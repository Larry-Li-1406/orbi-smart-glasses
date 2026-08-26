import AVFoundation
import CoreVideo
import Foundation
import Metal

enum OrbiMetalVideoStitcher {
    static func stitchVideo(
        bundle: OrbiRawBundle,
        outputURL: URL,
        width: Int = 1920,
        height: Int = 960,
        maxFrameRate: Int32 = 30
    ) async throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw OrbiServiceError.transferUnavailable("Metal is not available on this device.")
        }
        let pipeline = try makePipeline(device: device)
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard let textureCache else {
            throw OrbiServiceError.transferUnavailable("Cannot create Metal texture cache.")
        }

        let sources = bundle.videoSources
            .sorted { ($0.channel ?? Int.max, $0.path) < ($1.channel ?? Int.max, $1.path) }
            .prefix(4)
        guard sources.count >= 2 else {
            throw OrbiServiceError.transferUnavailable("Metal video stitch needs at least two camera MP4 files; found \(sources.count).")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        var readers: [SourceReader] = []
        for source in sources {
            readers.append(try await SourceReader(source: source, url: bundle.directory.appendingPathComponent(source.path)))
        }
        defer { readers.forEach { $0.cancel() } }

        guard let firstReader = readers.first else {
            throw OrbiServiceError.transferUnavailable("No readable raw video sources were found for Metal stitching.")
        }
        let duration = readers.reduce(firstReader.duration) { shortest, reader in
            CMTimeCompare(reader.duration, shortest) < 0 ? reader.duration : shortest
        }
        let frameRate = min(maxFrameRate, max(1, firstReader.nominalFrameRate))
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        let frameCount = max(1, Int(CMTimeGetSeconds(duration) * Double(frameRate)))
        let writer = try makeWriter(outputURL: outputURL, width: width, height: height)

        readers.forEach { $0.start() }
        var sourceFrames = readers.map { $0.nextFrame() }
        var renderedFrames = 0

        while renderedFrames < frameCount {
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(renderedFrames))
            updateFrames(&sourceFrames, readers: readers, presentationTime: presentationTime)
            guard sourceFrames.contains(where: { $0 != nil }) else { break }

            guard writer.input.isReadyForMoreMediaData else {
                try await Task.sleep(nanoseconds: 5_000_000)
                continue
            }
            guard let outputBuffer = createOutputPixelBuffer(adaptor: writer.adaptor, width: width, height: height),
                  let outputTexture = makeTexture(from: outputBuffer, textureCache: textureCache, pixelFormat: .bgra8Unorm, usage: [.shaderWrite]) else {
                throw OrbiServiceError.transferUnavailable("Cannot allocate Metal stitched video frame.")
            }

            let sourceTextures = try makeSourceTextures(frames: sourceFrames, textureCache: textureCache, device: device)
            let uniforms = makeUniformBuffer(device: device, readers: readers, sourceTextures: sourceTextures, width: width, height: height)
            try encodeFrame(
                commandQueue: commandQueue,
                pipeline: pipeline,
                uniforms: uniforms,
                sourceTextures: sourceTextures,
                outputTexture: outputTexture,
                width: width,
                height: height
            )

            guard writer.adaptor.append(outputBuffer, withPresentationTime: presentationTime) else {
                throw writer.assetWriter.error ?? OrbiServiceError.transferUnavailable("Cannot append Metal stitched video frame.")
            }
            renderedFrames += 1
        }

        writer.input.markAsFinished()
        await writer.assetWriter.finishWriting()
        if writer.assetWriter.status != .completed {
            throw writer.assetWriter.error ?? OrbiServiceError.transferUnavailable("Metal ORBI stitched video export failed.")
        }
    }

    private struct WriterParts {
        let assetWriter: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    private struct SourceTexture {
        let texture: MTLTexture
        let width: Int
        let height: Int
        let active: Bool
    }

    private final class SourceReader {
        let source: OrbiRawBundle.CameraSource
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let duration: CMTime
        let nominalFrameRate: Int32

        init(source: OrbiRawBundle.CameraSource, url: URL) async throws {
            self.source = source
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                throw OrbiServiceError.transferUnavailable("Raw MP4 \(source.path) has no video track.")
            }
            self.duration = try await asset.load(.duration)
            let frameRate = try await track.load(.nominalFrameRate)
            self.nominalFrameRate = Int32(max(1, min(60, frameRate.rounded())))
            self.reader = try AVAssetReader(asset: asset)
            self.output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw OrbiServiceError.transferUnavailable("Cannot attach raw MP4 reader for \(source.path).")
            }
            reader.add(output)
        }

        func start() {
            reader.startReading()
        }

        func cancel() {
            reader.cancelReading()
        }

        func nextFrame() -> SourceFrame? {
            guard let sample = output.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                return nil
            }
            return SourceFrame(pixelBuffer: pixelBuffer, time: CMSampleBufferGetPresentationTimeStamp(sample))
        }
    }

    private struct SourceFrame {
        let pixelBuffer: CVPixelBuffer
        let time: CMTime
    }

    private static func makeWriter(outputURL: URL, width: Int, height: Int) throws -> WriterParts {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: width * height * 8
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else {
            throw OrbiServiceError.transferUnavailable("Cannot add Metal stitched video input to writer.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? OrbiServiceError.transferUnavailable("Cannot start Metal ORBI stitched video writer.")
        }
        writer.startSession(atSourceTime: .zero)
        return WriterParts(assetWriter: writer, input: input, adaptor: adaptor)
    }

    private static func makePipeline(device: MTLDevice) throws -> MTLComputePipelineState {
        let library = try device.makeLibrary(source: metalSource, options: nil)
        guard let function = library.makeFunction(name: "orbi_stitch_kernel") else {
            throw OrbiServiceError.transferUnavailable("Cannot find ORBI Metal stitch kernel.")
        }
        return try device.makeComputePipelineState(function: function)
    }

    private static func updateFrames(_ frames: inout [SourceFrame?], readers: [SourceReader], presentationTime: CMTime) {
        for index in readers.indices {
            while let frame = frames[index],
                  CMTimeCompare(frame.time, presentationTime) < 0 {
                frames[index] = readers[index].nextFrame()
            }
        }
    }

    private static func makeSourceTextures(frames: [SourceFrame?], textureCache: CVMetalTextureCache, device: MTLDevice) throws -> [SourceTexture] {
        try (0..<4).map { index in
            if index < frames.count,
               let pixelBuffer = frames[index]?.pixelBuffer,
               let texture = makeTexture(from: pixelBuffer, textureCache: textureCache, pixelFormat: .bgra8Unorm, usage: [.shaderRead]) {
                return SourceTexture(texture: texture, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer), active: true)
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
            descriptor.usage = [.shaderRead]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw OrbiServiceError.transferUnavailable("Cannot allocate Metal placeholder texture.")
            }
            var black: UInt32 = 0xff000000
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &black, bytesPerRow: 4)
            return SourceTexture(texture: texture, width: 1, height: 1, active: false)
        }
    }

    private static func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        textureCache: CVMetalTextureCache,
        pixelFormat: MTLPixelFormat,
        usage: MTLTextureUsage
    ) -> MTLTexture? {
        var cvTexture: CVMetalTexture?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            0,
            &cvTexture
        )
        guard let texture = cvTexture.flatMap(CVMetalTextureGetTexture) else { return nil }
        texture.label = usage.contains(.shaderWrite) ? "ORBI stitched output" : "ORBI raw source"
        return texture
    }

    private static func createOutputPixelBuffer(adaptor: AVAssetWriterInputPixelBufferAdaptor, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        }
        if pixelBuffer == nil {
            CVPixelBufferCreate(
                nil,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                &pixelBuffer
            )
        }
        return pixelBuffer
    }

    private static func makeUniformBuffer(
        device: MTLDevice,
        readers: [SourceReader],
        sourceTextures: [SourceTexture],
        width: Int,
        height: Int
    ) -> MTLBuffer {
        var floats: [Float] = []
        floats.append(Float(width))
        floats.append(Float(height))
        floats.append(Float(readers.count))
        floats.append(0)
        for index in 0..<4 {
            appendCamera(index: index, readers: readers, sourceTextures: sourceTextures, floats: &floats)
        }
        return device.makeBuffer(bytes: floats, length: floats.count * MemoryLayout<Float>.stride, options: .storageModeShared)!
    }

    private static func appendCamera(index: Int, readers: [SourceReader], sourceTextures: [SourceTexture], floats: inout [Float]) {
        guard index < readers.count else {
            floats += [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                Float(2.0 * Double.pi / 3.0), Float(2.0 * Double.pi / 3.0), 0.5, 0.5,
                Float(Double.pi / 3.0), 0, 0, 0,
                1, 1, 0, 0
            ]
            return
        }
        let projection = OrbiCameraProjection(source: readers[index].source)
        let matrix = projection.rotation.m
        let calibration = projection.calibration
        let texture = sourceTextures[index]
        floats.append(Float(matrix[0]))
        floats.append(Float(matrix[3]))
        floats.append(Float(matrix[6]))
        floats.append(0)
        floats.append(Float(matrix[1]))
        floats.append(Float(matrix[4]))
        floats.append(Float(matrix[7]))
        floats.append(0)
        floats.append(Float(matrix[2]))
        floats.append(Float(matrix[5]))
        floats.append(Float(matrix[8]))
        floats.append(0)
        floats.append(Float(projection.horizontalFOV))
        floats.append(Float(projection.verticalFOV))
        floats.append(Float(calibration?.ppx ?? 0.5))
        floats.append(Float(calibration?.ppy ?? 0.5))
        floats.append(Float(calibration?.maxTheta ?? max(projection.horizontalFOV, projection.verticalFOV) / 2.0))
        floats.append(Float(calibration?.k1 ?? 0))
        floats.append(Float(calibration?.k2 ?? 0))
        floats.append(Float(calibration?.k3 ?? 0))
        floats.append(Float(texture.width))
        floats.append(Float(texture.height))
        floats.append(Float(calibration?.k4 ?? 0))
        floats.append(texture.active ? 1 : 0)
    }

    private static func encodeFrame(
        commandQueue: MTLCommandQueue,
        pipeline: MTLComputePipelineState,
        uniforms: MTLBuffer,
        sourceTextures: [SourceTexture],
        outputTexture: MTLTexture,
        width: Int,
        height: Int
    ) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw OrbiServiceError.transferUnavailable("Cannot create Metal command buffer.")
        }
        encoder.setComputePipelineState(pipeline)
        for index in 0..<4 {
            encoder.setTexture(sourceTextures[index].texture, index: index)
        }
        encoder.setTexture(outputTexture, index: 4)
        encoder.setBuffer(uniforms, offset: 0, index: 0)
        let threadWidth = min(16, pipeline.threadExecutionWidth)
        let threadsPerGroup = MTLSize(width: threadWidth, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (width + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
    }

    private static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CameraParams {
        float4 c0;
        float4 c1;
        float4 c2;
        float4 fovCenter;
        float4 distortion;
        float4 sourceSize;
    };

    struct Uniforms {
        float4 output;
        CameraParams cameras[4];
    };

    struct Candidate {
        float2 uv;
        float score;
        bool valid;
    };

    static inline float3 localDirection(float3 direction, constant CameraParams &camera)
    {
        return float3(dot(camera.c0.xyz, direction), dot(camera.c1.xyz, direction), dot(camera.c2.xyz, direction));
    }

    static inline Candidate candidateFor(float3 direction, constant CameraParams &camera)
    {
        Candidate candidate;
        candidate.uv = float2(-1.0, -1.0);
        candidate.score = -1.0;
        candidate.valid = false;
        if (camera.sourceSize.w < 0.5) {
            return candidate;
        }

        float3 local = localDirection(direction, camera);
        if (local.z <= 0.0) {
            return candidate;
        }

        float angleX = atan2(local.x, local.z);
        float angleY = atan2(local.y, sqrt(local.x * local.x + local.z * local.z));
        if (abs(angleX) > camera.fovCenter.x * 0.5 || abs(angleY) > camera.fovCenter.y * 0.5) {
            return candidate;
        }

        float theta = sqrt(angleX * angleX + angleY * angleY);
        float maxTheta = max(0.0001, camera.distortion.x);
        float normalized = theta / maxTheta;
        float r2 = normalized * normalized;
        float radial = normalized * (1.0
            + camera.distortion.y * r2
            + camera.distortion.z * r2 * r2
            + camera.distortion.w * r2 * r2 * r2
            + camera.sourceSize.z * r2 * r2 * r2 * r2);
        float directionScale = theta > 0.000001 ? radial / theta : 0.0;
        float2 uv = float2(
            camera.fovCenter.z + angleX * directionScale * 0.5,
            camera.fovCenter.w - angleY * directionScale * 0.5
        );
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return candidate;
        }

        candidate.uv = uv;
        candidate.score = local.z;
        candidate.valid = true;
        return candidate;
    }

    static inline float4 readSource(texture2d<float, access::sample> source, float2 uv, constant CameraParams &camera)
    {
        constexpr sampler sourceSampler(coord::pixel, address::clamp_to_edge, filter::linear);
        float2 pixel = float2(
            uv.x * max(1.0, camera.sourceSize.x - 1.0),
            uv.y * max(1.0, camera.sourceSize.y - 1.0)
        );
        return source.sample(sourceSampler, pixel);
    }

    kernel void orbi_stitch_kernel(
        texture2d<float, access::sample> source0 [[texture(0)]],
        texture2d<float, access::sample> source1 [[texture(1)]],
        texture2d<float, access::sample> source2 [[texture(2)]],
        texture2d<float, access::sample> source3 [[texture(3)]],
        texture2d<float, access::write> output [[texture(4)]],
        constant Uniforms &uniforms [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= uint(uniforms.output.x) || gid.y >= uint(uniforms.output.y)) {
            return;
        }

        float yaw = (float(gid.x) / max(1.0, uniforms.output.x - 1.0) - 0.5) * 6.28318530718;
        float pitch = (0.5 - float(gid.y) / max(1.0, uniforms.output.y - 1.0)) * 3.14159265359;
        float cp = cos(pitch);
        float3 direction = float3(cp * sin(yaw), sin(pitch), cp * cos(yaw));

        Candidate best;
        best.uv = float2(-1.0, -1.0);
        best.score = -1.0;
        best.valid = false;
        int bestIndex = -1;
        Candidate second = best;
        int secondIndex = -1;

        for (int index = 0; index < 4; ++index) {
            Candidate candidate = candidateFor(direction, uniforms.cameras[index]);
            if (!candidate.valid) {
                continue;
            }
            if (!best.valid || candidate.score > best.score) {
                second = best;
                secondIndex = bestIndex;
                best = candidate;
                bestIndex = index;
            } else if (!second.valid || candidate.score > second.score) {
                second = candidate;
                secondIndex = index;
            }
        }

        if (!best.valid) {
            output.write(float4(0.0, 0.0, 0.0, 1.0), gid);
            return;
        }

        float4 color;
        if (bestIndex == 0) { color = readSource(source0, best.uv, uniforms.cameras[0]); }
        else if (bestIndex == 1) { color = readSource(source1, best.uv, uniforms.cameras[1]); }
        else if (bestIndex == 2) { color = readSource(source2, best.uv, uniforms.cameras[2]); }
        else { color = readSource(source3, best.uv, uniforms.cameras[3]); }

        if (second.valid && secondIndex >= 0) {
            float scoreDelta = clamp((best.score - second.score) * 8.0, 0.0, 1.0);
            float blend = 1.0 - smoothstep(0.0, 1.0, scoreDelta);
            if (blend > 0.01) {
                float4 secondColor;
                if (secondIndex == 0) { secondColor = readSource(source0, second.uv, uniforms.cameras[0]); }
                else if (secondIndex == 1) { secondColor = readSource(source1, second.uv, uniforms.cameras[1]); }
                else if (secondIndex == 2) { secondColor = readSource(source2, second.uv, uniforms.cameras[2]); }
                else { secondColor = readSource(source3, second.uv, uniforms.cameras[3]); }
                color = mix(color, secondColor, blend * 0.5);
            }
        }

        output.write(float4(color.rgb, 1.0), gid);
    }
    """
}
