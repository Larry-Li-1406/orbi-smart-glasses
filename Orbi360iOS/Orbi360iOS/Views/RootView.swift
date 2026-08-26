import SwiftUI

// MARK: - Color Extensions

extension Color {
    static let orbiPrimary = Color(red: 0.004, green: 0.643, blue: 0.827)
    static let orbiPrimaryDark = Color(red: 0.004, green: 0.431, blue: 0.557)
    static let orbiAccent = Color(red: 0.094, green: 0.749, blue: 0.937)
    static let orbiBgDark = Color(red: 0.043, green: 0.051, blue: 0.063)
    static let orbiCardBg = Color(red: 0.969, green: 0.973, blue: 0.976)
    static let orbiBlackText = Color(red: 0.141, green: 0.153, blue: 0.157)
    static let orbiSubText = Color(red: 0.388, green: 0.412, blue: 0.431)
    static let orbiSeparator = Color(red: 0.882, green: 0.890, blue: 0.902)
    static let orbiPanel = Color(red: 0.949, green: 0.961, blue: 0.969)
    static let orbiInk = Color(red: 0.078, green: 0.094, blue: 0.110)
    static let orbiRed = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let orbiGreen = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let orbiOrange = Color(red: 0.949, green: 0.573, blue: 0.184)
}

// MARK: - Root View

struct RootView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var model = viewModel

        VStack(spacing: 0) {
            Group {
                switch model.selectedTab {
                case .shoot:
                    ShootRootView()
                case .media:
                    MediaRootView()
                case .settings:
                    SettingsRootView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OrbiBottomNav(selectedTab: $model.selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        .alert("ORBI 360", isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("好的", role: .cancel) { viewModel.message = nil }
        } message: {
            Text(viewModel.message ?? "")
        }
    }
}

// MARK: - Bottom Navigation

struct OrbiBottomNav: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 22, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(selectedTab == tab ? Color.orbiPrimary : .secondary)
                    .scaleEffect(selectedTab == tab ? 1.0 : 0.92)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(.black.opacity(0.06)).frame(height: 0.5), alignment: .top)
    }
}

// MARK: - Shoot Root

struct ShootRootView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            OrbiShootTabs()
            ZStack(alignment: .top) {
                if viewModel.currentStatus == nil {
                    ConnectionLobbyView()
                } else {
                    ShootModeContent()
                    ShootOverlayStatus()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if viewModel.currentStatus == nil {
                viewModel.connect()
            }
        }
    }
}

// MARK: - Shoot Mode Tabs

struct OrbiShootTabs: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.photo, "拍照", "camera.fill")
            tabButton(.live, "实时", "dot.radiowaves.left.and.right")
            tabButton(.video, "录像", "video.fill")
        }
        .frame(height: 52)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(.black.opacity(0.06)).frame(height: 0.5), alignment: .bottom)
    }

    private func tabButton(_ mode: DeviceMode, _ title: String, _ icon: String) -> some View {
        let isActive = viewModel.selectedShootMode == mode
        return Button {
            viewModel.selectShootMode(mode)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isActive ? Color.orbiPrimary : .secondary)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.orbiPrimary)
                    .frame(width: 28, height: 3)
                    .opacity(isActive ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isCameraBusy)
        .opacity(viewModel.isCameraBusy && !isActive ? 0.55 : 1)
    }
}

// MARK: - Connection Lobby

struct ConnectionLobbyView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        let isConnecting = viewModel.isConnectingToDevice

        ZStack {
            LinearGradient(
                colors: [Color.orbiInk, Color.orbiPrimaryDark, Color.orbiPrimary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: isConnecting ? "antenna.radiowaves.left.and.right" : "visionpro")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .symbolEffect(.pulse, value: isConnecting)

                    Text("ORBI 360")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("智能眼镜")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("连接设备", systemImage: "wifi")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.orbiBlackText)
                        Text("请在手机 WiFi 设置中选择眼镜热点 SSID 并输入密码连接")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.orbiSubText)
                            .lineSpacing(3)
                    }

                    HStack {
                        Image(systemName: "1.circle.fill")
                            .foregroundStyle(Color.orbiPrimary)
                        Text("打开手机 WiFi 设置")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.orbiBlackText)
                    }
                    HStack {
                        Image(systemName: "2.circle.fill")
                            .foregroundStyle(Color.orbiPrimary)
                        Text("选择 ORBI_360 热点")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.orbiBlackText)
                    }
                    HStack {
                        Image(systemName: "3.circle.fill")
                            .foregroundStyle(Color.orbiPrimary)
                        Text("返回 App 点击连接")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.orbiBlackText)
                    }

                    Button {
                        viewModel.connect()
                    } label: {
                        HStack(spacing: 10) {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "wifi")
                            }
                            Text(isConnecting ? "正在连接眼镜" : "连接眼镜")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orbiPrimary)
                    .controlSize(.large)
                    .disabled(isConnecting)

                    if case let .failed(reason) = viewModel.connectionState {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.orbiRed)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
                .background(Color.orbiCardBg)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
    }
}

// MARK: - Shoot Mode Content

struct ShootModeContent: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        switch viewModel.selectedShootMode {
        case .photo:
            PhotoModeView()
        case .live:
            LivePreviewModeView()
        case .video, .none:
            VideoModeView()
        }
    }
}

// MARK: - Shoot Overlay Status

struct ShootOverlayStatus: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        HStack {
            StatusPill(
                icon: viewModel.batterySymbol,
                text: viewModel.currentStatus?.battery.displayText ?? "--"
            )

            StatusPill(
                icon: viewModel.currentStatus?.cardAvailable == true ? "sdcard.fill" : "sdcard",
                text: viewModel.currentStatus?.cardAvailable == true ? "SD 可用" : "检查 SD"
            )

            Spacer()

            if let remaining = viewModel.currentStatus?.remainingText, !remaining.isEmpty {
                StatusPill(icon: "clock", text: remaining)
            }
        }
        .padding()
    }
}

struct StatusPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// MARK: - Photo Mode

struct PhotoModeView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orbiPrimary, Color.orbiPrimaryDark],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "camera.aperture")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 16)

                Text("1, 2...")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("拍照！")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()

                Button {
                    viewModel.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white)
                            .frame(width: 62, height: 62)
                        if viewModel.isCameraBusy {
                            ProgressView()
                                .tint(Color.orbiPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCameraBusy)
                .opacity(viewModel.isCameraBusy ? 0.68 : 1)
                .padding(.bottom, 70)
            }
        }
    }
}

// MARK: - Video Mode

struct VideoModeView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orbiPrimary, Color.orbiPrimaryDark],
                startPoint: .top, endPoint: .bottom
            )

            if viewModel.isCameraRunning {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orbiRed)
                            .frame(width: 8, height: 8)
                        Text("录像中")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 100)

                    Text(viewModel.currentStatus?.captureDuration.formattedDuration ?? "0:00")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    if viewModel.runningMode.isActive {
                        Text("循环 \(Int(viewModel.runningMode.recIntervalSeconds))秒 / 待机")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()

                    Button {
                        viewModel.toggleVideoRecording()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.orbiRed)
                                .frame(width: 30, height: 30)
                            if viewModel.isCameraBusy {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isCameraBusy)
                    .opacity(viewModel.isCameraBusy ? 0.68 : 1)
                    .padding(.bottom, 70)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "video.fill")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, 12)
                    Text("1, 2...")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("录像！")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Button {
                        viewModel.toggleVideoRecording()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(Color.orbiRed)
                                .frame(width: 62, height: 62)
                            if viewModel.isCameraBusy {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isCameraBusy)
                    .opacity(viewModel.isCameraBusy ? 0.68 : 1)
                    .padding(.bottom, 70)
                }
            }
        }
    }
}

// MARK: - Live Preview Mode

struct LivePreviewModeView: View {
    var body: some View {
        OrbiLivePreviewView()
    }
}

// MARK: - Media Root

struct MediaRootView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var model = viewModel

        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("", selection: $model.mediaSource) {
                        ForEach(MediaSource.allCases) { source in
                            Text(source.rawValue).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    Spacer()

                    Button {
                        withAnimation { viewModel.showMediaAsGrid.toggle() }
                    } label: {
                        Image(systemName: viewModel.showMediaAsGrid ? "list.bullet" : "square.grid.2x2")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(Color.orbiPrimary)

                HStack(spacing: 0) {
                    Text("照片").orbiMediaTab()
                    Text("视频").orbiMediaTab()
                }
                .background(Color.orbiPrimary)

                if viewModel.showMediaAsGrid {
                    MediaGridView()
                } else {
                    MediaListView()
                }
            }
            .task {
                await viewModel.refreshMedia()
            }
        }
    }
}

// MARK: - Media Grid View

struct MediaGridView: View {
    @Environment(AppViewModel.self) private var viewModel
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 8)]

    var body: some View {
        ScrollView {
            if viewModel.currentMediaItems.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: viewModel.mediaSource == .glasses ? "wifi.slash" : "tray")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(viewModel.mediaSource == .glasses ? "眼镜上暂无媒体" : "手机上暂无媒体")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(viewModel.mediaSource == .glasses ? "请连接眼镜后查看拍摄内容" : "请从眼镜传输媒体到手机查看")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(viewModel.currentMediaItems) { item in
                        NavigationLink {
                            if item.type == .photo {
                                PhotoViewerView(item: item)
                            } else {
                                MediaEditorView(item: item)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                MediaThumb(item: item)
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(alignment: .topTrailing) {
                                        downloadBadge(for: item)
                                    }
                                Text(item.sizeString)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            mediaMenu(item)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func downloadBadge(for item: OrbiMediaItem) -> some View {
        let state = viewModel.downloadState(for: item)
        if state.isActive {
            Circle()
                .fill(Color.orbiPrimary)
                .frame(width: 18, height: 18)
                .overlay(ProgressView().scaleEffect(0.55).tint(.white))
        } else if state == .completed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.orbiGreen)
        }
    }

    @ViewBuilder
    private func mediaMenu(_ item: OrbiMediaItem) -> some View {
        Button("选择") {}
        Button("分享") {}
        if viewModel.mediaSource == .glasses {
            Button("传输") { viewModel.download(item) }
        }
        Button("删除", role: .destructive) {
            if viewModel.mediaSource == .glasses {
                viewModel.delete(item)
            } else {
                deleteLocal(item)
            }
        }
    }

    private func deleteLocal(_ item: OrbiMediaItem) {
        let url = OrbiLocalMediaStore.mediaDirectory.appendingPathComponent("\(item.name).\(item.type.fileExtension.dropFirst())")
        try? FileManager.default.removeItem(at: url)
        Task { await viewModel.refreshLocalMedia() }
    }
}

// MARK: - Media List View

struct MediaListView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        if viewModel.currentMediaItems.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: viewModel.mediaSource == .glasses ? "wifi.slash" : "tray")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text(viewModel.mediaSource == .glasses ? "眼镜上暂无媒体" : "手机上暂无媒体")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 100)
        } else {
            List(viewModel.currentMediaItems) { item in
                NavigationLink {
                    if item.type == .photo {
                        PhotoViewerView(item: item)
                    } else {
                        MediaEditorView(item: item)
                    }
                } label: {
                    HStack(spacing: 14) {
                        MediaThumb(item: item)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .medium))
                            HStack(spacing: 8) {
                                Text(item.sizeString)
                                Text(item.dateUTC, style: .date)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            if viewModel.downloadState(for: item).isActive {
                                Text(viewModel.downloadState(for: item).label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.orbiPrimary)
                            }
                        }
                        Spacer()
                        if !item.durationString.isEmpty {
                            Text(item.durationString)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Media Thumbnail

struct MediaThumb: View {
    let item: OrbiMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if item.thumbnailExists, let image = localThumbnail {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: item.type == .photo
                        ? [Color.orbiPrimary.opacity(0.15), Color.orbiPrimary.opacity(0.05)]
                        : [Color.black.opacity(0.1), Color.black.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: item.type == .photo ? "photo" : "video")
                    .font(.title2)
                    .foregroundStyle(item.type == .photo ? Color.orbiPrimary : .black.opacity(0.6))
            }
            if item.type == .video, !item.durationString.isEmpty {
                Text(item.durationString)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var localThumbnail: Image? {
        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: item.thumbnailURL.path) else { return nil }
        return Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: item.thumbnailURL) else { return nil }
        return Image(nsImage: image)
        #else
        return nil
        #endif
    }
}

// MARK: - Settings Root

struct SettingsRootView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var model = viewModel

        NavigationStack {
            Form {
                Section("设备诊断") {
                    if let status = viewModel.currentStatus {
                        SettingsRow(label: "连接", value: "已连接")
                        SettingsRow(label: "设备 ID", value: status.id)
                        SettingsRow(label: "固件版本", value: status.firmwareVersion.isEmpty ? "—" : status.firmwareVersion)
                        SettingsRow(label: "当前模式", value: status.mode.displayName)
                        SettingsRow(label: "相机状态", value: status.cameraRunning ? "运行中" : "待机")
                        SettingsRow(label: "电量", value: status.battery.displayText)
                        SettingsRow(label: "SD 卡", value: status.cardAvailable ? "已挂载" : "不可用")
                        SettingsRow(label: "剩余容量", value: status.freeCapacityText)
                        SettingsRow(label: "NFS 传输", value: status.nfsUsed ? "开启" : "关闭")
                    } else {
                        SettingsRow(label: "连接", value: viewModel.isConnectingToDevice ? "连接中" : "未连接")
                    }

                    Button {
                        viewModel.refreshStatus()
                    } label: {
                        SettingsActionLabel(
                            title: "刷新状态",
                            systemImage: "arrow.clockwise",
                            isBusy: viewModel.isDeviceBusy
                        )
                    }
                    .disabled(viewModel.currentStatus == nil || viewModel.isDeviceBusy)

                    Button {
                        if viewModel.currentStatus == nil {
                            viewModel.connect()
                        } else {
                            viewModel.disconnect()
                        }
                    } label: {
                        Label(viewModel.currentStatus == nil ? "连接眼镜" : "断开连接", systemImage: viewModel.currentStatus == nil ? "wifi" : "wifi.slash")
                    }
                    .disabled(viewModel.isDeviceBusy)
                }

                Section {
                    Toggle("循环录制", isOn: $model.runningMode.isActive)
                        .tint(Color.orbiPrimary)
                    Stepper("总时长 \(Int(model.runningMode.totalTimeMinutes)) 分钟", value: $model.runningMode.totalTimeMinutes, in: 5...720, step: 5)
                        .disabled(!model.runningMode.isActive)
                    Stepper("录制间隔 \(Int(model.runningMode.recIntervalSeconds)) 秒", value: $model.runningMode.recIntervalSeconds, in: 5...3600, step: 5)
                        .disabled(!model.runningMode.isActive)
                    Stepper("待机间隔 \(Int(model.runningMode.idleIntervalSeconds)) 秒", value: $model.runningMode.idleIntervalSeconds, in: 5...3600, step: 5)
                        .disabled(!model.runningMode.isActive)
                    Toggle("待机时关闭 WiFi", isOn: $model.runningMode.turnOffWiFi)
                        .tint(Color.orbiPrimary)
                        .disabled(!model.runningMode.isActive)

                    Button {
                        viewModel.saveRunningMode()
                    } label: {
                        SettingsActionLabel(
                            title: "保存运行模式",
                            systemImage: "timer",
                            isBusy: viewModel.isSettingsBusy
                        )
                    }
                    .disabled(viewModel.currentStatus == nil || viewModel.isSettingsBusy)
                    .tint(Color.orbiPrimary)
                } header: {
                    Text("运行模式")
                } footer: {
                    Text("会按官方 Android 包的 set-settings/video_params 格式写入眼镜。关闭循环录制时会把 rec_timeout 写为 0。")
                }

                Section("存储") {
                    Button(role: .destructive) {
                        viewModel.formatSDCard()
                    } label: {
                        SettingsActionLabel(
                            title: "快速格式化 SD 卡",
                            systemImage: "sdcard",
                            isBusy: viewModel.isSettingsBusy
                        )
                    }
                    .disabled(viewModel.currentStatus == nil || viewModel.isSettingsBusy)
                }

                Section("WiFi 设置") {
                    TextField("名称", text: $model.wifiCredentials.ssid)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("密码", text: $model.wifiCredentials.password)
                    SecureField("确认密码", text: $model.wifiCredentials.passwordVerify)
                    Button {
                        viewModel.saveWiFi()
                    } label: {
                        SettingsActionLabel(
                            title: "保存 WiFi 热点",
                            systemImage: "wifi.router",
                            isBusy: viewModel.isSettingsBusy
                        )
                    }
                    .disabled(viewModel.currentStatus == nil || viewModel.isSettingsBusy)
                        .tint(Color.orbiPrimary)
                }
                Section("技术支持") {
                    TextField("邮箱地址", text: $model.supportEmail)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextEditor(text: $model.supportDescription)
                        .frame(minHeight: 80)
                    Button("发送报告") {
                        viewModel.message = "报告已发送，感谢反馈！"
                    }
                    .tint(Color.orbiPrimary)
                }
                Section("法律信息") {
                    Link("条款与条件", destination: URL(string: "https://orbiprime.com/terms-and-conditions.php")!)
                    Link("隐私政策", destination: URL(string: "https://orbiprime.com/privacy.php")!)
                }
            }
            .navigationTitle("设置")
            .scrollContentBackground(.hidden)
            .background(Color.orbiPanel)
        }
    }
}

struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.orbiBlackText)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

struct SettingsActionLabel: View {
    let title: String
    let systemImage: String
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
    }
}

// MARK: - Media Editor (360 Player Entry)

struct MediaEditorView: View {
    let item: OrbiMediaItem
    @Environment(AppViewModel.self) private var viewModel

    private var videoFileURL: URL? {
        let mediaDir = OrbiLocalMediaStore.mediaDirectory
        for ext in [item.type.fileExtension, item.type.fileExtension.lowercased()] {
            let url = mediaDir.appendingPathComponent("\(item.name)\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = videoFileURL {
                Orbi360PlayerView(videoURL: url)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("视频未下载到手机")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("请从眼镜传输视频后播放 360° 全景")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("传输") {
                        viewModel.download(item)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orbiPrimary)
                }
            }
        }
        .navigationTitle(item.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Photo Viewer

struct PhotoViewerView: View {
    let item: OrbiMediaItem
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = loadImage() {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in scale = lastScale * value }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1 {
                                    withAnimation { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                                }
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1 {
                                scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                            } else {
                                scale = 2; lastScale = 2
                            }
                        }
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(item.name)
                        .foregroundStyle(.white)
                    Text("图片不可用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(item.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadImage() -> Image? {
        let url = OrbiLocalMediaStore.mediaDirectory.appendingPathComponent("\(item.name)\(item.type.fileExtension)")
        #if canImport(UIKit)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
}

// MARK: - Thumbnail Cache

enum ThumbnailCache {
    private static var cache: [String: AnyObject] = [:]
    private static let lock = NSLock()

    static func image(forPath path: String) -> AnyObject? {
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }

    static func setImage(_ image: AnyObject, forPath path: String) {
        lock.lock(); defer { lock.unlock() }
        if cache.count > 50, let key = cache.keys.first {
            cache.removeValue(forKey: key)
        }
        cache[path] = image
    }

    static func clear() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - Extensions

private extension Text {
    func orbiMediaTab() -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 40)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.8)).frame(height: 2)
            }
    }
}

private extension DeviceMode {
    var displayName: String {
        switch self {
        case .none: return "未设置"
        case .photo: return "拍照"
        case .live: return "实时预览"
        case .video: return "录像"
        }
    }
}

private extension DeviceBattery {
    var displayText: String {
        switch self {
        case .charging: return "充电中"
        default: return percentText
        }
    }
}

private extension OrbiDeviceStatus {
    var freeCapacityText: String {
        guard sdFreeCapacity > 0 else { return "—" }
        let gigabytes = Double(sdFreeCapacity) / 1_073_741_824
        if gigabytes >= 1 {
            return String(format: "%.1f GB", gigabytes)
        }
        let megabytes = Double(sdFreeCapacity) / 1_048_576
        return String(format: "%.0f MB", megabytes)
    }
}

private extension TimeInterval {
    var formattedDuration: String {
        let total = Int(self)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
