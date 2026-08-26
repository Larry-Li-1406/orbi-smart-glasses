import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(UIKit)
import UIKit
#endif

enum MediaThumbnailService {
    static func saveThumbnail(for mediaURL: URL, to thumbnailURL: URL) async throws {
        try FileManager.default.createDirectory(at: thumbnailURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        #if canImport(AVFoundation) && canImport(UIKit)
        let asset = AVURLAsset(url: mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let time = CMTime(seconds: 0.35, preferredTimescale: 600)
        let image = try await generator.image(at: time).image
        let uiImage = UIImage(cgImage: image)
        guard let data = uiImage.pngData() else { return }
        try data.write(to: thumbnailURL, options: .atomic)
        #endif
    }
}
