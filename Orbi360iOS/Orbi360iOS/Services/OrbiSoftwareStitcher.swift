import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

enum OrbiSoftwareStitcher {
    static func stitchPhoto(bundle: OrbiRawBundle, outputURL: URL, width: Int = 4760, height: Int = 2380) throws {
        #if canImport(CoreGraphics)
        let photoSources = bundle.photoSources
        guard photoSources.count >= 2 else {
            throw OrbiServiceError.transferUnavailable("Photo stitch needs at least two camera images; found \(photoSources.count).")
        }
        let images = try photoSources.map { source -> (OrbiRawBundle.CameraSource, CGImage) in
            let url = bundle.directory.appendingPathComponent(source.path)
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw OrbiServiceError.transferUnavailable("Cannot decode camera image \(source.path).")
            }
            return (source, image)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OrbiServiceError.transferUnavailable("Cannot allocate stitch output buffer.")
        }

        let calibrated = images.map { source, image in
            CalibratedImage(projection: OrbiCameraProjection(source: source), image: image)
        }

        for y in 0..<height {
            for x in 0..<width {
                let direction = OrbiVec3.fromEquirectangular(x: x, y: y, width: width, height: height)
                if let sample = bestSample(for: direction, cameras: calibrated) {
                    drawNearestPixel(from: sample.image, u: sample.uv.x, v: sample.uv.y, to: context, x: x, y: y)
                }
            }
        }

        guard let stitched = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw OrbiServiceError.transferUnavailable("Cannot create stitched JPEG.")
        }
        CGImageDestinationAddImage(destination, stitched, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OrbiServiceError.transferUnavailable("Cannot write stitched JPEG.")
        }
        #else
        throw OrbiServiceError.transferUnavailable("Software stitching requires CoreGraphics.")
        #endif
    }

    #if canImport(CoreGraphics)
    private struct CalibratedImage {
        let projection: OrbiCameraProjection
        let image: CGImage

        init(projection: OrbiCameraProjection, image: CGImage) {
            self.projection = projection
            self.image = image
        }
    }

    private static func bestSample(for direction: OrbiVec3, cameras: [CalibratedImage]) -> (image: CGImage, uv: OrbiVec2)? {
        var best: (camera: CalibratedImage, uv: OrbiVec2, score: Double)?
        for camera in cameras {
            guard let sample = camera.projection.uv(for: direction) else { continue }
            if best == nil || sample.score > best!.score {
                best = (camera, sample.uv, sample.score)
            }
        }
        return best.map { ($0.camera.image, $0.uv) }
    }

    private static func drawNearestPixel(from image: CGImage, u: Double, v: Double, to context: CGContext, x: Int, y: Int) {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return
        }
        let sourceX = min(image.width - 1, max(0, Int(u * Double(image.width - 1))))
        let sourceY = min(image.height - 1, max(0, Int(v * Double(image.height - 1))))
        let bitsPerPixel = image.bitsPerPixel
        let bytesPerPixel = max(1, bitsPerPixel / 8)
        let sourceOffset = sourceY * image.bytesPerRow + sourceX * bytesPerPixel
        let r = bytes[sourceOffset]
        let g = bytes[sourceOffset + min(1, bytesPerPixel - 1)]
        let b = bytes[sourceOffset + min(2, bytesPerPixel - 1)]
        context.setFillColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }
    #endif
}
