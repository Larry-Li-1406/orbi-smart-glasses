import Foundation

struct OrbiRawBundle: Codable {
    enum SourceKind: String, Codable {
        case video
        case photo
        case audio
        case imu
        case config
        case thumbnail
        case unknown
    }

    struct CameraSource: Codable, Hashable {
        var channel: Int?
        var path: String
        var fileSize: Int64?
        var kind: SourceKind
        var referenceCamera: CameraCalibration?
        var mp4Info: OrbiMP4Info?
    }

    struct CameraCalibration: Codable, Hashable {
        var viewAngleX: Double?
        var viewAngleY: Double?
        var maxTheta: Double?
        var ppx: Double?
        var ppy: Double?
        var k1: Double?
        var k2: Double?
        var k3: Double?
        var k4: Double?
        var rotationVector: [Double]
        var rotationMatrix: [Double]
    }

    var directory: URL
    var configURL: URL?
    var mediaUUID: String?
    var glassesUUID: String?
    var sessionUUID: String?
    var deviceType: String?
    var durationMilliseconds: Int64?
    var cameraOrder: [Int]
    var sources: [CameraSource]
    var imuFiles: [String]
    var rawConfig: String?

    var videoSources: [CameraSource] {
        sources.filter { $0.kind == .video }
    }

    var photoSources: [CameraSource] {
        sources.filter { $0.kind == .photo }
    }
}

enum OrbiRawBundleParser {
    static func parse(directory: URL, mediaName: String) throws -> OrbiRawBundle {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let configURL = preferredConfigURL(in: files, mediaName: mediaName)
        let rawConfig = configURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        var bundle = OrbiRawBundle(
            directory: directory,
            configURL: configURL,
            mediaUUID: nil,
            glassesUUID: nil,
            sessionUUID: nil,
            deviceType: nil,
            durationMilliseconds: nil,
            cameraOrder: [],
            sources: [],
            imuFiles: [],
            rawConfig: rawConfig
        )

        if let rawConfig {
            applyConfig(rawConfig, directory: directory, bundle: &bundle)
        }
        addFilesystemSources(files, bundle: &bundle)
        enrichVideoSources(directory: directory, bundle: &bundle)
        bundle.sources.sort {
            ($0.channel ?? Int.max, $0.path) < ($1.channel ?? Int.max, $1.path)
        }
        return bundle
    }

    private static func preferredConfigURL(in files: [URL], mediaName: String) -> URL? {
        let exact = "\(mediaName).CFG".lowercased()
        return files.first { $0.lastPathComponent.lowercased() == exact }
            ?? files.first { $0.pathExtension.lowercased() == "cfg" }
    }

    private static func applyConfig(_ text: String, directory: URL, bundle: inout OrbiRawBundle) {
        guard let json = extractJSONObject(from: text),
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            applyLooseKeyValueConfig(text, bundle: &bundle)
            return
        }
        bundle.mediaUUID = string(object, keys: ["mediaUUID", "videoUUID", "imageUUID"])
        bundle.glassesUUID = string(object, keys: ["glassesUUID"])
        bundle.sessionUUID = string(object, keys: ["sessionUUID"])
        bundle.deviceType = string(object, keys: ["deviceType"])
        bundle.durationMilliseconds = int64(object, keys: ["duration", "Duration"])
        bundle.cameraOrder = intArray(object["camera_order"] ?? object["cameraOrder"])
        bundle.imuFiles = stringArray(object["imuFiles"])
        if let helmet = object["helmetImu"] as? [String: Any] {
            bundle.imuFiles += stringArray(helmet["imuFiles"])
            if let imuPath = string(helmet, keys: ["imuPath"]) {
                bundle.imuFiles.append(imuPath)
            }
        }
        if let imuPath = string(object, keys: ["imuPath"]) {
            bundle.imuFiles.append(imuPath)
        }
        if let sources = object["sources"] as? [[String: Any]] {
            bundle.sources += sources.enumerated().compactMap { index, source in
                sourceFromConfig(source, directory: directory, fallbackChannel: index)
            }
        }
    }

    private static func sourceFromConfig(_ object: [String: Any], directory: URL, fallbackChannel: Int) -> OrbiRawBundle.CameraSource? {
        guard let path = string(object, keys: ["path", "file", "filename", "name"]) else { return nil }
        let kind = kindForPath(path)
        let fileSize = int64(object, keys: ["fileSize", "size"])
        let channel = int(object, keys: ["chanel", "channel"]) ?? fallbackChannel
        let referenceCamera = (object["referenceCamera"] as? [String: Any]).map(cameraCalibration)
        let absolute = directory.appendingPathComponent(path)
        let resolvedSize = fileSize ?? fileSizeAt(absolute)
        return OrbiRawBundle.CameraSource(
            channel: channel,
            path: path,
            fileSize: resolvedSize,
            kind: kind,
            referenceCamera: referenceCamera,
            mp4Info: nil
        )
    }

    private static func cameraCalibration(_ object: [String: Any]) -> OrbiRawBundle.CameraCalibration {
        OrbiRawBundle.CameraCalibration(
            viewAngleX: double(object, keys: ["viewAngleX"]),
            viewAngleY: double(object, keys: ["viewAngleY"]),
            maxTheta: double(object, keys: ["maxTheta"]),
            ppx: double(object, keys: ["ppx"]),
            ppy: double(object, keys: ["ppy"]),
            k1: double(object, keys: ["k1"]),
            k2: double(object, keys: ["k2"]),
            k3: double(object, keys: ["k3"]),
            k4: double(object, keys: ["k4"]),
            rotationVector: doubleArray(object["rotationVector"]),
            rotationMatrix: doubleArray(object["rotationMatrix"])
        )
    }

    private static func applyLooseKeyValueConfig(_ text: String, bundle: inout OrbiRawBundle) {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0 == "=" || $0 == ":" }).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "glassesuuid":
                bundle.glassesUUID = value
            case "mediauuid", "videouuid", "imageuuid":
                bundle.mediaUUID = value
            case "sessionuuid":
                bundle.sessionUUID = value
            case "duration":
                bundle.durationMilliseconds = Int64(value)
            case "imupath":
                bundle.imuFiles.append(value)
            default:
                if key.contains("path") || value.lowercased().hasSuffix(".mp4") || value.lowercased().hasSuffix(".jpg") {
                    bundle.sources.append(.init(channel: nil, path: value, fileSize: nil, kind: kindForPath(value), referenceCamera: nil, mp4Info: nil))
                }
            }
        }
    }

    private static func addFilesystemSources(_ files: [URL], bundle: inout OrbiRawBundle) {
        let existing = Set(bundle.sources.map { $0.path.lowercased() })
        for file in files {
            let name = file.lastPathComponent
            guard !existing.contains(name.lowercased()) else { continue }
            let kind = kindForFile(file)
            switch kind {
            case .video, .photo, .audio:
                bundle.sources.append(.init(channel: channelFromName(name), path: name, fileSize: fileSizeAt(file), kind: kind, referenceCamera: nil, mp4Info: nil))
            case .imu:
                bundle.imuFiles.append(name)
            default:
                break
            }
        }
    }

    private static func enrichVideoSources(directory: URL, bundle: inout OrbiRawBundle) {
        for index in bundle.sources.indices where bundle.sources[index].kind == .video {
            let sourceURL = directory.appendingPathComponent(bundle.sources[index].path)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            bundle.sources[index].mp4Info = try? OrbiMP4Inspector.inspect(url: sourceURL)
        }
    }

    private static func extractJSONObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }
        return String(text[start...end]).data(using: .utf8)
    }

    private static func kindForFile(_ url: URL) -> OrbiRawBundle.SourceKind {
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 12 {
            if data.starts(with: [0xff, 0xd8, 0xff]) { return .photo }
            if data[4..<8] == Data("ftyp".utf8) { return .video }
        }
        return kindForPath(url.lastPathComponent)
    }

    private static func kindForPath(_ path: String) -> OrbiRawBundle.SourceKind {
        switch (path as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "h264", "264":
            return .video
        case "jpg", "jpeg":
            return .photo
        case "aac", "m4a", "wav", "mp3":
            return .audio
        case "imu", "csv", "dat", "bin":
            return path.lowercased().contains("imu") ? .imu : .unknown
        case "cfg", "json":
            return .config
        case "png", "thm":
            return .thumbnail
        default:
            return path.lowercased().contains("imu") ? .imu : .unknown
        }
    }

    private static func channelFromName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        let digits = stem.reversed().drop { !$0.isNumber }.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(String(digits.reversed())).map { max(0, $0 - 1) }
    }

    private static func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
            if let value = object[key] { return "\(value)" }
        }
        return nil
    }

    private static func int(_ object: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? String, let int = Int(value) { return int }
            if let value = object[key] as? NSNumber { return value.intValue }
        }
        return nil
    }

    private static func int64(_ object: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            if let value = object[key] as? Int64 { return value }
            if let value = object[key] as? Int { return Int64(value) }
            if let value = object[key] as? String, let int = Int64(value) { return int }
            if let value = object[key] as? NSNumber { return value.int64Value }
        }
        return nil
    }

    private static func double(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double { return value }
            if let value = object[key] as? String, let double = Double(value) { return double }
            if let value = object[key] as? NSNumber { return value.doubleValue }
        }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.map { "\($0)" } }
        if let value = value as? String { return [value] }
        return []
    }

    private static func intArray(_ value: Any?) -> [Int] {
        if let values = value as? [Int] { return values }
        if let values = value as? [Any] {
            return values.compactMap {
                if let int = $0 as? Int { return int }
                if let string = $0 as? String { return Int(string) }
                if let number = $0 as? NSNumber { return number.intValue }
                return nil
            }
        }
        return []
    }

    private static func doubleArray(_ value: Any?) -> [Double] {
        if let values = value as? [Double] { return values }
        if let values = value as? [Any] {
            return values.compactMap {
                if let double = $0 as? Double { return double }
                if let string = $0 as? String { return Double(string) }
                if let number = $0 as? NSNumber { return number.doubleValue }
                return nil
            }
        }
        return []
    }

    private static func fileSizeAt(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}
