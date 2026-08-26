import AVFoundation
import CoreImage
import CoreVideo
import Foundation

enum OrbiCoreImageVideoStitcher {
    static func stitchVideo(
        bundle: OrbiRawBundle,
        outputURL: URL,
        width: Int = 1920,
        height: Int = 960,
        maxFrameRate: Int32 = 30
    ) async throws {
        let sources = bundle.videoSources
            .sorted { ($0.channel ?? Int.max, $0.path) < ($1.channel ?? Int.max, $1.path) }
            .prefix(4)
        guard sources.count >= 2 else {
            throw OrbiServiceError.transferUnavailable("GPU video stitch needs at least two camera MP4 files; found \(sources.count).")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        var readers: [SourceReader] = []
        for source in sources {
            readers.append(try await SourceReader(source: source, url: bundle.directory.appendingPathComponent(source.path)))
        }
        defer {
            readers.forEach { $0.cancel() }
        }

        guard let firstReader = readers.first else {
            throw OrbiServiceError.transferUnavailable("No readable raw video sources were found for GPU stitching.")
        }
        let duration = readers.reduce(firstReader.duration) { shortest, reader in
            CMTimeCompare(reader.duration, shortest) < 0 ? reader.duration : shortest
        }
        let frameRate = min(maxFrameRate, max(1, firstReader.nominalFrameRate))
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        let frameCount = max(1, Int(CMTimeGetSeconds(duration) * Double(frameRate)))

        let writer = try makeWriter(outputURL: outputURL, width: width, height: height)
        let input = writer.input
        let adaptor = writer.adaptor
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let kernel = try makeKernel()
        let projections = readers.map { OrbiCameraProjection(source: $0.source) }
        let renderBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        readers.forEach { $0.start() }
        var sourceFrames = readers.map { $0.nextFrame() }
        var renderedFrames = 0

        while renderedFrames < frameCount {
            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(renderedFrames))
            updateFrames(&sourceFrames, readers: readers, presentationTime: presentationTime)
            guard sourceFrames.contains(where: { $0 != nil }) else { break }

            guard input.isReadyForMoreMediaData else {
                try await Task.sleep(nanoseconds: 5_000_000)
                continue
            }
            guard let output = createOutputPixelBuffer(adaptor: adaptor, width: width, height: height) else {
                throw OrbiServiceError.transferUnavailable("Cannot allocate GPU stitched video frame.")
            }

            let image = try stitchedImage(
                frames: sourceFrames,
                projections: projections,
                kernel: kernel,
                width: width,
                height: height
            )
            ciContext.render(image, to: output, bounds: renderBounds, colorSpace: colorSpace)

            guard adaptor.append(output, withPresentationTime: presentationTime) else {
                throw writer.assetWriter.error ?? OrbiServiceError.transferUnavailable("Cannot append GPU stitched video frame.")
            }
            renderedFrames += 1
        }

        input.markAsFinished()
        await writer.assetWriter.finishWriting()
        if writer.assetWriter.status != .completed {
            throw writer.assetWriter.error ?? OrbiServiceError.transferUnavailable("GPU ORBI stitched video export failed.")
        }
    }

    private struct WriterParts {
        let assetWriter: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
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
            return SourceFrame(
                pixelBuffer: pixelBuffer,
                time: CMSampleBufferGetPresentationTimeStamp(sample)
            )
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
                    AVVideoAverageBitRateKey: width * height * 6
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
            throw OrbiServiceError.transferUnavailable("Cannot add GPU stitched video input to writer.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? OrbiServiceError.transferUnavailable("Cannot start GPU ORBI stitched video writer.")
        }
        writer.startSession(atSourceTime: .zero)
        return WriterParts(assetWriter: writer, input: input, adaptor: adaptor)
    }

    private static func updateFrames(_ frames: inout [SourceFrame?], readers: [SourceReader], presentationTime: CMTime) {
        for index in readers.indices {
            while let frame = frames[index],
                  CMTimeCompare(frame.time, presentationTime) < 0 {
                frames[index] = readers[index].nextFrame()
            }
        }
    }

    private static func stitchedImage(
        frames: [SourceFrame?],
        projections: [OrbiCameraProjection],
        kernel: CIKernel,
        width: Int,
        height: Int
    ) throws -> CIImage {
        let images = (0..<4).map { index -> CIImage in
            if index < frames.count, let pixelBuffer = frames[index]?.pixelBuffer {
                return CIImage(cvPixelBuffer: pixelBuffer)
            }
            return CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var arguments: [Any] = images
        arguments.append(Float(projections.count))
        for index in 0..<4 {
            arguments.append(contentsOf: cameraVectors(projections, images: images, index: index))
        }
        arguments.append(CIVector(x: CGFloat(width), y: CGFloat(height), z: 0, w: 0))
        guard let image = kernel.apply(
            extent: CGRect(x: 0, y: 0, width: width, height: height),
            roiCallback: { _, rect in rect },
            arguments: arguments
        ) else {
            throw OrbiServiceError.transferUnavailable("Core Image stitch kernel did not produce a frame.")
        }
        return image
    }

    private static func cameraVectors(_ projections: [OrbiCameraProjection], images: [CIImage], index: Int) -> [CIVector] {
        let imageSize = index < images.count ? images[index].extent.size : CGSize(width: 1, height: 1)
        guard index < projections.count else {
            return [
                CIVector(x: 1, y: 0, z: 0, w: 0),
                CIVector(x: 0, y: 1, z: 0, w: 0),
                CIVector(x: 0, y: 0, z: 1, w: 0),
                CIVector(x: 2.0 * .pi / 3.0, y: 2.0 * .pi / 3.0, z: 0.5, w: 0.5),
                CIVector(x: 0, y: 0, z: 0, w: 0),
                CIVector(x: max(1, imageSize.width), y: max(1, imageSize.height), z: 0, w: 0)
            ]
        }
        let projection = projections[index]
        let matrix = projection.rotation.m
        let calibration = projection.calibration
        return [
            CIVector(x: matrix[0], y: matrix[3], z: matrix[6], w: 0),
            CIVector(x: matrix[1], y: matrix[4], z: matrix[7], w: 0),
            CIVector(x: matrix[2], y: matrix[5], z: matrix[8], w: 0),
            CIVector(
                x: projection.horizontalFOV,
                y: projection.verticalFOV,
                z: calibration?.ppx ?? 0.5,
                w: calibration?.ppy ?? 0.5
            ),
            CIVector(
                x: calibration?.maxTheta ?? max(projection.horizontalFOV, projection.verticalFOV) / 2.0,
                y: calibration?.k1 ?? 0,
                z: calibration?.k2 ?? 0,
                w: calibration?.k3 ?? 0
            ),
            CIVector(x: max(1, imageSize.width), y: max(1, imageSize.height), z: calibration?.k4 ?? 0, w: 0)
        ]
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

    private static func makeKernel() throws -> CIKernel {
        guard let kernel = CIKernel(source: kernelSource) else {
            throw OrbiServiceError.transferUnavailable("Cannot compile ORBI Core Image stitch kernel.")
        }
        return kernel
    }

    private static let kernelSource = """
    vec3 orbiLocal(vec3 direction, vec4 c0, vec4 c1, vec4 c2)
    {
        return vec3(dot(c0.xyz, direction), dot(c1.xyz, direction), dot(c2.xyz, direction));
    }

    vec3 orbiSampleInfo(vec3 direction, vec4 c0, vec4 c1, vec4 c2, vec4 fovCenter, vec4 dist)
    {
        vec3 local = orbiLocal(direction, c0, c1, c2);
        if (local.z <= 0.0) {
            return vec3(-1.0, -1.0, -1.0);
        }
        float angleX = atan(local.x, local.z);
        float angleY = atan(local.y, sqrt(local.x * local.x + local.z * local.z));
        if (abs(angleX) > fovCenter.x * 0.5 || abs(angleY) > fovCenter.y * 0.5) {
            return vec3(-1.0, -1.0, -1.0);
        }

        float theta = sqrt(angleX * angleX + angleY * angleY);
        float maxTheta = max(0.0001, dist.x);
        float normalized = theta / maxTheta;
        float r2 = normalized * normalized;
        float radial = normalized * (1.0 + dist.y * r2 + dist.z * r2 * r2 + dist.w * r2 * r2 * r2);
        float directionScale = theta > 0.000001 ? radial / theta : 0.0;
        vec2 uv = vec2(
            fovCenter.z + angleX * directionScale * 0.5,
            fovCenter.w - angleY * directionScale * 0.5
        );
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return vec3(-1.0, -1.0, -1.0);
        }
        return vec3(uv, local.z);
    }

    vec4 orbiFetch(sampler source, vec2 uv, vec4 sourceSize)
    {
        vec2 pixel = vec2(uv.x * max(1.0, sourceSize.x - 1.0), uv.y * max(1.0, sourceSize.y - 1.0));
        return sample(source, samplerTransform(source, pixel));
    }

    kernel vec4 orbiStitch(
        sampler source0, sampler source1, sampler source2, sampler source3,
        float sourceCount,
        vec4 c00, vec4 c01, vec4 c02, vec4 p0, vec4 d0, vec4 s0,
        vec4 c10, vec4 c11, vec4 c12, vec4 p1, vec4 d1, vec4 s1,
        vec4 c20, vec4 c21, vec4 c22, vec4 p2, vec4 d2, vec4 s2,
        vec4 c30, vec4 c31, vec4 c32, vec4 p3, vec4 d3, vec4 s3,
        vec4 outputSize
    )
    {
        vec2 dc = destCoord();
        float yaw = (dc.x / max(1.0, outputSize.x - 1.0) - 0.5) * 6.28318530718;
        float pitch = (0.5 - dc.y / max(1.0, outputSize.y - 1.0)) * 3.14159265359;
        float cp = cos(pitch);
        vec3 direction = vec3(cp * sin(yaw), sin(pitch), cp * cos(yaw));

        vec3 best = vec3(-1.0, -1.0, -1.0);
        float bestIndex = -1.0;
        vec3 candidate = orbiSampleInfo(direction, c00, c01, c02, p0, d0);
        if (sourceCount > 0.0 && candidate.z > best.z) { best = candidate; bestIndex = 0.0; }
        candidate = orbiSampleInfo(direction, c10, c11, c12, p1, d1);
        if (sourceCount > 1.0 && candidate.z > best.z) { best = candidate; bestIndex = 1.0; }
        candidate = orbiSampleInfo(direction, c20, c21, c22, p2, d2);
        if (sourceCount > 2.0 && candidate.z > best.z) { best = candidate; bestIndex = 2.0; }
        candidate = orbiSampleInfo(direction, c30, c31, c32, p3, d3);
        if (sourceCount > 3.0 && candidate.z > best.z) { best = candidate; bestIndex = 3.0; }

        if (bestIndex < 0.0) {
            return vec4(0.0, 0.0, 0.0, 1.0);
        }
        if (bestIndex < 0.5) { return orbiFetch(source0, best.xy, s0); }
        if (bestIndex < 1.5) { return orbiFetch(source1, best.xy, s1); }
        if (bestIndex < 2.5) { return orbiFetch(source2, best.xy, s2); }
        return orbiFetch(source3, best.xy, s3);
    }
    """
}
