// ─────────────────────────────────────────────────────────────────────────────
//  MetalEmulatorView.swift
//  YDrive iOS Native
//
//  UIViewRepresentable wrapping an MTKView that renders libretro frames.
//
//  Pixel format mapping from libretro → Metal:
//    YDrivePixelFormatRGB565   → MTLPixelFormatB5G6R5Unorm  (16-bit)
//    YDrivePixelFormatXRGB8888 → MTLPixelFormatBGRA8Unorm   (32-bit, X ignored)
//    YDrivePixelFormat0RGB1555 → MTLPixelFormatBGR5A1Unorm  (15-bit packed)
//
//  The view receives frames directly from LibretroEmulatorEngine via
//  VideoFrameConsumer and blits each new EmulatorFrame into an MTLTexture.
//
//  Aspect ratio is preserved using a letterbox/pillarbox approach:
//  the draw region is centred in the MTKView without stretching the image.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import MetalKit
import Metal
import os

private let log = Logger(subsystem: "com.yigit.ydrive", category: "MetalRenderer")

// ─────────────────────────────────────────────────────────────────────────────
struct MetalEmulatorView: UIViewRepresentable {

    @ObservedObject var engine: LibretroEmulatorEngine
    var videoFilter: String

    func makeCoordinator() -> MetalCoordinator {
        MetalCoordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device          = MTLCreateSystemDefaultDevice()
        view.delegate        = context.coordinator
        view.enableSetNeedsDisplay = false        // driven by display link at 60fps
        view.isPaused        = false
        view.preferredFramesPerSecond = 60
        view.clearColor      = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isUserInteractionEnabled = false     // never intercept or delay touch events

        context.coordinator.mtkView = view
        context.coordinator.setup(device: view.device)
        engine.videoFrameConsumer = context.coordinator
        log.info("[METAL] MTKView created, device: \(view.device?.name ?? "nil", privacy: .public)")
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if uiView.isPaused != engine.isPaused {
            uiView.isPaused = engine.isPaused
        }

        var mode: Int32 = 0
        if videoFilter == "CRT" { mode = 1 }
        else if videoFilter == "Simple CRT" { mode = 2 }
        context.coordinator.filterMode = mode
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: MetalCoordinator) {
        uiView.isPaused = true
        uiView.delegate = nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
final class MetalCoordinator: NSObject, MTKViewDelegate, VideoFrameConsumer, @unchecked Sendable {

    weak var mtkView: MTKView?

    // Metal objects
    private var device:          MTLDevice?
    private var commandQueue:    MTLCommandQueue?
    private var pipelineState:   MTLRenderPipelineState?
    private var texture:         MTLTexture?
    private var samplerState:    MTLSamplerState?
    private var vertexBuffer:    MTLBuffer?

    // Reusable conversion buffer (avoids per-frame heap allocation)
    private var stagingBuffer:   UnsafeMutablePointer<UInt32>?
    private var stagingCapacity: Int = 0

    // Pending frame from emulation queue (single-slot mailbox)
    private var pendingFrame:    EmulatorFrame?
    private let frameLock        = NSLock()
    
    var filterMode: Int32 = 0

    // Current texture dimensions
    private var texWidth:  Int = 0
    private var texHeight: Int = 0
    private var texFormat: YDrivePixelFormat = .rgb565

    // Fullscreen quad vertices: position (x,y) + uv (u,v)
    private let quadVertices: [Float] = [
        -1,  1,  0, 0,   // top-left
         1,  1,  1, 0,   // top-right
        -1, -1,  0, 1,   // bottom-left
         1, -1,  1, 1,   // bottom-right
    ]

    deinit {
        stagingBuffer?.deallocate()
    }

    // ── Setup ─────────────────────────────────────────────────────────────────
    func setup(device: MTLDevice?) {
        guard let device else {
            log.error("[METAL] No Metal device available")
            return
        }
        self.device       = device
        self.commandQueue = device.makeCommandQueue()

        // Vertex buffer (full-screen quad, updated per draw for aspect-correct rect)
        vertexBuffer = device.makeBuffer(bytes: quadVertices,
                                         length: quadVertices.count * MemoryLayout<Float>.size,
                                         options: .storageModeShared)

        // Sampler (nearest for pixel-perfect retro look)
        let samplerDesc              = MTLSamplerDescriptor()
        samplerDesc.minFilter        = .nearest
        samplerDesc.magFilter        = .nearest
        samplerDesc.sAddressMode     = .clampToEdge
        samplerDesc.tAddressMode     = .clampToEdge
        self.samplerState            = device.makeSamplerState(descriptor: samplerDesc)

        buildPipeline(device: device)
        log.info("[METAL] Setup complete")
    }

    // ── Pipeline ──────────────────────────────────────────────────────────────
    private func buildPipeline(device: MTLDevice) {
        // Inline Metal shaders (no separate .metal file required)
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vertex {
            float2 position [[attribute(0)]];
            float2 uv       [[attribute(1)]];
        };

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut vert(uint vid [[vertex_id]],
                              const device float4 *verts [[buffer(0)]]) {
            VertexOut out;
            out.position = float4(verts[vid].xy, 0, 1);
            out.uv       = verts[vid].zw;
            return out;
        }

        struct Uniforms {
            int filterMode;
        };

        fragment float4 frag(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler smp          [[sampler(0)]],
                             constant Uniforms &u [[buffer(1)]]) {
            float4 color = tex.sample(smp, in.uv);
            
            if (u.filterMode == 1) {
                // CRT: screen curve + scanlines + vignette
                float2 uv = in.uv;
                uv = uv * 2.0 - 1.0;
                uv *= 1.0 + pow(abs(uv.yx), float2(2.0)) / 10.0;
                uv = uv * 0.5 + 0.5;
                
                if(uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
                    return float4(0,0,0,1);
                }
                
                float4 texColor = tex.sample(smp, uv);
                float tex_y = uv.y * float(tex.get_height());
                float scanline = sin(tex_y * 3.14159) * 0.2 + 0.8;
                
                float vig = length(uv - 0.5);
                vig = smoothstep(0.7, 0.4, vig);
                
                return float4(texColor.rgb * scanline * vig, texColor.a);
            } else if (u.filterMode == 2) {
                // Simple CRT: just scanlines
                float tex_y = in.uv.y * float(tex.get_height());
                float scanline = sin(tex_y * 3.14159) * 0.15 + 0.85;
                return float4(color.rgb * scanline, color.a);
            }
            
            return color;
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertFn   = library.makeFunction(name: "vert"),
              let fragFn   = library.makeFunction(name: "frag") else {
            log.error("[METAL] Shader compilation failed")
            return
        }

        let desc               = MTLRenderPipelineDescriptor()
        desc.vertexFunction    = vertFn
        desc.fragmentFunction  = fragFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            log.info("[METAL] Render pipeline ready")
        } catch {
            log.error("[METAL] Pipeline error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // ── Frame mailbox ─────────────────────────────────────────────────────────
    func enqueueFrame(_ frame: EmulatorFrame) {
        frameLock.lock()
        pendingFrame = frame
        frameLock.unlock()
    }

    // ── MTLTexture creation / update ─────────────────────────────────────────
    private func ensureTexture(width: Int, height: Int, format: YDrivePixelFormat) {
        guard let device else { return }

        // Recreate only when dimensions or format change
        if texture != nil && texWidth == width && texHeight == height && texFormat == format { return }

        let texDesc              = MTLTextureDescriptor.texture2DDescriptor(
                                       pixelFormat: .bgra8Unorm,
                                       width: width,
                                       height: height,
                                       mipmapped: false)
        texDesc.usage            = [.shaderRead]
        texDesc.storageMode      = .shared
        texture                  = device.makeTexture(descriptor: texDesc)
        texWidth                 = width
        texHeight                = height
        texFormat                = format

        let needed = width * height
        if needed > stagingCapacity {
            stagingBuffer?.deallocate()
            stagingBuffer = UnsafeMutablePointer<UInt32>.allocate(capacity: needed)
            stagingCapacity = needed
        }

        log.info("[METAL] Texture created: \(width)x\(height)")
    }

    private func updateTexture(frame: EmulatorFrame) {
        guard let texture, let data = frame.data else { return }

        let w = frame.width, h = frame.height, pitch = frame.pitch

        switch frame.pixelFormat {

        case .xrgb8888:
            data.withUnsafeBytes { ptr in
                texture.replace(region: MTLRegionMake2D(0, 0, w, h),
                                mipmapLevel: 0,
                                withBytes: ptr.baseAddress!,
                                bytesPerRow: pitch)
            }

        case .rgb565:
            guard let dest = stagingBuffer else { return }
            data.withUnsafeBytes { src in
                let src16 = src.bindMemory(to: UInt16.self)
                for y in 0..<h {
                    let rowSrc = src16.baseAddress!.advanced(by: y * (pitch / 2))
                    let rowDst = dest.advanced(by: y * w)
                    for x in 0..<w {
                        let p  = rowSrc[x]
                        let r5 = UInt32((p >> 11) & 0x1F)
                        let g6 = UInt32((p >> 5)  & 0x3F)
                        let b5 = UInt32( p         & 0x1F)
                        let r8 = (r5 << 3) | (r5 >> 2)
                        let g8 = (g6 << 2) | (g6 >> 4)
                        let b8 = (b5 << 3) | (b5 >> 2)
                        rowDst[x] = 0xFF000000 | (r8 << 16) | (g8 << 8) | b8
                    }
                }
            }
            texture.replace(region: MTLRegionMake2D(0, 0, w, h),
                            mipmapLevel: 0,
                            withBytes: dest,
                            bytesPerRow: w * 4)

        case .trgb1555:
            guard let dest = stagingBuffer else { return }
            data.withUnsafeBytes { src in
                let src16 = src.bindMemory(to: UInt16.self)
                for y in 0..<h {
                    let rowSrc = src16.baseAddress!.advanced(by: y * (pitch / 2))
                    let rowDst = dest.advanced(by: y * w)
                    for x in 0..<w {
                        let p  = rowSrc[x]
                        let r5 = UInt32((p >> 10) & 0x1F)
                        let g5 = UInt32((p >> 5)  & 0x1F)
                        let b5 = UInt32( p         & 0x1F)
                        let r8 = (r5 << 3) | (r5 >> 2)
                        let g8 = (g5 << 3) | (g5 >> 2)
                        let b8 = (b5 << 3) | (b5 >> 2)
                        rowDst[x] = 0xFF000000 | (r8 << 16) | (g8 << 8) | b8
                    }
                }
            }
            texture.replace(region: MTLRegionMake2D(0, 0, w, h),
                            mipmapLevel: 0,
                            withBytes: dest,
                            bytesPerRow: w * 4)

        @unknown default:
            break
        }
    }

    // ── Aspect-correct quad vertices ─────────────────────────────────────────
    /// Returns NDC vertices for a centred letterboxed quad preserving `aspect`.
    private func aspectQuad(viewWidth: Float, viewHeight: Float, aspect: Float) -> [Float] {
        let viewAspect = viewWidth / viewHeight
        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        if viewAspect > aspect {
            // Pillarbox
            scaleX = aspect / viewAspect
        } else {
            // Letterbox
            scaleY = viewAspect / aspect
        }

        return [
            -scaleX,  scaleY,  0, 0,
             scaleX,  scaleY,  1, 0,
            -scaleX, -scaleY,  0, 1,
             scaleX, -scaleY,  1, 1,
        ]
    }

    // ── MTKViewDelegate ───────────────────────────────────────────────────────
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        log.debug("[METAL] Drawable size: \(size.width)x\(size.height)")
    }

    func draw(in view: MTKView) {
        // Consume pending frame
        frameLock.lock()
        let frame = pendingFrame
        pendingFrame = nil
        frameLock.unlock()

        if let frame {
            ensureTexture(width: frame.width, height: frame.height, format: frame.pixelFormat)
            updateTexture(frame: frame)
        }

        guard let texture,
              let drawable        = view.currentDrawable,
              let renderPassDesc  = view.currentRenderPassDescriptor,
              let commandBuffer   = commandQueue?.makeCommandBuffer(),
              let encoder         = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc),
              let pipelineState   else { return }

        // Upload aspect-correct quad
        let dw = Float(view.drawableSize.width)
        let dh = Float(view.drawableSize.height)
        // aspect from engine (fallback 4:3)
        let aspect: Float = texWidth > 0 && texHeight > 0
            ? Float(texWidth) / Float(texHeight)
            : (4.0 / 3.0)
        let verts = aspectQuad(viewWidth: dw, viewHeight: dh, aspect: aspect)
        vertexBuffer?.contents().copyMemory(from: verts,
                                            byteCount: verts.count * MemoryLayout<Float>.size)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        
        var mode = filterMode
        encoder.setFragmentBytes(&mode, length: MemoryLayout<Int32>.size, index: 1)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
