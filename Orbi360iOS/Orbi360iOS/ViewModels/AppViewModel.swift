import Foundation
import Observation
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
@Observable
final class AppViewModel {
    var selectedTab: MainTab = .shoot
    var selectedShootMode: DeviceMode = .video
    var connectionState: DeviceConnectionState = .disconnected
    var mediaItems: [OrbiMediaItem] = []
    var localMediaItems: [OrbiMediaItem] = []
    var mediaSource: MediaSource = .glasses
    var showMediaAsGrid = true
    var message: String?
    var isUsingDemoFallback = false
    var wifiCredentials = WiFiCredentials(ssid: "ORBI_360", password: "", passwordVerify: "")
    var runningMode = RunningModeSettings()
    var supportEmail = ""
    var supportDescription = ""
    var downloadStates: [UUID: DownloadState] = [:]
    var isCameraBusy = false
    var isSettingsBusy = false

    private let networkDeviceService: OrbiDeviceServicing
    private let networkMediaService: OrbiMediaServicing
    private let demoDeviceService: OrbiDeviceServicing
    private let demoMediaService: OrbiMediaServicing

    private var deviceService: OrbiDeviceServicing
    private var mediaService: OrbiMediaServicing
    private var isConnecting = false

    init(
        networkDeviceService: OrbiDeviceServicing? = nil,
        networkMediaService: OrbiMediaServicing? = nil,
        demoDeviceService: OrbiDeviceServicing = DemoOrbiDeviceService(),
        demoMediaService: OrbiMediaServicing = DemoOrbiMediaService()
    ) {
        let sharedClient = OrbiTCPClient()
        let resolvedNetworkDeviceService = networkDeviceService ?? NetworkOrbiDeviceService(client: sharedClient)
        let resolvedNetworkMediaService = networkMediaService ?? NetworkOrbiMediaService(client: sharedClient)
        self.networkDeviceService = resolvedNetworkDeviceService
        self.networkMediaService = resolvedNetworkMediaService
        self.demoDeviceService = demoDeviceService
        self.demoMediaService = demoMediaService
        self.deviceService = resolvedNetworkDeviceService
        self.mediaService = resolvedNetworkMediaService
    }

    var currentStatus: OrbiDeviceStatus? {
        if case let .connected(status) = connectionState {
            return status
        }
        return nil
    }

    var isConnectingToDevice: Bool {
        isConnecting
    }

    var isDeviceBusy: Bool {
        isConnecting || isCameraBusy || isSettingsBusy
    }

    var isCameraRunning: Bool {
        currentStatus?.cameraRunning ?? false
    }

    var batterySymbol: String {
        switch currentStatus?.battery {
        case .charging: return "battery.100.bolt"
        case .charge100: return "battery.100"
        case .charge75: return "battery.75"
        case .charge50: return "battery.50"
        case .charge25: return "battery.25"
        case .chargeZero: return "battery.0"
        default: return "battery.0"
        }
    }

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        message = nil
        connectionState = .connecting
        Task {
            defer { isConnecting = false }
            do {
                deviceService = networkDeviceService
                mediaService = networkMediaService
                let status = try await deviceService.connect()
                isUsingDemoFallback = false
                connectionState = .connected(status)
                selectedShootMode = status.mode == .none ? .video : status.mode
                if selectedShootMode == .video && status.mode != .video {
                    connectionState = .connected(try await deviceService.setMode(.video))
                }
                await refreshLocalMedia()
            } catch {
                isUsingDemoFallback = false
                connectionState = .failed(error.localizedDescription)
                message = error.localizedDescription
            }
        }
    }

    func disconnect() {
        Task {
            await deviceService.disconnect()
            connectionState = .disconnected
            mediaItems = []
        }
    }

    func selectShootMode(_ mode: DeviceMode) {
        guard !isCameraBusy else { return }
        guard currentStatus != nil else {
            selectedShootMode = mode
            return
        }
        selectedShootMode = mode
        isCameraBusy = true
        Task {
            defer { isCameraBusy = false }
            do {
                let status = try await deviceService.setMode(mode)
                connectionState = .connected(status)
            } catch {
                message = error.localizedDescription
                await refreshStatusSilently(preferCommandFailure: false)
            }
        }
    }

    func capturePhoto() {
        guard !isCameraBusy else { return }
        isCameraBusy = true
        Task {
            defer { isCameraBusy = false }
            do {
                guard currentStatus?.cardAvailable ?? false else {
                    message = "请检查SD卡是否已插入并格式化后重试"
                    return
                }
                try await deviceService.startCamera()
                message = "拍摄完成"
                await updateStatus()
                await refreshMedia()
            } catch {
                message = error.localizedDescription
                await refreshStatusSilently(preferCommandFailure: true)
            }
        }
    }

    func toggleVideoRecording() {
        guard !isCameraBusy else { return }
        isCameraBusy = true
        Task {
            defer { isCameraBusy = false }
            do {
                if isCameraRunning {
                    try await deviceService.stopCamera()
                    message = "视频已保存"
                } else {
                    guard currentStatus?.cardAvailable ?? false else {
                        message = "请检查SD卡是否已插入并格式化后重试"
                        return
                    }
                    try await deviceService.startCamera()
                    message = "正在录像"
                }
                await updateStatus()
            } catch {
                message = error.localizedDescription
                await refreshStatusSilently(preferCommandFailure: true)
            }
        }
    }

    func startLivePreview() {
        guard !isCameraBusy else { return }
        isCameraBusy = true
        Task {
            defer { isCameraBusy = false }
            do {
                let status = try await deviceService.setMode(.live)
                connectionState = .connected(status)
                try await deviceService.startCamera()
                let ports = OrbiProtocol.livePreviewPorts.map(String.init).joined(separator: ", ")
                message = "实时预览端口: \(ports)"
                await updateStatus()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func stopLivePreview() {
        guard !isCameraBusy else { return }
        isCameraBusy = true
        Task {
            defer { isCameraBusy = false }
            do {
                try await deviceService.stopCamera()
                let status = try await deviceService.setMode(.video)
                connectionState = .connected(status)
                selectedShootMode = .video
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func refreshMedia() async {
        do {
            mediaItems = try await mediaService.fetchRemoteMedia().sorted { $0.dateUTC > $1.dateUTC }
        } catch {
            message = error.localizedDescription
        }
        await refreshLocalMedia()
    }

    func refreshLocalMedia() async {
        var items: [OrbiMediaItem] = []
        if let mediaFiles = try? FileManager.default.contentsOfDirectory(at: OrbiLocalMediaStore.mediaDirectory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) {
            for file in mediaFiles {
                let name = file.deletingPathExtension().lastPathComponent
                let ext = file.pathExtension.uppercased()
                let type: MediaType = ext == "MP4" ? .video : (ext == "JPG" ? .photo : .unknown)
                guard type != .unknown else { continue }
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let duration: TimeInterval = type == .video ? await Self.extractDuration(from: file) : 0
                let thumbExists = FileManager.default.fileExists(atPath: OrbiLocalMediaStore.cacheDirectory.appendingPathComponent("\(name).png").path)
                items.append(OrbiMediaItem(
                    id: UUID(),
                    name: name,
                    type: type,
                    dateUTC: date,
                    duration: duration,
                    remoteSize: 0,
                    localSize: size,
                    isRemote: false,
                    isLocal: true,
                    thumbnailExists: thumbExists
                ))
            }
        }
        localMediaItems = items.sorted { $0.dateUTC > $1.dateUTC }
    }

    var currentMediaItems: [OrbiMediaItem] {
        mediaSource == .glasses ? mediaItems : localMediaItems
    }

    func saveWiFi() {
        guard !isSettingsBusy else { return }
        isSettingsBusy = true
        Task {
            defer { isSettingsBusy = false }
            do {
                try await deviceService.setWiFi(wifiCredentials)
                message = "WiFi 设置已保存"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func saveRunningMode() {
        guard !isSettingsBusy else { return }
        isSettingsBusy = true
        Task {
            defer { isSettingsBusy = false }
            do {
                try await deviceService.setRunningMode(runningMode)
                message = runningMode.isActive ? "运行模式已保存" : "运行模式已关闭"
                await updateStatus()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func formatSDCard() {
        guard !isSettingsBusy else { return }
        isSettingsBusy = true
        Task {
            defer { isSettingsBusy = false }
            do {
                try await deviceService.formatSDCard()
                message = "SD 卡格式化命令已发送"
                await updateStatus()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func delete(_ item: OrbiMediaItem) {
        Task {
            do {
                try await mediaService.delete(item)
                await refreshMedia()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func download(_ item: OrbiMediaItem) {
        downloadStates[item.id] = .transferring
        Task {
            do {
                try await mediaService.download(item)
                downloadStates[item.id] = .completed
                message = "传输完成: \(item.name)"
                await refreshLocalMedia()
            } catch {
                downloadStates[item.id] = .failed(error.localizedDescription)
                message = error.localizedDescription
            }
        }
    }

    func downloadState(for item: OrbiMediaItem) -> DownloadState {
        downloadStates[item.id] ?? .idle
    }

    func refreshStatus() {
        Task {
            await updateStatus()
        }
    }

    private func updateStatus() async {
        do {
            let status = try await deviceService.fetchStatus()
            connectionState = .connected(status)
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshStatusSilently(preferCommandFailure: Bool) async {
        do {
            let status = try await deviceService.fetchStatus()
            connectionState = .connected(status)
        } catch {
            if preferCommandFailure, case OrbiServiceError.commandFailed = error {
                message = error.localizedDescription
            }
            if case .connected = connectionState {
                connectionState = .failed(error.localizedDescription)
            }
        }
    }

    static func extractDuration(from url: URL) async -> TimeInterval {
        #if canImport(AVFoundation)
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        return CMTimeGetSeconds(duration)
        #else
        return 0
        #endif
    }

    func localFileURL(for item: OrbiMediaItem) -> URL? {
        let source = mediaSource == .glasses ? item : item
        if source.isLocal {
            return OrbiLocalMediaStore.mediaDirectory.appendingPathComponent("\(source.name).\(source.type.fileExtension.dropFirst())")
        }
        return nil
    }
}
