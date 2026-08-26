import SwiftUI
import AVFoundation
import Metal
import MetalKit
import simd

// MARK: - 360° Player View

struct Orbi360PlayerView: View {
    let videoURL: URL

    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var fov: Float = 75
    @State private var lastYaw: Float = 0
    @State private var lastPitch: Float = 0
    @State private var lastFov: Float = 75
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var seekTime: Double?
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Orbi360MetalView(
                videoURL: videoURL,
                yaw: yaw,
                pitch: pitch,
                fov: fov,
                isPlaying: isPlaying,
                seekTime: seekTime,
                onTimeUpdate: { time, dur in
                    currentTime = time
                    duration = dur
                },
                onSeekComplete: { seekTime = nil }
            )
            .gesture(dragGesture)
            .gesture(magnificationGesture)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls.toggle()
                }
            }

            if showControls {
                VStack {
                    topBar
                    Spacer()
                    bottomControls
                }
                .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Top Bar

    private var topBar: some View {
        HStack {
            Text("360\u{00B0} 全景")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                yaw = 0; pitch = 0; fov = 75
                lastYaw = 0; lastPitch = 0; lastFov = 75
            } label: {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { newValue in
                            currentTime = newValue
                            seekTime = newValue
                        }
                    ),
                    in: 0...max(duration, 1)
                )
                .tint(Color.orbiPrimary)
                Text(formatTime(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 50) {
                Button {
                    let target = max(0, currentTime - 10)
                    seekTime = target
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                }

                Button {
                    let target = min(duration, currentTime + 10)
                    seekTime = target
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
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
                fov = max(30, min(110, newFov))
            }
            .onEnded { _ in
                lastFov = fov
            }
    }

    // MARK: Helpers

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Metal View (UIViewRepresentable)

struct Orbi360MetalView: UIViewRepresentable {
    let videoURL: URL
    let yaw: Float
    let pitch: Float
    let fov: Float
    let isPlaying: Bool
    let seekTime: Double?
    let onTimeUpdate: (Double, Double) -> Void
    let onSeekComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(videoURL: videoURL, onTimeUpdate: onTimeUpdate)
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
        context.coordinator.setupPlayer()
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let c = context.coordinator
        c.yaw = yaw
        c.pitch = pitch
        c.fov = fov

        if c.isPlaying != isPlaying {
            c.setPlaying(isPlaying)
        }

        if let seek = seekTime, abs(c.currentTime - seek) > 0.5 {
            c.seek(to: seek)
            onSeekComplete()
        }
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        private let commandQueue: MTLCommandQueue
        private var pipelineState: MTLRenderPipelineState
        private var vertexBuffer: MTLBuffer
        private var indexCount: Int
        private var indexBuffer: MTLBuffer
        private var uniformBuffer: MTLBuffer
        private var textureCache: CVMetalTextureCache?

        private var player: AVPlayer?
        private var videoOutput: AVPlayerItemVideoOutput?
        private var timeObserver: Any?
        private var playerItem: AVPlayerItem?

        var yaw: Float = 0
        var pitch: Float = 0
        var fov: Float = 75
        var isPlaying = false
        var currentTime: Double = 0

        private var currentTexture: MTLTexture?
        private var currentCVTexture: CVMetalTexture?

        private let onTimeUpdate: (Double, Double) -> Void
        private let videoURL: URL

        init(videoURL: URL, onTimeUpdate: @escaping (Double, Double) -> Void) {
            self.videoURL = videoURL
            self.onTimeUpdate = onTimeUpdate

            guard let device = MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue() else {
                fatalError("Metal is not available on this device")
            }
            self.device = device
            self.commandQueue = commandQueue

            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)

            let library = try! device.makeLibrary(source: Self.metalSource, options: nil)
            let vertexFunction = library.makeFunction(name: "sphere_vertex")!
            let fragmentFunction = library.makeFunction(name: "equirect_fragment")!

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 3
            pipelineDescriptor.vertexDescriptor = vertexDescriptor

            self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)

            let (vertices, indices) = Self.generateSphere(segments: 64, rings: 32)
            self.vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<Float>.stride,
                options: []
            )!
            self.indexCount = indices.count
            self.indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indices.count * MemoryLayout<UInt16>.stride,
                options: []
            )!
            self.uniformBuffer = device.makeBuffer(
                length: MemoryLayout<simd_float4x4>.stride * 2,
                options: []
            )!
            self.textureCache = cache
            super.init()
        }

        // MARK: Player Setup

        func setupPlayer() {
            let item = AVPlayerItem(url: videoURL)

            let output = AVPlayerItemVideoOutput(
                pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
                ]
            )
            item.add(output)
            self.videoOutput = output
            self.playerItem = item

            let player = AVPlayer(playerItem: item)
            self.player = player

            let interval = CMTime(value: 1, timescale: 10)
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self] time in
                guard let self = self else { return }
                let t = CMTimeGetSeconds(time)
                let d = CMTimeGetSeconds(item.duration)
                self.currentTime = t
                self.onTimeUpdate(t, d.isFinite ? d : 0)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemDidReachEnd),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item
            )

            player.play()
            isPlaying = true
        }

        @objc private func playerItemDidReachEnd() {
            player?.seek(to: .zero)
            player?.play()
        }

        func setPlaying(_ playing: Bool) {
            isPlaying = playing
            if playing {
                player?.play()
            } else {
                player?.pause()
            }
        }

        func seek(to time: Double) {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = time
        }

        func cleanup() {
            player?.pause()
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            NotificationCenter.default.removeObserver(self)
            player = nil
            videoOutput = nil
            playerItem = nil
            currentTexture = nil
            currentCVTexture = nil
        }

        // MARK: MTKViewDelegate

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

            updateVideoTexture()

            let aspect = Float(view.drawableSize.width / max(1, view.drawableSize.height))
            var projection = Self.perspectiveMatrix(
                fov: fov * .pi / 180,
                aspect: aspect,
                near: 0.01,
                far: 100
            )
            var rotation = Self.rotationMatrix(yaw: yaw, pitch: pitch)

            let ptr = uniformBuffer.contents()
            memcpy(ptr, &projection, MemoryLayout<simd_float4x4>.stride)
            memcpy(ptr.advanced(by: MemoryLayout<simd_float4x4>.stride), &rotation, MemoryLayout<simd_float4x4>.stride)

            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

            if let texture = currentTexture {
                encoder.setFragmentTexture(texture, index: 0)
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

        // MARK: Video Texture

        private func updateVideoTexture() {
            guard let videoOutput = videoOutput,
                  let textureCache = textureCache,
                  let playerItem = playerItem else { return }

            let itemTime = playerItem.currentTime()
            guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime) else { return }

            guard let pixelBuffer = videoOutput.copyPixelBuffer(
                forItemTime: itemTime,
                itemTimeForDisplay: nil
            ) else { return }

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(
                nil,
                textureCache,
                pixelBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &cvTexture
            )

            if let cvTexture = cvTexture {
                currentCVTexture = cvTexture
                currentTexture = CVMetalTextureGetTexture(cvTexture)
            }
        }

        // MARK: Matrix Helpers

        static func perspectiveMatrix(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
            let f = 1 / tan(fov / 2)
            return simd_float4x4(
                simd_float4(f / aspect, 0, 0, 0),
                simd_float4(0, f, 0, 0),
                simd_float4(0, 0, far / (near - far), -1),
                simd_float4(0, 0, near * far / (near - far), 0)
            )
        }

        static func rotationMatrix(yaw: Float, pitch: Float) -> simd_float4x4 {
            let cy = cos(yaw), sy = sin(yaw)
            let cp = cos(pitch), sp = sin(pitch)
            return simd_float4x4(
                simd_float4(cy, sp * sy, -cp * sy, 0),
                simd_float4(0, cp, sp, 0),
                simd_float4(sy, -sp * cy, cp * cy, 0),
                simd_float4(0, 0, 0, 1)
            )
        }

        // MARK: Sphere Geometry

        static func generateSphere(segments: Int, rings: Int) -> (vertices: [Float], indices: [UInt16]) {
            var vertices: [Float] = []
            var indices: [UInt16] = []

            for ring in 0...rings {
                let phi = Float(ring) / Float(rings) * Float.pi
                for segment in 0...segments {
                    let theta = Float(segment) / Float(segments) * 2 * Float.pi
                    let x = sin(phi) * cos(theta)
                    let y = cos(phi)
                    let z = sin(phi) * sin(theta)
                    vertices.append(contentsOf: [x, y, z])
                }
            }

            for ring in 0..<rings {
                for segment in 0..<segments {
                    let a = UInt16(ring * (segments + 1) + segment)
                    let b = UInt16(Int(a) + segments + 1)
                    indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
                }
            }

            return (vertices, indices)
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
        """
    }
}
