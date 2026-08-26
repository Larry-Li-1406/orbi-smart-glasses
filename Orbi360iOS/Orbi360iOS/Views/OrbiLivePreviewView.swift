import SwiftUI
import AVFoundation
import Metal
import MetalKit
import Network
import VideoToolbox
import simd

// MARK: - Live Preview View

struct OrbiLivePreviewView: View {
    @Environment(AppViewModel.self) private var viewModel

    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var fov: Float = 90
    @State private var lastYaw: Float = 0
    @State private var lastPitch: Float = 0
    @State private var lastFov: Float = 90
    @State private var isConnected = false
    @State private var frameCount: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            OrbiLivePreviewMetalView(
                deviceIP: OrbiProtocol.deviceIP,
                ports: OrbiProtocol.livePreviewPorts,
                isStreaming: viewModel.isCameraRunning,
                yaw: yaw,
                pitch: pitch,
                fov: fov,
                onFrame: { count in
                    frameCount = count
                },
                onConnectionChange: { connected in
                    isConnected = connected
                }
            )
            .gesture(dragGesture)
            .gesture(magnificationGesture)

            // Overlay: top status bar
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isCameraRunning ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                            .opacity(viewModel.isCameraRunning ? 0.8 : 0.4)
                            .scaleEffect(viewModel.isCameraRunning ? 1.0 : 0.8)
                            .animation(
                                viewModel.isCameraRunning
                                    ? .easeInOut(duration: 0.8).repeatForever()
                                    : .default,
                                value: viewModel.isCameraRunning
                            )
                        Text(viewModel.isCameraRunning ? "直播中" : "待机")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.5)))

                    Spacer()

                    if isConnected {
                        Text("\(frameCount) 帧")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                    }

                    Button {
                        yaw = 0; pitch = 0; fov = 90
                        lastYaw = 0; lastPitch = 0; lastFov = 90
                    } label: {
                        Image(systemName: "location.north.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
                .padding()
                .background(LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))

                Spacer()

                // Bottom: connection info + start/stop
                VStack(spacing: 10) {
                    if !viewModel.isCameraRunning {
                        VStack(spacing: 4) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(.white.opacity(0.5))
                            Text("实时预览")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("点击开始连接眼镜预览画面")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    HStack(spacing: 16) {
                        Button {
                            if viewModel.isCameraRunning {
                                viewModel.stopLivePreview()
                            } else {
                                viewModel.startLivePreview()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if viewModel.isCameraBusy {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: viewModel.isCameraRunning ? "stop.fill" : "play.fill")
                                }
                                Text(viewModel.isCameraRunning ? "停止" : "开始")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(viewModel.isCameraRunning ? Color.red.opacity(0.8) : Color.orbiPrimary))
                            .foregroundStyle(.white)
                        }
                        .disabled(viewModel.isCameraBusy)
                        .opacity(viewModel.isCameraBusy ? 0.7 : 1)

                        if viewModel.isCameraRunning {
                            Label(
                                isConnected ? "已连接" : "连接中\u{2026}",
                                systemImage: isConnected ? "wifi" : "wifi.exclamationmark"
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let sensitivity: Float = 0.005
                yaw = lastYaw + Float(value.translation.width) * sensitivity
                pitch = max(
                    min(lastPitch + Float(value.translation.height) * sensitivity, Float.pi / 2 - 0.01),
                    -Float.pi / 2 + 0.01
                )
            }
            .onEnded { _ in
                lastYaw = yaw
                lastPitch = pitch
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newFov = lastFov / Float(value)
                fov = max(40, min(120, newFov))
            }
            .onEnded { _ in
                lastFov = fov
            }
    }
}

// MARK: - Metal View (UIViewRepresentable)

struct OrbiLivePreviewMetalView: UIViewRepresentable {
    let deviceIP: String
    let ports: [Int]
    let isStreaming: Bool
    let yaw: Float
    let pitch: Float
    let fov: Float
    let onFrame: (Int) -> Void
    let onConnectionChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            deviceIP: deviceIP,
            ports: ports,
            onFrame: onFrame,
            onConnectionChange: onConnectionChange
        )
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.delegate = context.coordinator
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = false
        view.isOpaque = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let c = context.coordinator
        c.yaw = yaw
        c.pitch = pitch
        c.fov = fov

        if isStreaming && !c.isReceiving {
            c.startReceiving()
        } else if !isStreaming && c.isReceiving {
            c.stopReceiving()
        }
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    // MARK: Stream Format

    enum StreamFormat {
        case unknown
        case jpeg
        case h264
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private var texturePipeline: MTLRenderPipelineState
        private var demoPipeline: MTLRenderPipelineState
        private var vertexBuffer: MTLBuffer
        private var indexCount: Int
        private var indexBuffer: MTLBuffer
        private var uniformBuffer: MTLBuffer
        private var textureCache: CVMetalTextureCache?
        private var demoTime: Float = 0

        private var connections: [NWConnection]
        private var receiveBuffer = Data()
        private let onFrame: (Int) -> Void
        private let onConnectionChange: (Bool) -> Void
        private let deviceIP: String
        private let ports: [Int]

        var yaw: Float = 0
        var pitch: Float = 0
        var fov: Float = 90
        var isReceiving = false
        private var frameCount = 0
        private var _currentTexture: MTLTexture?
        private var _currentCVTexture: CVMetalTexture?
        private let textureLock = NSLock()
        private var streamDecoder: OrbiLiveStreamDecoder?
        private var streamFormat: StreamFormat = .unknown

        private var currentTexture: MTLTexture? {
            get { textureLock.lock(); defer { textureLock.unlock() }; return _currentTexture }
            set { textureLock.lock(); defer { textureLock.unlock() }; _currentTexture = newValue }
        }

        private var currentCVTexture: CVMetalTexture? {
            get { textureLock.lock(); defer { textureLock.unlock() }; return _currentCVTexture }
            set { textureLock.lock(); defer { textureLock.unlock() }; _currentCVTexture = newValue }
        }

        init(deviceIP: String, ports: [Int], onFrame: @escaping (Int) -> Void, onConnectionChange: @escaping (Bool) -> Void) {
            self.deviceIP = deviceIP
            self.ports = ports
            self.onFrame = onFrame
            self.onConnectionChange = onConnectionChange
            self.connections = []

            guard let device = MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue() else {
                fatalError("Metal is not available")
            }
            self.device = device
            self.commandQueue = commandQueue

            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)

            let library = try! device.makeLibrary(source: Self.metalSource, options: nil)

            // Texture pipeline (for real video frames)
            let textureVert = library.makeFunction(name: "sphere_vertex")!
            let textureFrag = library.makeFunction(name: "equirect_fragment")!
            let texDesc = MTLRenderPipelineDescriptor()
            texDesc.vertexFunction = textureVert
            texDesc.fragmentFunction = textureFrag
            texDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            let vertDesc = MTLVertexDescriptor()
            vertDesc.attributes[0].format = .float3
            vertDesc.attributes[0].bufferIndex = 0
            vertDesc.attributes[0].offset = 0
            vertDesc.layouts[0].stride = MemoryLayout<Float>.stride * 3
            texDesc.vertexDescriptor = vertDesc
            self.texturePipeline = try! device.makeRenderPipelineState(descriptor: texDesc)

            // Demo pipeline (procedural pattern)
            let demoFrag = library.makeFunction(name: "demo_fragment")!
            let demoDesc = MTLRenderPipelineDescriptor()
            demoDesc.vertexFunction = textureVert
            demoDesc.fragmentFunction = demoFrag
            demoDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            demoDesc.vertexDescriptor = vertDesc
            self.demoPipeline = try! device.makeRenderPipelineState(descriptor: demoDesc)

            let (vertices, indices) = Orbi360MetalView.Coordinator.generateSphere(segments: 64, rings: 32)
            self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: [])!
            self.indexCount = indices.count
            self.indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: [])!
            self.uniformBuffer = device.makeBuffer(length: MemoryLayout<simd_float4x4>.stride * 2, options: [])!
            self.textureCache = cache
            super.init()
        }

        // MARK: TCP Receiving

        func startReceiving() {
            print("[ORBI DEBUG] Live preview start receiving from \(deviceIP) ports=\(ports)")
            isReceiving = true
            streamFormat = .unknown
            receiveBuffer.removeAll()
            streamDecoder = OrbiLiveStreamDecoder { [weak self] pixelBuffer in
                self?.handleDecodedFrame(pixelBuffer)
            }
            connections = ports.enumerated().map { index, port in
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(deviceIP),
                    port: NWEndpoint.Port(integerLiteral: UInt16(port))
                )
                let conn = NWConnection(to: endpoint, using: .tcp)
                conn.stateUpdateHandler = { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        print("[ORBI DEBUG] Live preview port \(port) ready")
                        DispatchQueue.main.async {
                            self.onConnectionChange(true)
                        }
                        self.receiveData(from: conn)
                    case .failed, .cancelled:
                        print("[ORBI DEBUG] Live preview port \(port) \(state)")
                        DispatchQueue.main.async {
                            self.onConnectionChange(false)
                        }
                    default:
                        break
                    }
                }
                conn.start(queue: .global(qos: .userInitiated))
                return conn
            }
        }

        func stopReceiving() {
            print("[ORBI DEBUG] Live preview stop receiving")
            isReceiving = false
            streamFormat = .unknown
            for conn in connections {
                conn.cancel()
            }
            connections.removeAll()
            streamDecoder = nil
            currentTexture = nil
            currentCVTexture = nil
            receiveBuffer.removeAll(keepingCapacity: true)
            DispatchQueue.main.async {
                self.onConnectionChange(false)
            }
        }

        private func receiveData(from connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
                guard let self = self else { return }
                if let error = error {
                    print("[ORBI DEBUG] Live preview receive error: \(error)")
                    return
                }
                if let data = data, !data.isEmpty {
                    if self.frameCount == 0 {
                        print("[ORBI DEBUG] Live preview received first chunk \(data.count) bytes")
                    }
                    self.processReceivedData(data)
                }
                if self.isReceiving {
                    self.receiveData(from: connection)
                }
            }
        }

        private func processReceivedData(_ data: Data) {
            receiveBuffer.append(data)
            guard receiveBuffer.count > 4 else { return }

            // Detect format once and remember it (sticky detection)
            if streamFormat == .unknown {
                let bytes = [UInt8](receiveBuffer.prefix(8))
                if bytes[0] == 0xFF && bytes[1] == 0xD8 {
                    streamFormat = .jpeg
                    print("[ORBI DEBUG] Live preview detected JPEG stream")
                } else if (bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x00 && bytes[3] == 0x01) ||
                          (bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01) {
                    streamFormat = .h264
                    print("[ORBI DEBUG] Live preview detected H264 stream")
                } else {
                    // Unknown — discard old data but keep last 256 bytes
                    if receiveBuffer.count > 1024 {
                        receiveBuffer.removeFirst(receiveBuffer.count - 256)
                    }
                    return
                }
            }

            switch streamFormat {
            case .h264:
                // Find all NAL start-code positions in the buffer
                let bytes = [UInt8](receiveBuffer)
                var startPositions: [Int] = []
                var i = 0
                while i < bytes.count - 2 {
                    if i + 3 < bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                        startPositions.append(i)
                        i += 4
                    } else if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                        startPositions.append(i)
                        i += 3
                    } else {
                        i += 1
                    }
                }

                if startPositions.count >= 2 {
                    // Process complete NAL units (up to the last start code)
                    let lastStart = startPositions.last!
                    let completeData = receiveBuffer.subdata(in: 0..<lastStart)
                    streamDecoder?.processData(completeData)
                    // Keep the incomplete last NAL unit for next receive
                    receiveBuffer = receiveBuffer.subdata(in: lastStart..<receiveBuffer.count)
                }
                // If only one start code found, wait for more data

            case .jpeg:
                // JPEG mode: find frame boundaries (FFD8 ... FFD9)
                while receiveBuffer.count > 4 {
                    let startIdx = receiveBuffer.firstRange(of: Data([0xFF, 0xD8]))?.lowerBound
                    guard let start = startIdx else {
                        receiveBuffer.removeAll(keepingCapacity: true)
                        return
                    }
                    if start > 0 {
                        receiveBuffer.removeFirst(start)
                    }
                    guard let end = receiveBuffer.firstRange(of: Data([0xFF, 0xD9]))?.upperBound else {
                        break
                    }
                    let frameData = receiveBuffer.subdata(in: 0..<end)
                    receiveBuffer.removeFirst(end)
                    handleJPEGFrame(frameData)
                }

            case .unknown:
                break
            }
        }

        private func handleJPEGFrame(_ data: Data) {
            #if canImport(UIKit)
            guard let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else { return }
            createTexture(from: cgImage)
            #endif
        }

        private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer) {
            guard let textureCache = textureCache else { return }

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                nil, textureCache, pixelBuffer, nil,
                .bgra8Unorm, width, height, 0, &cvTexture
            )
            if let cvTexture = cvTexture {
                currentCVTexture = cvTexture
                currentTexture = CVMetalTextureGetTexture(cvTexture)
                frameCount += 1
                if frameCount == 1 {
                    print("[ORBI DEBUG] Live preview first decoded H264 frame \(width)x\(height)")
                }
                DispatchQueue.main.async {
                    self.onFrame(self.frameCount)
                }
            }
        }

        private func createTexture(from cgImage: CGImage) {
            guard let textureCache = textureCache else { return }

            let width = cgImage.width
            let height = cgImage.height

            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                nil, width, height,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]] as CFDictionary,
                &pixelBuffer
            )
            guard let pb = pixelBuffer else { return }

            CVPixelBufferLockBaseAddress(pb, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(pb, [])

            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                nil, textureCache, pb, nil,
                .bgra8Unorm, width, height, 0, &cvTexture
            )
            if let cvTexture = cvTexture {
                currentCVTexture = cvTexture
                currentTexture = CVMetalTextureGetTexture(cvTexture)
                frameCount += 1
                if frameCount == 1 {
                    print("[ORBI DEBUG] Live preview first JPEG frame \(width)x\(height)")
                }
                DispatchQueue.main.async {
                    self.onFrame(self.frameCount)
                }
            }
        }

        // MARK: MTKViewDelegate

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

            demoTime += 1.0 / 60.0

            let aspect = Float(view.drawableSize.width / max(1, view.drawableSize.height))
            var projection = Orbi360MetalView.Coordinator.perspectiveMatrix(
                fov: fov * .pi / 180, aspect: aspect, near: 0.01, far: 100
            )
            var rotation = Orbi360MetalView.Coordinator.rotationMatrix(yaw: yaw, pitch: pitch)

            let ptr = uniformBuffer.contents()
            memcpy(ptr, &projection, MemoryLayout<simd_float4x4>.stride)
            memcpy(ptr.advanced(by: MemoryLayout<simd_float4x4>.stride), &rotation, MemoryLayout<simd_float4x4>.stride)

            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

            // Use demo pipeline if no video texture
            // Capture texture once to avoid race with network thread
            let texture = currentTexture
            let hasTexture = texture != nil
            encoder.setRenderPipelineState(hasTexture ? texturePipeline : demoPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

            if hasTexture {
                encoder.setFragmentTexture(texture, index: 0)
            }

            // Pass demo time to fragment shader via uniform buffer
            if !hasTexture {
                var time = demoTime
                let timeBuffer = device.makeBuffer(bytes: &time, length: MemoryLayout<Float>.stride, options: [])
                encoder.setFragmentBuffer(timeBuffer, offset: 0, index: 0)
            }

            encoder.setCullMode(.none)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        // MARK: Cleanup

        func cleanup() {
            stopReceiving()
        }

        // MARK: Metal Shader Source

        static let metalSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float3 direction;
        };

        struct Uniforms {
            float4x4 projection;
            float4x4 rotation;
        };

        vertex VertexOut sphere_vertex(
            uint vid [[vertex_id]],
            device const float3* positions [[buffer(0)]],
            constant Uniforms* uniforms [[buffer(1)]]
        ) {
            VertexOut out;
            float3 pos = positions[vid];
            out.direction = pos;
            float3 rotated = (uniforms->rotation * float4(pos, 1.0)).xyz;
            out.position = uniforms->projection * float4(rotated, 1.0);
            return out;
        }

        fragment float4 equirect_fragment(
            VertexOut in [[stage_in]],
            texture2d<float> equirect [[texture(0)]]
        ) {
            constexpr sampler s(coord::normalized, address::repeat, filter::linear);
            float3 dir = normalize(in.direction);
            float yaw = atan2(dir.x, dir.z);
            float pitch = asin(clamp(dir.y, -1.0, 1.0));
            float u = yaw / (2.0 * M_PI_F) + 0.5;
            float v = 0.5 - pitch / M_PI_F;
            return equirect.sample(s, float2(u, v));
        }

        fragment float4 demo_fragment(
            VertexOut in [[stage_in]],
            constant float* time [[buffer(0)]]
        ) {
            float3 dir = normalize(in.direction);
            float yaw = atan2(dir.x, dir.z);
            float pitch = asin(clamp(dir.y, -1.0, 1.0));
            float u = yaw / (2.0 * M_PI_F) + 0.5;
            float v = 0.5 - pitch / M_PI_F;
            float t = *time;

            // Grid pattern
            float gridSize = 16.0;
            float2 grid = fract(float2(u, v) * gridSize);
            float gridLine = step(0.96, grid.x) + step(0.96, grid.y);

            // Animated gradient
            float3 color = float3(
                0.5 + 0.3 * sin(u * 6.0 + t * 0.5),
                0.3 + 0.2 * cos(v * 4.0 + t * 0.3),
                0.6 + 0.2 * sin((u + v) * 5.0 + t)
            );

            // Cardinal direction markers
            float north = smoothstep(0.02, 0.0, abs(u - 0.5) + abs(v - 0.0));
            float south = smoothstep(0.02, 0.0, abs(u - 0.0) + abs(v - 0.5));
            float east = smoothstep(0.02, 0.0, abs(u - 0.75) + abs(v - 0.5));
            float west = smoothstep(0.02, 0.0, abs(u - 0.25) + abs(v - 0.5));

            color = mix(color, float3(1.0, 0.3, 0.3), north);
            color = mix(color, float3(0.3, 1.0, 0.3), south);
            color = mix(color, float3(0.3, 0.3, 1.0), east);
            color = mix(color, float3(1.0, 1.0, 0.3), west);

            // Grid overlay
            color = mix(color, float3(1.0), gridLine * 0.3);

            return float4(color, 1.0);
        }
        """
    }
}

// MARK: - H.264 Live Stream Decoder

final class OrbiLiveStreamDecoder {
    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private let onDecode: (CVPixelBuffer) -> Void

    init(onDecode: @escaping (CVPixelBuffer) -> Void) {
        self.onDecode = onDecode
    }

    func processData(_ data: Data) {
        let nalUnits = findNALUnits(in: data)
        for nal in nalUnits {
            handleNALUnit(nal)
        }
    }

    // MARK: NAL Unit Parsing

    private func findNALUnits(in data: Data) -> [Data] {
        var units: [Data] = []
        var i = 0
        let bytes = [UInt8](data)

        while i < bytes.count {
            // Find start code: 00 00 00 01 or 00 00 01
            var startCodeLen = 0
            if i + 3 < bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                startCodeLen = 4
            } else if i + 2 < bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                startCodeLen = 3
            }

            if startCodeLen > 0 {
                // Find next start code
                var nextStart = bytes.count
                let searchStart = i + startCodeLen + 1
                let searchEnd = bytes.count - 2
                if searchStart < searchEnd {
                    for j in searchStart..<searchEnd {
                        if bytes[j] == 0 && bytes[j + 1] == 0 && (bytes[j + 2] == 1 || (j + 3 < bytes.count && bytes[j + 2] == 0 && bytes[j + 3] == 1)) {
                            nextStart = j
                            break
                        }
                    }
                }
                let nalData = data.subdata(in: (i + startCodeLen)..<nextStart)
                units.append(nalData)
                i = nextStart
            } else {
                i += 1
            }
        }
        return units
    }

    private func handleNALUnit(_ nalData: Data) {
        guard !nalData.isEmpty else { return }
        let nalType = nalData[nalData.startIndex] & 0x1F

        switch nalType {
        case 7: // SPS
            sps = nalData
            tryCreateSession()
        case 8: // PPS
            pps = nalData
            tryCreateSession()
        case 5, 1: // IDR or non-IDR slice
            decodeFrame(nalData)
        default:
            break
        }
    }

    // MARK: Session Creation

    private func tryCreateSession() {
        guard let sps = sps, let pps = pps else { return }

        var formatDesc: CMVideoFormatDescription?

        sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress!
                let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress!

                let pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let sizes: [Int] = [sps.count, pps.count]

                pointers.withUnsafeBufferPointer { ptrBuf in
                    sizes.withUnsafeBufferPointer { sizeBuf in
                        _ = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: nil,
                            parameterSetCount: 2,
                            parameterSetPointers: ptrBuf.baseAddress!,
                            parameterSetSizes: sizeBuf.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDesc
                        )
                    }
                }
            }
        }

        guard let formatDescription = formatDesc else { return }
        self.formatDescription = formatDescription

        let callback: @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
            OSStatus, VTDecodeInfoFlags, CVImageBuffer?,
            CMTime, CMTime
        ) -> Void = { refcon, _, status, _, imageBuffer, _, _ in
            guard let refcon = refcon, status == noErr, let buffer = imageBuffer else { return }
            let decoder = Unmanaged<OrbiLiveStreamDecoder>.fromOpaque(refcon).takeUnretainedValue()
            decoder.onDecode(buffer)
        }

        var record = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: callback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var newSession: VTDecompressionSession?
        let result = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: nil,
            outputCallback: &record,
            decompressionSessionOut: &newSession
        )

        if result == noErr {
            session = newSession
        }
    }

    // MARK: Frame Decoding

    private func decodeFrame(_ nalData: Data) {
        guard let session = session, let formatDescription = formatDescription else { return }

        // Convert Annex B to AVCC: replace start code with 4-byte big-endian length
        var avccData = Data()
        let nalLength = UInt32(nalData.count)
        var be = nalLength.bigEndian
        withUnsafeBytes(of: &be) { avccData.append(contentsOf: $0) }
        avccData.append(nalData)

        // Create CMBlockBuffer
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil,
            blockLength: avccData.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0,
            dataLength: avccData.count, flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard let blockBuffer = blockBuffer else { return }

        _ = avccData.withUnsafeBytes { rawBuf in
            CMBlockBufferReplaceDataBytes(
                with: rawBuf.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }

        // Create CMSampleBuffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )

        CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let sampleBuffer = sampleBuffer else { return }

        var infoFlags = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [],
            frameRefcon: nil,
            infoFlagsOut: &infoFlags
        )
    }
}
