import AVFoundation
import CoreVideo
import Foundation

enum OrbiVideoStitcher {
    static func stitchVideo(
        bundle: OrbiRawBundle,
        outputURL: URL,
        width: Int = 1920,
        height: Int = 960,
        maxFrameRate: Int32 = 24
    ) async throws {
        let sources = bundle.videoSources
            .sorted { ($0.channel ?? Int.max, $0.path) < ($1.channel ?? Int.max, $1.path) }
            .prefix(4)
        guard sources.count >= 2 else {
            throw OrbiServiceError.transferUnavailable("Video stitch needs at least two camera MP4 files; found \(sources.count).")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        var readers: [SourceReader] = []
        for source in sources {
            let reader = try await SourceReader(source: source, url: bundle.directory.appendingPathComponent(source.path))
            readers.append(reader)
        }
        defer {
            for reader in readers {
                reader.cancel()
            }
        }

        guard let firstReader = readers.first else {
            throw OrbiServiceError.transferUnavailable("No readable raw video sources were found.")
        }
        let duration = readers.reduce(firstReader.duration) { shortest, reader in
            CMTimeCompare(reader.duration, shortest) < 0 ? reader.duration : shortest
        }
        let frameRate = min(maxFrameRate, max(1, firstReader.nominalFrameRate))
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        let frameCount = max(1, Int(CMTimeGetSeconds(duration) * Double(frameRate)))

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: width * height * 4
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
            throw OrbiServiceError.transferUnavailable("Cannot add stitched video input to writer.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? OrbiServiceError.transferUnavailable("Cannot start ORBI stitched video writer.")
        }
        writer.startSession(atSourceTime: .zero)

        let projections = readers.map { OrbiCameraProjection(source: $0.source) }
        let mapping = buildMapping(width: width, height: height, projections: projections)

        for reader in readers {
            reader.start()
        }

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
                throw OrbiServiceError.transferUnavailable("Cannot allocate stitched video frame.")
            }
            render(mapping: mapping, sourceFrames: sourceFrames, output: output, width: width, height: height)
            guard adaptor.append(output, withPresentationTime: presentationTime) else {
                throw writer.error ?? OrbiServiceError.transferUnavailable("Cannot append stitched video frame.")
            }
            renderedFrames += 1
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? OrbiServiceError.transferUnavailable("ORBI stitched video export failed.")
        }
    }

    private struct MappingEntry {
        var sourceIndex: Int
        var u: Float
        var v: Float
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

    private static func updateFrames(_ frames: inout [SourceFrame?], readers: [SourceReader], presentationTime: CMTime) {
        for index in readers.indices {
            while let frame = frames[index],
                  CMTimeCompare(frame.time, presentationTime) < 0 {
                frames[index] = readers[index].nextFrame()
            }
        }
    }

    private static func buildMapping(width: Int, height: Int, projections: [OrbiCameraProjection]) -> [MappingEntry?] {
        var mapping = Array<MappingEntry?>(repeating: nil, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let direction = OrbiVec3.fromEquirectangular(x: x, y: y, width: width, height: height)
                var best: (index: Int, uv: OrbiVec2, score: Double)?
                for (index, projection) in projections.enumerated() {
                    guard let sample = projection.uv(for: direction) else { continue }
                    if best == nil || sample.score > best!.score {
                        best = (index, sample.uv, sample.score)
                    }
                }
                if let best {
                    mapping[y * width + x] = MappingEntry(sourceIndex: best.index, u: Float(best.uv.x), v: Float(best.uv.y))
                }
            }
        }
        return mapping
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

    private static func render(
        mapping: [MappingEntry?],
        sourceFrames: [SourceFrame?],
        output: CVPixelBuffer,
        width: Int,
        height: Int
    ) {
        let sourceBuffers = sourceFrames.map { $0?.pixelBuffer }
        for buffer in sourceBuffers.compactMap({ $0 }) {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
        }
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            for buffer in sourceBuffers.compactMap({ $0 }) {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            }
        }

        guard let outputBase = CVPixelBufferGetBaseAddress(output) else { return }
        let outputBytes = outputBase.assumingMemoryBound(to: UInt8.self)
        let outputStride = CVPixelBufferGetBytesPerRow(output)

        for y in 0..<height {
            for x in 0..<width {
                let outputOffset = y * outputStride + x * 4
                guard let entry = mapping[y * width + x],
                      entry.sourceIndex < sourceBuffers.count,
                      let source = sourceBuffers[entry.sourceIndex],
                      let sourceBase = CVPixelBufferGetBaseAddress(source) else {
                    outputBytes[outputOffset] = 0
                    outputBytes[outputOffset + 1] = 0
                    outputBytes[outputOffset + 2] = 0
                    outputBytes[outputOffset + 3] = 255
                    continue
                }

                let sourceWidth = CVPixelBufferGetWidth(source)
                let sourceHeight = CVPixelBufferGetHeight(source)
                let sourceStride = CVPixelBufferGetBytesPerRow(source)
                let sourceX = min(sourceWidth - 1, max(0, Int(entry.u * Float(max(1, sourceWidth - 1)))))
                let sourceY = min(sourceHeight - 1, max(0, Int(entry.v * Float(max(1, sourceHeight - 1)))))
                let sourceOffset = sourceY * sourceStride + sourceX * 4
                let sourceBytes = sourceBase.assumingMemoryBound(to: UInt8.self)

                outputBytes[outputOffset] = sourceBytes[sourceOffset]
                outputBytes[outputOffset + 1] = sourceBytes[sourceOffset + 1]
                outputBytes[outputOffset + 2] = sourceBytes[sourceOffset + 2]
                outputBytes[outputOffset + 3] = 255
            }
        }
    }
}
