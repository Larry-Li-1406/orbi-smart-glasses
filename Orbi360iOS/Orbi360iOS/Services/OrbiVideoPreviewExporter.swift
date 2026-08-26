import AVFoundation
import CoreGraphics
import Foundation

enum OrbiVideoPreviewExporter {
    static func exportPreview(bundle: OrbiRawBundle, outputURL: URL) async throws {
        let sources = bundle.videoSources
            .sorted { ($0.channel ?? Int.max, $0.path) < ($1.channel ?? Int.max, $1.path) }
            .prefix(4)
        guard !sources.isEmpty else {
            throw OrbiServiceError.transferUnavailable("No raw MP4 source files were found in the downloaded video bundle.")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let assets = sources.map { AVURLAsset(url: bundle.directory.appendingPathComponent($0.path)) }
        let composition = AVMutableComposition()
        var videoLayers: [(AVMutableCompositionTrack, AVAssetTrack, Int)] = []
        var shortestDuration: CMTime?

        for (index, asset) in assets.enumerated() {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let assetVideoTrack = videoTracks.first,
                  let compositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                continue
            }

            let duration = try await asset.load(.duration)
            shortestDuration = shortestDuration.map { CMTimeMinimum($0, duration) } ?? duration
            videoLayers.append((compositionTrack, assetVideoTrack, index))
        }

        guard let duration = shortestDuration, !videoLayers.isEmpty else {
            throw OrbiServiceError.transferUnavailable("The raw video bundle does not contain readable video tracks.")
        }

        for (compositionTrack, assetTrack, _) in videoLayers {
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: assetTrack,
                at: .zero
            )
        }
        try await addFirstAudioTrack(from: assets, to: composition, duration: duration)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: 1920, height: videoLayers.count <= 2 ? 540 : 1080)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        for (compositionTrack, assetTrack, index) in videoLayers {
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
            layer.setTransform(
                try await transform(for: assetTrack, index: index, count: videoLayers.count, renderSize: videoComposition.renderSize),
                at: .zero
            )
            layerInstructions.append(layer)
        }
        instruction.layerInstructions = layerInstructions
        videoComposition.instructions = [instruction]

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw OrbiServiceError.transferUnavailable("Cannot create video exporter for raw ORBI preview.")
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true

        try await exporter.export(to: outputURL, as: .mp4)
    }

    private static func addFirstAudioTrack(from assets: [AVURLAsset], to composition: AVMutableComposition, duration: CMTime) async throws {
        for asset in assets {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let audioTrack = audioTracks.first,
                  let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                continue
            }
            let assetDuration = try await asset.load(.duration)
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, assetDuration)),
                of: audioTrack,
                at: .zero
            )
            return
        }
    }

    private static func transform(for track: AVAssetTrack, index: Int, count: Int, renderSize: CGSize) async throws -> CGAffineTransform {
        let columns = count <= 1 ? 1 : 2
        let rows = count <= 2 ? 1 : 2
        let cellSize = CGSize(width: renderSize.width / CGFloat(columns), height: renderSize.height / CGFloat(rows))
        let column = index % columns
        let row = index / columns

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let normalizedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let normalizedSize = CGSize(width: abs(normalizedRect.width), height: abs(normalizedRect.height))
        guard normalizedSize.width > 0, normalizedSize.height > 0 else {
            return .identity
        }

        let scale = min(cellSize.width / normalizedSize.width, cellSize.height / normalizedSize.height)
        let fittedSize = CGSize(width: normalizedSize.width * scale, height: normalizedSize.height * scale)
        let x = CGFloat(column) * cellSize.width + (cellSize.width - fittedSize.width) / 2
        let y = CGFloat(row) * cellSize.height + (cellSize.height - fittedSize.height) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -normalizedRect.minX, y: -normalizedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }
}
