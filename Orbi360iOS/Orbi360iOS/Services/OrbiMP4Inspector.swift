import Foundation

struct OrbiMP4Info: Codable, Hashable {
    struct Track: Codable, Hashable {
        var handlerType: String?
        var codec: String?
        var width: Int?
        var height: Int?
        var timescale: UInt32?
        var durationSeconds: Double?
    }

    var majorBrand: String?
    var compatibleBrands: [String]
    var tracks: [Track]
    var hasSphericalMetadata: Bool

    var primaryVideoTrack: Track? {
        tracks.first { $0.handlerType == "vide" } ?? tracks.first { $0.width != nil && $0.height != nil }
    }
}

enum OrbiMP4Inspector {
    static func inspect(url: URL) throws -> OrbiMP4Info {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try fileSize(at: url)
        let context = ParseContext()
        try parseRange(handle: handle, start: 0, end: fileSize, context: context, track: nil)
        return OrbiMP4Info(
            majorBrand: context.majorBrand,
            compatibleBrands: context.compatibleBrands,
            tracks: context.tracks.map { $0.build() },
            hasSphericalMetadata: context.hasSphericalMetadata
        )
    }

    private final class ParseContext {
        var majorBrand: String?
        var compatibleBrands: [String] = []
        var tracks: [TrackBuilder] = []
        var hasSphericalMetadata = false
    }

    private final class TrackBuilder {
        var handlerType: String?
        var codec: String?
        var width: Int?
        var height: Int?
        var timescale: UInt32?
        var durationSeconds: Double?

        func build() -> OrbiMP4Info.Track {
            OrbiMP4Info.Track(
                handlerType: handlerType,
                codec: codec,
                width: width,
                height: height,
                timescale: timescale,
                durationSeconds: durationSeconds
            )
        }
    }

    private struct Atom {
        var offset: UInt64
        var size: UInt64
        var headerSize: UInt64
        var type: String

        var payloadOffset: UInt64 { offset + headerSize }
        var payloadSize: UInt64 { size - headerSize }
        var endOffset: UInt64 { offset + size }
    }

    private static let containerTypes: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl", "edts", "udta", "dinf", "meta", "ilst"
    ]

    private static func parseRange(
        handle: FileHandle,
        start: UInt64,
        end: UInt64,
        context: ParseContext,
        track: TrackBuilder?
    ) throws {
        var cursor = start
        while cursor + 8 <= end {
            guard let atom = try readAtom(handle: handle, at: cursor, fileEnd: end) else { break }
            guard atom.size >= atom.headerSize, atom.endOffset <= end else { break }

            try parseAtom(handle: handle, atom: atom, context: context, track: track)
            guard atom.endOffset > cursor else { break }
            cursor = atom.endOffset
        }
    }

    private static func parseAtom(
        handle: FileHandle,
        atom: Atom,
        context: ParseContext,
        track: TrackBuilder?
    ) throws {
        switch atom.type {
        case "ftyp":
            try parseFileType(handle: handle, atom: atom, context: context)
        case "trak":
            let trackBuilder = TrackBuilder()
            try parseRange(
                handle: handle,
                start: atom.payloadOffset,
                end: atom.endOffset,
                context: context,
                track: trackBuilder
            )
            context.tracks.append(trackBuilder)
        case "tkhd":
            try parseTrackHeader(handle: handle, atom: atom, track: track)
        case "mdhd":
            try parseMediaHeader(handle: handle, atom: atom, track: track)
        case "hdlr":
            try parseHandler(handle: handle, atom: atom, track: track)
        case "stsd":
            try parseSampleDescription(handle: handle, atom: atom, track: track)
        case "uuid", "xml ", "©xyz":
            try scanSphericalMetadata(handle: handle, atom: atom, context: context)
        default:
            break
        }

        if containerTypes.contains(atom.type) {
            let childOffset = atom.type == "meta" ? atom.payloadOffset + 4 : atom.payloadOffset
            if childOffset + 8 <= atom.endOffset {
                try parseRange(handle: handle, start: childOffset, end: atom.endOffset, context: context, track: track)
            }
        } else if atom.payloadSize <= 256 * 1024 {
            try scanSphericalMetadata(handle: handle, atom: atom, context: context)
        }
    }

    private static func readAtom(handle: FileHandle, at offset: UInt64, fileEnd: UInt64) throws -> Atom? {
        guard offset + 8 <= fileEnd else { return nil }
        let header = try readData(handle: handle, offset: offset, length: 16)
        guard header.count >= 8 else { return nil }

        let compactSize = UInt64(header.uint32BE(at: 0))
        let type = header.string4(at: 4)
        var size = compactSize
        var headerSize: UInt64 = 8

        if compactSize == 1 {
            guard header.count >= 16 else { return nil }
            size = header.uint64BE(at: 8)
            headerSize = 16
        } else if compactSize == 0 {
            size = fileEnd - offset
        }

        guard size >= headerSize, offset <= UInt64.max - size else { return nil }
        return Atom(offset: offset, size: size, headerSize: headerSize, type: type)
    }

    private static func parseFileType(handle: FileHandle, atom: Atom, context: ParseContext) throws {
        let data = try readPayload(handle: handle, atom: atom, maxLength: 4096)
        guard data.count >= 8 else { return }
        context.majorBrand = data.string4(at: 0)
        var brands: [String] = []
        var cursor = 8
        while cursor + 4 <= data.count {
            brands.append(data.string4(at: cursor))
            cursor += 4
        }
        context.compatibleBrands = brands
    }

    private static func parseTrackHeader(handle: FileHandle, atom: Atom, track: TrackBuilder?) throws {
        let data = try readPayload(handle: handle, atom: atom, maxLength: 512)
        guard data.count >= 8 else { return }
        let widthFixed = data.uint32BE(at: data.count - 8)
        let heightFixed = data.uint32BE(at: data.count - 4)
        let width = Int((widthFixed + 0x8000) >> 16)
        let height = Int((heightFixed + 0x8000) >> 16)
        if width > 0 { track?.width = width }
        if height > 0 { track?.height = height }
    }

    private static func parseMediaHeader(handle: FileHandle, atom: Atom, track: TrackBuilder?) throws {
        let data = try readPayload(handle: handle, atom: atom, maxLength: 64)
        guard data.count >= 24 else { return }
        let version = data[0]
        if version == 1, data.count >= 32 {
            let timescale = data.uint32BE(at: 20)
            let duration = data.uint64BE(at: 24)
            track?.timescale = timescale
            if timescale > 0 {
                track?.durationSeconds = Double(duration) / Double(timescale)
            }
        } else {
            let timescale = data.uint32BE(at: 12)
            let duration = data.uint32BE(at: 16)
            track?.timescale = timescale
            if timescale > 0 {
                track?.durationSeconds = Double(duration) / Double(timescale)
            }
        }
    }

    private static func parseHandler(handle: FileHandle, atom: Atom, track: TrackBuilder?) throws {
        let data = try readPayload(handle: handle, atom: atom, maxLength: 64)
        guard data.count >= 12 else { return }
        track?.handlerType = data.string4(at: 8)
    }

    private static func parseSampleDescription(handle: FileHandle, atom: Atom, track: TrackBuilder?) throws {
        let data = try readPayload(handle: handle, atom: atom, maxLength: 8192)
        guard data.count >= 16 else { return }
        let entryCount = data.uint32BE(at: 4)
        guard entryCount > 0 else { return }

        let entryStart = 8
        guard entryStart + 16 <= data.count else { return }
        let codec = data.string4(at: entryStart + 4)
        track?.codec = codec

        if ["avc1", "avc3", "hvc1", "hev1", "mp4v", "jpeg"].contains(codec),
           entryStart + 36 <= data.count {
            let width = Int(data.uint16BE(at: entryStart + 32))
            let height = Int(data.uint16BE(at: entryStart + 34))
            if width > 0 { track?.width = width }
            if height > 0 { track?.height = height }
        }
    }

    private static func scanSphericalMetadata(handle: FileHandle, atom: Atom, context: ParseContext) throws {
        guard !context.hasSphericalMetadata else { return }
        let data = try readPayload(handle: handle, atom: atom, maxLength: 256 * 1024)
        if data.containsASCII("SphericalVideo") ||
            data.containsASCII("GSpherical") ||
            data.containsASCII("ProjectionType") ||
            data.containsASCII("Video360") {
            context.hasSphericalMetadata = true
        }
    }

    private static func readPayload(handle: FileHandle, atom: Atom, maxLength: Int) throws -> Data {
        let boundedLength = min(UInt64(maxLength), atom.payloadSize)
        return try readData(handle: handle, offset: atom.payloadOffset, length: Int(boundedLength))
    }

    private static func readData(handle: FileHandle, offset: UInt64, length: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return handle.readData(ofLength: length)
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }
}

private extension Data {
    func uint16BE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func uint32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return (UInt32(self[offset]) << 24) |
            (UInt32(self[offset + 1]) << 16) |
            (UInt32(self[offset + 2]) << 8) |
            UInt32(self[offset + 3])
    }

    func uint64BE(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return value
    }

    func string4(at offset: Int) -> String {
        guard offset + 4 <= count else { return "" }
        let bytes = [self[offset], self[offset + 1], self[offset + 2], self[offset + 3]]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    func containsASCII(_ text: String) -> Bool {
        guard let needle = text.data(using: .ascii), !needle.isEmpty else { return false }
        return range(of: needle) != nil
    }
}
