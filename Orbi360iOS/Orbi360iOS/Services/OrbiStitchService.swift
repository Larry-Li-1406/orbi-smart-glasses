import Foundation

enum OrbiStitchService {
    static func materializeDownloadedMedia(_ item: OrbiMediaItem) async throws {
        try OrbiLocalMediaStore.prepareDirectories()
        let bundle = try OrbiRawBundleParser.parse(directory: item.rawBundleURL, mediaName: item.name)

        if item.type == .photo, bundle.photoSources.count >= 2 {
            try OrbiSoftwareStitcher.stitchPhoto(bundle: bundle, outputURL: item.localURL)
            try await MediaThumbnailService.saveThumbnail(for: item.localURL, to: item.thumbnailURL)
            return
        }

        if item.type == .video, bundle.videoSources.count > 1 {
            do {
                try await OrbiMetalVideoStitcher.stitchVideo(bundle: bundle, outputURL: item.localURL)
            } catch {
                do {
                    try await OrbiCoreImageVideoStitcher.stitchVideo(bundle: bundle, outputURL: item.localURL)
                } catch {
                    do {
                        try await OrbiVideoStitcher.stitchVideo(bundle: bundle, outputURL: item.localURL)
                    } catch {
                        try await OrbiVideoPreviewExporter.exportPreview(bundle: bundle, outputURL: item.localURL)
                    }
                }
            }
            try await MediaThumbnailService.saveThumbnail(for: item.localURL, to: item.thumbnailURL)
            try saveDebugManifest(bundle, for: item)
            return
        }

        if let readyMedia = firstReadyMedia(in: item.rawBundleURL, type: item.type) {
            if FileManager.default.fileExists(atPath: item.localURL.path) {
                try FileManager.default.removeItem(at: item.localURL)
            }
            try FileManager.default.copyItem(at: readyMedia, to: item.localURL)
            try await MediaThumbnailService.saveThumbnail(for: item.localURL, to: item.thumbnailURL)
            return
        }

        try saveDebugManifest(bundle, for: item)
        throw OrbiServiceError.transferUnavailable(
            "Raw media downloaded for \(item.name): \(bundle.videoSources.count) video sources, \(bundle.photoSources.count) photo sources, \(bundle.imuFiles.count) IMU files. \(videoSourceSummary(bundle)) The bundle is saved at \(item.rawBundleURL.path)."
        )
    }

    private static func firstReadyMedia(in directory: URL, type: MediaType) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        let allowedExtensions: Set<String> = type == .photo ? ["jpg", "jpeg"] : ["mp4", "mov"]
        return files.first { allowedExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func saveDebugManifest(_ bundle: OrbiRawBundle, for item: OrbiMediaItem) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bundle)
        try data.write(to: item.rawBundleURL.appendingPathComponent("orbi-ios-raw-manifest.json"), options: Data.WritingOptions.atomic)
    }

    private static func videoSourceSummary(_ bundle: OrbiRawBundle) -> String {
        let summaries = bundle.videoSources.compactMap { source -> String? in
            guard let track = source.mp4Info?.primaryVideoTrack else { return nil }
            let size = [track.width, track.height].compactMap { $0 }.map(String.init).joined(separator: "x")
            let codec = track.codec ?? "unknown"
            return [source.path, size.isEmpty ? nil : size, codec].compactMap { $0 }.joined(separator: " ")
        }
        return summaries.isEmpty ? "" : "Video tracks: \(summaries.joined(separator: ", "))."
    }
}
