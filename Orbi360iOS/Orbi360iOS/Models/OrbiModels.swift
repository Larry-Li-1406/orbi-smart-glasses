import Foundation

enum MainTab: String, CaseIterable, Identifiable {
    case shoot = "拍摄"
    case media = "媒体"
    case settings = "设置"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .shoot: return "camera.viewfinder"
        case .media: return "photo.on.rectangle"
        case .settings: return "gearshape"
        }
    }
}

enum DeviceMode: String, CaseIterable, Identifiable, Codable {
    case none
    case photo
    case live
    case video

    var id: String { rawValue }

    var commandValue: String {
        switch self {
        case .photo: return "shot"
        case .live: return "live"
        case .video: return "record"
        case .none: return ""
        }
    }

    init(deviceModeString: String?) {
        switch deviceModeString {
        case "shot": self = .photo
        case "live": self = .live
        case "record": self = .video
        default: self = .none
        }
    }
}

enum DeviceConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(OrbiDeviceStatus)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum DeviceBattery: String, Codable {
    case none
    case chargeZero
    case charge25
    case charge50
    case charge75
    case charge100
    case charging

    var percentText: String {
        switch self {
        case .none: return "--"
        case .chargeZero: return "0%"
        case .charge25: return "25%"
        case .charge50: return "50%"
        case .charge75: return "75%"
        case .charge100: return "100%"
        case .charging: return "Charging"
        }
    }
}

struct OrbiDeviceStatus: Equatable, Codable {
    var id: String
    var firmwareVersion: String
    var mode: DeviceMode
    var cameraRunning: Bool
    var battery: DeviceBattery
    var sdFreeCapacity: Int64
    var sdCardInserted: Bool
    var sdCardMounted: Bool
    var captureDuration: TimeInterval
    var nfsUsed: Bool

    static let sample = OrbiDeviceStatus(
        id: "ORBI-360",
        firmwareVersion: "1.5.1",
        mode: .video,
        cameraRunning: false,
        battery: .charge75,
        sdFreeCapacity: 18_400_000_000,
        sdCardInserted: true,
        sdCardMounted: true,
        captureDuration: 0,
        nfsUsed: false
    )

    var cardAvailable: Bool {
        sdCardInserted && sdCardMounted
    }

    var remainingText: String {
        if !sdCardInserted { return "无 SD 卡" }
        if !sdCardMounted { return "SD 卡格式错误" }
        switch mode {
        case .photo:
            let photoSize: Int64 = 5_242_880
            return "可拍: \(sdFreeCapacity / photoSize) 张"
        case .video:
            let seconds = sdFreeCapacity / 9_742
            return "可录: \(Self.formatHMS(seconds))"
        default:
            return ""
        }
    }

    private static func formatHMS(_ seconds: Int64) -> String {
        let h = seconds / 3600
        let m = seconds % 3600 / 60
        let s = seconds % 60
        return String(format: "%02lld:%02lld:%02lld", h, m, s)
    }
}

enum MediaType: String, Codable {
    case video
    case photo
    case thumbnail
    case unknown

    var fileExtension: String {
        switch self {
        case .video: return ".MP4"
        case .photo: return ".JPG"
        case .thumbnail: return ".THM"
        case .unknown: return ""
        }
    }
}

struct OrbiMediaItem: Identifiable, Equatable, Hashable, Codable {
    var id: UUID
    var name: String
    var type: MediaType
    var dateUTC: Date
    var duration: TimeInterval
    var remoteSize: Int64
    var localSize: Int64
    var isRemote: Bool
    var isLocal: Bool
    var thumbnailExists: Bool

    var nfsURLString: String {
        configURLString
    }

    var configURLString: String {
        "nfs://\(OrbiProtocol.deviceIP)\(OrbiProtocol.dcimPath)\(name)/\(name).CFG"
    }

    var remoteDirectoryURLString: String {
        "nfs://\(OrbiProtocol.deviceIP)\(OrbiProtocol.dcimPath)\(name)"
    }

    var outputFileName: String {
        let date = OrbiFileDateFormatter.string(from: dateUTC)
        return "{\(id.uuidString.lowercased())}_\(date)_\(name)\(type.fileExtension.lowercased())"
    }

    var rawBundleDirectoryName: String {
        "{\(id.uuidString.lowercased())}_\(name)"
    }

    var localURL: URL {
        OrbiLocalMediaStore.mediaDirectory.appendingPathComponent(outputFileName)
    }

    var rawBundleURL: URL {
        OrbiLocalMediaStore.rawDirectory.appendingPathComponent(rawBundleDirectoryName, isDirectory: true)
    }

    var thumbnailURL: URL {
        OrbiLocalMediaStore.cacheDirectory.appendingPathComponent("{\(id.uuidString.lowercased())}.png")
    }

    var sizeString: String {
        let size = isLocal ? localSize : remoteSize
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    var durationString: String {
        guard type == .video, duration > 0 else { return "" }
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static let samples: [OrbiMediaItem] = [
        .init(id: UUID(), name: "ORBI_0001", type: .photo, dateUTC: .now.addingTimeInterval(-1800), duration: 0, remoteSize: 4_900_000, localSize: 4_900_000, isRemote: true, isLocal: true, thumbnailExists: false),
        .init(id: UUID(), name: "ORBI_0002", type: .video, dateUTC: .now.addingTimeInterval(-7200), duration: 42, remoteSize: 118_000_000, localSize: 0, isRemote: true, isLocal: false, thumbnailExists: false),
        .init(id: UUID(), name: "ORBI_0003", type: .video, dateUTC: .now.addingTimeInterval(-86400), duration: 126, remoteSize: 362_000_000, localSize: 362_000_000, isRemote: true, isLocal: true, thumbnailExists: false)
    ]
}

enum OrbiLocalMediaStore {
    static var mediaDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORBI 360", isDirectory: true)
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORBI 360", isDirectory: true)
    }

    static var rawDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORBI 360 Raw", isDirectory: true)
    }

    static func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
    }
}

enum OrbiFileDateFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

struct WiFiCredentials: Equatable, Codable {
    var ssid: String
    var password: String
    var passwordVerify: String
}

struct RunningModeSettings: Equatable, Codable {
    var isActive: Bool = false
    var totalTimeMinutes: Double = 120
    var recIntervalSeconds: Double = 60
    var idleIntervalSeconds: Double = 60
    var turnOffWiFi: Bool = false

    var recordTimeoutSeconds: Int {
        Int(totalTimeMinutes * 60)
    }

    var recIntervalMilliseconds: Int {
        Int(recIntervalSeconds * 1000)
    }

    var idleIntervalMilliseconds: Int {
        Int(idleIntervalSeconds * 1000)
    }
}

enum DownloadState: Equatable {
    case idle
    case transferring
    case stitching
    case completed
    case failed(String)

    var isActive: Bool {
        switch self {
        case .transferring, .stitching: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .idle: return ""
        case .transferring: return "传输中"
        case .stitching: return "拼接中"
        case .completed: return "已完成"
        case .failed(let reason): return "失败: \(reason)"
        }
    }
}

enum MediaSource: String, CaseIterable, Identifiable {
    case glasses = "眼镜"
    case phone = "手机"

    var id: String { rawValue }
}

enum OrbiProtocol {
    static let deviceIP = "192.168.2.1"
    static let devicePort = 8080
    static let localPort = 5000
    static let messageDelimiter = "\r\n\r\n"
    static let dcimPath = "/run/RTOS/DCIM/"
    static let livePreviewPorts = [5000, 5002, 5004, 5006]
    static let wifiInterfaceName = "en0"
    static let defaultRecordIntervalMilliseconds = 300_000
    static let defaultIdleIntervalMilliseconds = 600_000
}

struct OrbiCommandFailure: Equatable {
    let command: String
    let responseString: String?
    let descString: String?
    let errorCode: String?
    let errorParam: String?

    var isAlreadyStarted: Bool {
        rawDescription.localizedCaseInsensitiveContains("already start")
    }

    var rawDescription: String {
        let details = [responseString, descString, errorCode, errorParam]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !details.isEmpty else { return command }
        return "\(command) \(details.joined(separator: " "))"
    }

    var userDescription: String {
        if rawDescription.localizedCaseInsensitiveContains("cant set camera capture mode") {
            return "眼镜无法切换相机采集模式。请重启眼镜，断开充电线，并确认 SD 卡可用后重试"
        }
        guard let code = errorCode.flatMap(Int.init) else {
            return "指令失败: \(rawDescription)"
        }
        let suffix = "错误码 \(code)" + (errorParam.map { " / 参数 \($0)" } ?? "")
        switch code {
        case 838_860_801, 855_638_017, 1_107_296_256:
            return "SD 卡未插入或未挂载，请重新插拔/格式化 SD 卡后重试（\(suffix)）"
        case 838_860_802, 855_638_018:
            return "SD 卡写保护，无法保存拍摄内容（\(suffix)）"
        case 838_860_803, 855_638_019, 553_648_129, 570_425_345:
            return "SD 卡空间不足，请清理或格式化后重试（\(suffix)）"
        case 838_860_804, 855_638_020:
            return "SD 卡目录数量已满，请导出素材后格式化 SD 卡（\(suffix)）"
        case 838_860_805:
            return "拍照系统错误。请重启眼镜，确认 SD 卡可用后再试（\(suffix)）"
        case 855_638_021:
            return "录像系统错误。请先重启眼镜，最好断开充电线，并确认 SD 卡可用后再试（\(suffix)）"
        case 570_425_346:
            return "录像保存失败：SD 卡速度不足，请换高速卡或格式化后重试（\(suffix)）"
        case 1_124_073_472:
            return "电量过低，眼镜拒绝拍摄，请充电后重试（\(suffix)）"
        case 1_157_627_904, 1_157_627_905:
            return "眼镜温度过高，已停止拍摄，请降温后重试（\(suffix)）"
        case 1_174_405_120:
            return "正在传输素材，眼镜暂时不能录像。请等待传输结束后重试（\(suffix)）"
        default:
            return "眼镜返回硬件错误：\(rawDescription)"
        }
    }
}

struct DeviceCommandEnvelope: Encodable {
    let id: Int
    let cmd: String
    var mode: String?
    var modeShort: Bool?
    var wifiAp: WiFiAPCommand?
    var psk: String?
    var initialStart: Bool?
    var channel: Int?
    var hwMode: String?
    var start: Bool?
    var imageParams: ImageParams?
    var videoParams: VideoParams?
    var streamParams: StreamParams?
    var calendarData: CalendarData?
    var quick: Bool?

    init(
        id: Int,
        cmd: String,
        mode: String? = nil,
        modeShort: Bool? = nil,
        wifiAp: WiFiAPCommand? = nil,
        psk: String? = nil,
        initialStart: Bool? = nil,
        channel: Int? = nil,
        hwMode: String? = nil,
        start: Bool? = nil,
        imageParams: ImageParams? = nil,
        videoParams: VideoParams? = nil,
        streamParams: StreamParams? = nil,
        calendarData: CalendarData? = nil,
        quick: Bool? = nil
    ) {
        self.id = id
        self.cmd = cmd
        self.mode = mode
        self.modeShort = modeShort
        self.wifiAp = wifiAp
        self.psk = psk
        self.initialStart = initialStart
        self.channel = channel
        self.hwMode = hwMode
        self.start = start
        self.imageParams = imageParams
        self.videoParams = videoParams
        self.streamParams = streamParams
        self.calendarData = calendarData
        self.quick = quick
    }

    struct WiFiAPCommand: Codable, Equatable {
        var ssid: String
        var psk: String
        var channel: Int = 48
    }

    struct ImageParams: Codable, Equatable {
        var delay: Int = 300
    }

    struct VideoParams: Codable, Equatable {
        var delay: Int = 300
        var audio: Bool = true
        var recordTimeout: Int = 0
        var recInterval: Int = 0
        var idleInterval: Int = 0
        var turnOffWiFi: Bool = false
        var runner: Bool = false

        enum CodingKeys: String, CodingKey {
            case delay
            case audio
            case recordTimeout = "rec_timeout"
            case recInterval = "time_record"
            case idleInterval = "time_sleep"
            case turnOffWiFi = "turn_off_wifi"
            case runner
        }
    }

    struct StreamParams: Codable, Equatable {
        var rtpIP: String
        var streams: [Stream]

        enum CodingKeys: String, CodingKey {
            case rtpIP = "rtp_ip"
            case streams
        }
    }

    struct Stream: Codable, Equatable {
        var rtpPort: Int

        enum CodingKeys: String, CodingKey {
            case rtpPort = "rtp_port"
        }

        init(rtpPort: Int) {
            self.rtpPort = rtpPort
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rtpPort = Self.decodeFlexibleInt(container, forKey: .rtpPort) ?? 0
        }
    }

    struct CalendarData: Codable, Equatable {
        var second: Int
        var minute: Int
        var hour: Int
        var day: Int
        var dayOfWeek: Int
        var month: Int
        var year: Int

        enum CodingKeys: String, CodingKey {
            case second
            case minute
            case hour
            case day
            case dayOfWeek = "day_of_week"
            case month
            case year
        }

        init(date: Date = Date().addingTimeInterval(1), calendar: Calendar = .current) {
            second = calendar.component(.second, from: date)
            minute = calendar.component(.minute, from: date)
            hour = calendar.component(.hour, from: date)
            day = calendar.component(.day, from: date)
            let weekday = calendar.component(.weekday, from: date) - 1
            dayOfWeek = weekday == 0 ? 7 : weekday
            month = calendar.component(.month, from: date)
            year = calendar.component(.year, from: date) - 2000
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case cmd
        case mode
        case modeShort = "mode_short"
        case wifiAp = "wifi_ap"
        case psk
        case initialStart = "initial_start"
        case channel
        case hwMode = "hw_mode"
        case start
        case imageParams = "image_params"
        case videoParams = "video_params"
        case streamParams = "stream_params"
        case calendarData = "calendar_data"
        case quick
    }
}

struct DeviceResponseEnvelope: Decodable {
    struct Charger: Decodable {
        var threshold: Int?
        var charging: Bool?

        enum CodingKeys: String, CodingKey {
            case threshold
            case charging
        }

        init(threshold: Int? = nil, charging: Bool? = nil) {
            self.threshold = threshold
            self.charging = charging
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            threshold = Self.decodeFlexibleInt(container, forKey: .threshold)
            charging = Self.decodeFlexibleBool(container, forKey: .charging)
        }
    }

    struct SDCard: Decodable {
        var inserted: Bool?
        var mount: Bool?
        var freeCapacity: Int64?

        enum CodingKeys: String, CodingKey {
            case inserted
            case mount
            case freeCapacity = "free_capacity"
        }

        init(inserted: Bool? = nil, mount: Bool? = nil, freeCapacity: Int64? = nil) {
            self.inserted = inserted
            self.mount = mount
            self.freeCapacity = freeCapacity
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inserted = Self.decodeFlexibleBool(container, forKey: .inserted)
            mount = Self.decodeFlexibleBool(container, forKey: .mount)
            freeCapacity = Self.decodeFlexibleInt64(container, forKey: .freeCapacity)
        }
    }

    struct DeviceFileArray: Decodable {
        var files: [DeviceFile]?

        init(files: [DeviceFile]? = nil) {
            self.files = files
        }
    }

    struct DeviceFile: Decodable {
        var uuid: String?
        var pathname: String?
        var size: Int64?
        var duration: String?
        var date: String?

        init(uuid: String? = nil, pathname: String? = nil, size: Int64? = nil, duration: String? = nil, date: String? = nil) {
            self.uuid = uuid
            self.pathname = pathname
            self.size = size
            self.duration = duration
            self.date = date
        }
    }

    var id: Int?
    var event: String?
    var commandId: Int?
    var errorCode: String?
    var errorParam: String?
    var responseString: String?
    var descString: String?
    var result: Bool?
    var deviceUUID: String?
    var firmwareVersion: String?
    var run: Bool?
    var mode: String?
    var captureDuration: Int?
    var nfsTransfer: Bool?
    var wifiSSID: String?
    var wifiInitialStart: Bool?
    var imageParams: DeviceCommandEnvelope.ImageParams?
    var videoParams: DeviceCommandEnvelope.VideoParams?
    var streamParams: DeviceCommandEnvelope.StreamParams?
    var charger: Charger?
    var sdCard: SDCard?
    var images: [DeviceFile]?
    var videos: [DeviceFile]?
    var image: DeviceFileArray?
    var video: DeviceFileArray?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case commandId = "command_id"
        case errorCode = "error_code"
        case errorParam = "error_param"
        case responseString = "resp-str"
        case descString = "desc-str"
        case result
        case deviceUUID = "dev-uuid"
        case firmwareVersion = "firmware-version"
        case run
        case mode
        case captureDuration = "capture-duration"
        case nfsTransfer = "nfs_transfer"
        case wifiSSID = "wifi-ssid"
        case wifiInitialStart = "initial_start"
        case imageParams = "image_params"
        case videoParams = "video_params"
        case streamParams = "stream_params"
        case charger
        case sdCard = "SD_card"
        case sdCardLower = "sd_card"
        case images
        case videos
        case image
        case video
    }

    init(
        id: Int? = nil,
        event: String? = nil,
        commandId: Int? = nil,
        errorCode: String? = nil,
        errorParam: String? = nil,
        responseString: String? = nil,
        descString: String? = nil,
        result: Bool? = nil,
        deviceUUID: String? = nil,
        firmwareVersion: String? = nil,
        run: Bool? = nil,
        mode: String? = nil,
        captureDuration: Int? = nil,
        nfsTransfer: Bool? = nil,
        wifiSSID: String? = nil,
        wifiInitialStart: Bool? = nil,
        imageParams: DeviceCommandEnvelope.ImageParams? = nil,
        videoParams: DeviceCommandEnvelope.VideoParams? = nil,
        streamParams: DeviceCommandEnvelope.StreamParams? = nil,
        charger: Charger? = nil,
        sdCard: SDCard? = nil,
        images: [DeviceFile]? = nil,
        videos: [DeviceFile]? = nil,
        image: DeviceFileArray? = nil,
        video: DeviceFileArray? = nil
    ) {
        self.id = id
        self.event = event
        self.commandId = commandId
        self.errorCode = errorCode
        self.errorParam = errorParam
        self.responseString = responseString
        self.descString = descString
        self.result = result
        self.deviceUUID = deviceUUID
        self.firmwareVersion = firmwareVersion
        self.run = run
        self.mode = mode
        self.captureDuration = captureDuration
        self.nfsTransfer = nfsTransfer
        self.wifiSSID = wifiSSID
        self.wifiInitialStart = wifiInitialStart
        self.imageParams = imageParams
        self.videoParams = videoParams
        self.streamParams = streamParams
        self.charger = charger
        self.sdCard = sdCard
        self.images = images
        self.videos = videos
        self.image = image
        self.video = video
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = Self.decodeFlexibleInt(container, forKey: .id)
        event = try container.decodeIfPresent(String.self, forKey: .event)
        commandId = Self.decodeFlexibleInt(container, forKey: .commandId)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        errorParam = try container.decodeIfPresent(String.self, forKey: .errorParam)
        responseString = try container.decodeIfPresent(String.self, forKey: .responseString)
        descString = try container.decodeIfPresent(String.self, forKey: .descString)
        result = Self.decodeFlexibleBool(container, forKey: .result)
        deviceUUID = try container.decodeIfPresent(String.self, forKey: .deviceUUID)
        firmwareVersion = try container.decodeIfPresent(String.self, forKey: .firmwareVersion)
        run = Self.decodeFlexibleBool(container, forKey: .run)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        captureDuration = Self.decodeFlexibleInt(container, forKey: .captureDuration)
        nfsTransfer = Self.decodeFlexibleBool(container, forKey: .nfsTransfer)
        wifiSSID = try container.decodeIfPresent(String.self, forKey: .wifiSSID)
        wifiInitialStart = Self.decodeFlexibleBool(container, forKey: .wifiInitialStart)
        imageParams = try container.decodeIfPresent(DeviceCommandEnvelope.ImageParams.self, forKey: .imageParams)
        videoParams = try container.decodeIfPresent(DeviceCommandEnvelope.VideoParams.self, forKey: .videoParams)
        streamParams = try container.decodeIfPresent(DeviceCommandEnvelope.StreamParams.self, forKey: .streamParams)
        charger = try container.decodeIfPresent(Charger.self, forKey: .charger)
        sdCard = try container.decodeIfPresent(SDCard.self, forKey: .sdCard)
            ?? container.decodeIfPresent(SDCard.self, forKey: .sdCardLower)
        images = try container.decodeIfPresent([DeviceFile].self, forKey: .images)
        videos = try container.decodeIfPresent([DeviceFile].self, forKey: .videos)
        image = try container.decodeIfPresent(DeviceFileArray.self, forKey: .image)
        video = try container.decodeIfPresent(DeviceFileArray.self, forKey: .video)
    }

    func commandFailure(for command: String) -> OrbiCommandFailure {
        OrbiCommandFailure(
            command: command,
            responseString: responseString,
            descString: descString,
            errorCode: errorCode,
            errorParam: errorParam
        )
    }

    func commandFailureDescription(for command: String) -> String {
        commandFailure(for: command).rawDescription
    }
}

private extension Decodable {
    static func decodeFlexibleBool<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "on": return true
            case "false", "0", "no", "off": return false
            default: return nil
            }
        }
        return nil
    }

    static func decodeFlexibleInt<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    static func decodeFlexibleInt64<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int64(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int64(value) }
        return nil
    }
}

struct DeviceEventEnvelope: Decodable {
    var id: Int?
    var event: String
    var mode: String?
    var mediaName: String?
    var mediaUuid: String?
    var availableStorage: Int64?
    var errorCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case mode
        case mediaName = "name"
        case mediaUuid = "uuid"
        case availableStorage = "available_storage"
        case errorCode = "error_code"
    }
}
