import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

private func orbiDebugLog(_ message: String) {
    #if DEBUG
    print("[ORBI DEBUG] \(message)")
    #endif
}

protocol OrbiDeviceServicing {
    func connect() async throws -> OrbiDeviceStatus
    func disconnect() async
    func fetchStatus() async throws -> OrbiDeviceStatus
    func setMode(_ mode: DeviceMode) async throws -> OrbiDeviceStatus
    func startCamera() async throws
    func stopCamera() async throws
    func setWiFi(_ credentials: WiFiCredentials) async throws
    func setRunningMode(_ settings: RunningModeSettings) async throws
    func formatSDCard() async throws
}

protocol OrbiMediaServicing {
    func fetchRemoteMedia() async throws -> [OrbiMediaItem]
    func download(_ item: OrbiMediaItem) async throws
    func delete(_ item: OrbiMediaItem) async throws
}

enum OrbiServiceError: LocalizedError {
    case connectionFailed
    case commandFailed(OrbiCommandFailure)
    case timeout
    case invalidSSID
    case invalidPassword
    case unsupportedMode
    case transferUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "无法连接到 ORBI 眼镜（\(OrbiProtocol.deviceIP):\(OrbiProtocol.devicePort)）"
        case .commandFailed(let failure):
            return failure.userDescription
        case .timeout:
            return "指令超时"
        case .invalidSSID:
            return "SSID 需为 1-32 位字符，仅可包含字母、数字、连字符和下划线"
        case .invalidPassword:
            return "两次密码需一致且至少 8 位字符"
        case .unsupportedMode:
            return "当前模式不支持这个操作"
        case .transferUnavailable(let reason):
            return reason
        }
    }
}

private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didEnter = false

    func enter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didEnter else { return false }
        didEnter = true
        return true
    }
}

private final class AsyncCommandLock: @unchecked Sendable {
    private let lock = NSLock()
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isLocked {
                waiters.append(continuation)
                lock.unlock()
            } else {
                isLocked = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()
        guard !waiters.isEmpty else {
            isLocked = false
            lock.unlock()
            return
        }
        let continuation = waiters.removeFirst()
        lock.unlock()
        continuation.resume()
    }
}

actor OrbiTCPClient {
    private var connection: NWConnection?
    private var isConnected = false
    private var commandId = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let commandLock = AsyncCommandLock()

    func connect() async throws {
        await commandLock.acquire()
        defer { commandLock.release() }
        try await connectUnlocked()
    }

    private func connectUnlocked() async throws {
        if connection != nil, isConnected {
            orbiDebugLog("TCP reuse existing connection")
            return
        }
        connection?.cancel()
        connection = nil
        isConnected = false
        let endpoint = NWEndpoint.Host(OrbiProtocol.deviceIP)
        let port = NWEndpoint.Port(integerLiteral: UInt16(OrbiProtocol.devicePort))
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        parameters.prohibitedInterfaceTypes = [.cellular, .wiredEthernet]
        let conn = NWConnection(host: endpoint, port: port, using: parameters)
        connection = conn
        orbiDebugLog("TCP connecting \(OrbiProtocol.deviceIP):\(OrbiProtocol.devicePort) over Wi-Fi")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let gate = OneShotGate()
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 8_000_000_000)
                    guard gate.enter() else { return }
                    conn.stateUpdateHandler = nil
                    conn.cancel()
                    orbiDebugLog("TCP connect timeout")
                    continuation.resume(throwing: OrbiServiceError.timeout)
                }

                @Sendable func resumeOnce(_ result: Result<Void, Error>) {
                    guard gate.enter() else { return }
                    timeoutTask.cancel()
                    conn.stateUpdateHandler = nil
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                conn.stateUpdateHandler = { state in
                    orbiDebugLog("TCP state \(state)")
                    switch state {
                    case .ready:
                        resumeOnce(.success(()))
                    case .failed(let error):
                        resumeOnce(.failure(error))
                    case .cancelled:
                        resumeOnce(.failure(OrbiServiceError.connectionFailed))
                    default:
                        break
                    }
                }
                conn.start(queue: .global(qos: .userInitiated))
            }
            isConnected = true
        } catch {
            clearConnectionIfCurrent(conn)
            throw error
        }
    }

    func disconnect() {
        orbiDebugLog("TCP disconnect")
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func clearConnectionIfCurrent(_ conn: NWConnection) {
        guard connection === conn else { return }
        connection = nil
        isConnected = false
    }

    func send(
        cmd: String,
        responseTimeout: TimeInterval = 15,
        configure: (inout DeviceCommandEnvelope) -> Void = { _ in }
    ) async throws -> DeviceResponseEnvelope {
        await commandLock.acquire()
        defer { commandLock.release() }
        try await connectUnlocked()
        commandId += 1
        let requestId = commandId
        var envelope = DeviceCommandEnvelope(id: requestId, cmd: cmd)
        configure(&envelope)
        let data = try encoder.encode(envelope) + Data(OrbiProtocol.messageDelimiter.utf8)
        guard let connection else { throw OrbiServiceError.connectionFailed }
        orbiDebugLog("SEND #\(requestId) cmd=\(cmd)")
        try await connection.sendAsync(data)

        do {
            while true {
                let responseData = try await connection.receiveUntilDelimiter(Data(OrbiProtocol.messageDelimiter.utf8), timeout: responseTimeout)
                if let responseString = String(data: responseData, encoding: .utf8) {
                    orbiDebugLog("RECV #\(requestId) \(responseString)")
                } else {
                    orbiDebugLog("RECV #\(requestId) \(responseData.count) bytes")
                }
                let response = try decoder.decode(DeviceResponseEnvelope.self, from: responseData)
                if response.event == "error" {
                    throw OrbiServiceError.commandFailed(response.commandFailure(for: cmd))
                }
                if response.event == "received", response.commandId == requestId {
                    orbiDebugLog("ACK #\(requestId) cmd=\(cmd)")
                    continue
                }
                if response.event != nil {
                    orbiDebugLog("EVENT while waiting #\(requestId) event=\(response.event ?? "")")
                    continue
                }
                guard response.result ?? false else {
                    throw OrbiServiceError.commandFailed(response.commandFailure(for: cmd))
                }
                return response
            }
        } catch {
            orbiDebugLog("FAILED #\(requestId) cmd=\(cmd) error=\(String(describing: error))")
            clearConnectionIfCurrent(connection)
            connection.cancel()
            throw error
        }
    }
}

private extension NWConnection {
    func sendAsync(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receiveUntilDelimiter(_ delimiter: Data, timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                var buffer = Data()
                while true {
                    let chunk = try await self.receiveChunk()
                    buffer.append(chunk)
                    if let range = buffer.range(of: delimiter) {
                        return buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw OrbiServiceError.timeout
            }
            guard let result = try await group.next() else { throw OrbiServiceError.timeout }
            group.cancelAll()
            return result
        }
    }

    func receiveChunk() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: OrbiServiceError.connectionFailed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

final class NetworkOrbiDeviceService: OrbiDeviceServicing {
    private let client: OrbiTCPClient

    init(client: OrbiTCPClient = OrbiTCPClient()) {
        self.client = client
    }

    func connect() async throws -> OrbiDeviceStatus {
        try await client.connect()
        let status = try await fetchStatus()
        do {
            try await initializeDevice(status: status)
        } catch {
            orbiDebugLog("Initial setup failed: \(error.localizedDescription)")
        }
        return try await fetchStatus()
    }

    func disconnect() async {
        await client.disconnect()
    }

    func fetchStatus() async throws -> OrbiDeviceStatus {
        let response = try await client.send(cmd: "get-status") { $0.modeShort = true }
        return Self.status(from: response)
    }

    func setMode(_ mode: DeviceMode) async throws -> OrbiDeviceStatus {
        guard mode != .none else { throw OrbiServiceError.unsupportedMode }
        let current = try await fetchStatus()
        if current.cameraRunning && (current.mode == .live || current.mode == .video) && current.mode != mode {
            try await stopCamera()
        }
        if current.mode == mode {
            if mode == .live {
                try await configureLivePreview()
            }
            return current
        }
        _ = try await client.send(cmd: "mode") { $0.mode = mode.commandValue }
        if mode == .live {
            try await configureLivePreview()
        }
        return try await fetchStatus()
    }

    func startCamera() async throws {
        do {
            _ = try await client.send(cmd: "start")
        } catch OrbiServiceError.commandFailed(let failure)
            where failure.isAlreadyStarted {
            return
        }
    }

    func stopCamera() async throws {
        _ = try await client.send(cmd: "stop")
    }

    func setWiFi(_ credentials: WiFiCredentials) async throws {
        try Self.validate(credentials)
        _ = try await client.send(cmd: "wifi-ap") {
            $0.wifiAp = .init(ssid: credentials.ssid, psk: credentials.password)
        }
        _ = try await client.send(cmd: "save")
    }

    func setRunningMode(_ settings: RunningModeSettings) async throws {
        try await saveGeneralSettings(settings)
    }

    func formatSDCard() async throws {
        _ = try await client.send(cmd: "format-sd") { $0.quick = true }
    }

    private func initializeDevice(status: OrbiDeviceStatus) async throws {
        let settingsResponse = try? await client.send(cmd: "get-settings")
        let includeCalendar = Self.isOlderFirmware(status.firmwareVersion, than: "1.0123")
        if Self.needsVideoTimingRepair(settingsResponse?.videoParams) {
            try await saveGeneralSettings(Self.repairedRunningModeSettings(from: settingsResponse?.videoParams), includeCalendar: includeCalendar)
        } else if includeCalendar {
            _ = try await client.send(cmd: "set-settings") {
                $0.calendarData = .init()
            }
            _ = try await client.send(cmd: "save")
        } else {
            _ = try? await client.send(cmd: "set_calendar_date") {
                $0.calendarData = .init()
            }
        }
    }

    private func configureLivePreview() async throws {
        _ = try await client.send(cmd: "set-stream-params") {
            $0.streamParams = Self.livePreviewStreamParams()
        }
    }

    private func saveGeneralSettings(_ settings: RunningModeSettings, includeCalendar: Bool = false) async throws {
        _ = try await client.send(cmd: "set-settings") {
            $0.imageParams = .init(delay: 300)
            $0.videoParams = .init(
                delay: 300,
                audio: true,
                recordTimeout: settings.isActive ? settings.recordTimeoutSeconds * 1000 : 0,
                recInterval: settings.recIntervalMilliseconds,
                idleInterval: settings.idleIntervalMilliseconds,
                turnOffWiFi: settings.turnOffWiFi,
                runner: settings.isActive
            )
            if includeCalendar {
                $0.calendarData = .init()
            }
        }
        _ = try await client.send(cmd: "save")
    }

    private static func livePreviewStreamParams() -> DeviceCommandEnvelope.StreamParams {
        .init(
            rtpIP: localWiFiIPv4Address() ?? OrbiProtocol.deviceIP,
            streams: OrbiProtocol.livePreviewPorts.map { .init(rtpPort: $0) }
        )
    }

    private static func isOlderFirmware(_ version: String, than minimum: String) -> Bool {
        let lhs = version.split(separator: ".").compactMap { Int($0) }
        let rhs = minimum.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l < r }
        }
        return false
    }

    private static func localWiFiIPv4Address() -> String? {
        #if canImport(Darwin)
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            guard name == OrbiProtocol.wifiInterfaceName,
                  let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            guard ip.hasPrefix("192.168.2.") else { continue }
            return ip
        }
        #endif
        return nil
    }

    private static func needsVideoTimingRepair(_ params: DeviceCommandEnvelope.VideoParams?) -> Bool {
        guard let params else { return false }
        return params.recInterval <= 0 || params.idleInterval <= 0
    }

    private static func repairedRunningModeSettings(from params: DeviceCommandEnvelope.VideoParams?) -> RunningModeSettings {
        let timeoutMinutes = Double((params?.recordTimeout ?? 0) / 1000) / 60
        return RunningModeSettings(
            isActive: params?.runner ?? false,
            totalTimeMinutes: timeoutMinutes,
            recIntervalSeconds: Double(max(params?.recInterval ?? 0, OrbiProtocol.defaultRecordIntervalMilliseconds)) / 1000,
            idleIntervalSeconds: Double(max(params?.idleInterval ?? 0, OrbiProtocol.defaultIdleIntervalMilliseconds)) / 1000,
            turnOffWiFi: params?.turnOffWiFi ?? false
        )
    }

    static func status(from response: DeviceResponseEnvelope) -> OrbiDeviceStatus {
        let threshold = response.charger?.threshold ?? 75
        let battery: DeviceBattery
        if response.charger?.charging == true {
            battery = .charging
        } else if threshold <= 0 {
            battery = .chargeZero
        } else if threshold <= 25 {
            battery = .charge25
        } else if threshold <= 50 {
            battery = .charge50
        } else if threshold <= 75 {
            battery = .charge75
        } else {
            battery = .charge100
        }
        return OrbiDeviceStatus(
            id: response.deviceUUID ?? "ORBI-360",
            firmwareVersion: response.firmwareVersion ?? "",
            mode: DeviceMode(deviceModeString: response.mode),
            cameraRunning: response.run ?? false,
            battery: battery,
            sdFreeCapacity: response.sdCard?.freeCapacity ?? 0,
            sdCardInserted: response.sdCard?.inserted ?? false,
            sdCardMounted: response.sdCard?.mount ?? false,
            captureDuration: TimeInterval(response.captureDuration ?? 0) / 1000,
            nfsUsed: response.nfsTransfer ?? false
        )
    }

    static func validate(_ credentials: WiFiCredentials) throws {
        let ssidOK = !credentials.ssid.isEmpty
            && credentials.ssid.count <= 32
            && credentials.ssid.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard ssidOK else { throw OrbiServiceError.invalidSSID }
        if !credentials.password.isEmpty {
            guard credentials.password.count >= 8, credentials.password == credentials.passwordVerify else {
                throw OrbiServiceError.invalidPassword
            }
        }
    }
}

final class NetworkOrbiMediaService: OrbiMediaServicing {
    private let client: OrbiTCPClient
    private let nfsClient: NFSClient

    init(client: OrbiTCPClient = OrbiTCPClient(), nfsClient: NFSClient = NFSClient()) {
        self.client = client
        self.nfsClient = nfsClient
    }

    func fetchRemoteMedia() async throws -> [OrbiMediaItem] {
        let response = try await client.send(cmd: "get_media_list", responseTimeout: 4)
        let imageFiles = response.images ?? response.image?.files ?? []
        let videoFiles = response.videos ?? response.video?.files ?? []
        return imageFiles.map { Self.item(from: $0, type: .photo) }
            + videoFiles.map { Self.item(from: $0, type: .video) }
    }

    func download(_ item: OrbiMediaItem) async throws {
        try OrbiLocalMediaStore.prepareDirectories()
        try await setNFSBusy(true)
        defer {
            Task { try? await setNFSBusy(false) }
        }
        _ = try await Task.detached(priority: .userInitiated) {
            try self.nfsClient.downloadDirectory(urlString: item.remoteDirectoryURLString, to: item.rawBundleURL)
        }.value
        try await OrbiStitchService.materializeDownloadedMedia(item)
    }

    func delete(_ item: OrbiMediaItem) async throws {
        try await setNFSBusy(true)
        defer {
            Task { try? await setNFSBusy(false) }
        }
        try await Task.detached(priority: .userInitiated) {
            try self.nfsClient.removeDirectory(urlString: item.remoteDirectoryURLString)
        }.value
        try? FileManager.default.removeItem(at: item.localURL)
        try? FileManager.default.removeItem(at: item.thumbnailURL)
        try? FileManager.default.removeItem(at: item.rawBundleURL)
    }

    private func setNFSBusy(_ busy: Bool) async throws {
        _ = try await client.send(cmd: "nfs-transfer") { $0.start = busy }
    }

    private static func item(from file: DeviceResponseEnvelope.DeviceFile, type: MediaType) -> OrbiMediaItem {
        let id = UUID(uuidString: file.uuid ?? "") ?? UUID()
        let date = ISO8601DateFormatter().date(from: file.date ?? "") ?? Date()
        let duration = TimeInterval((Int(file.duration ?? "") ?? 0) / 1000)
        let name = ((file.pathname as NSString?)?.deletingPathExtension).flatMap { ($0 as NSString).lastPathComponent } ?? file.pathname ?? "ORBI"
        let candidate = OrbiMediaItem(
            id: id,
            name: name,
            type: type,
            dateUTC: date,
            duration: duration,
            remoteSize: file.size ?? 0,
            localSize: 0,
            isRemote: true,
            isLocal: false,
            thumbnailExists: false
        )
        let localSize = (try? candidate.localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return OrbiMediaItem(
            id: id,
            name: name,
            type: type,
            dateUTC: date,
            duration: duration,
            remoteSize: file.size ?? 0,
            localSize: localSize,
            isRemote: true,
            isLocal: localSize > 0,
            thumbnailExists: FileManager.default.fileExists(atPath: candidate.thumbnailURL.path)
        )
    }
}

final class DemoOrbiDeviceService: OrbiDeviceServicing {
    private var status = OrbiDeviceStatus.sample

    func connect() async throws -> OrbiDeviceStatus {
        try await Task.sleep(nanoseconds: 300_000_000)
        return status
    }

    func disconnect() async {}

    func fetchStatus() async throws -> OrbiDeviceStatus { status }

    func setMode(_ mode: DeviceMode) async throws -> OrbiDeviceStatus {
        status.mode = mode
        status.cameraRunning = false
        return status
    }

    func startCamera() async throws {
        status.cameraRunning = true
    }

    func stopCamera() async throws {
        status.cameraRunning = false
    }

    func setWiFi(_ credentials: WiFiCredentials) async throws {
        try NetworkOrbiDeviceService.validate(credentials)
    }

    func setRunningMode(_ settings: RunningModeSettings) async throws {}

    func formatSDCard() async throws {
        status.sdFreeCapacity = 32_000_000_000
    }
}

final class DemoOrbiMediaService: OrbiMediaServicing {
    private var items = OrbiMediaItem.samples

    func fetchRemoteMedia() async throws -> [OrbiMediaItem] { items }
    func download(_ item: OrbiMediaItem) async throws {}
    func delete(_ item: OrbiMediaItem) async throws {
        items.removeAll { $0.id == item.id }
    }
}
