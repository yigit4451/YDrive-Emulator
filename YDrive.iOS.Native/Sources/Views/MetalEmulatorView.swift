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
//  The view observes LibretroEmulatorEngine.currentFrame and blits each
//  new EmulatorFrame into an MTLTexture via replaceRegion.
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

    func makeCoordinator() -> MetalCoordinator {
        MetalCoordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device          = MTLCreateSystemDefaultDevice()
        view.delegate        = context.coordinator
        view.enableSetNeedsDisplay = false        // driven by frame timer, not display link
        view.isPaused        = false
        view.preferredFramesPerSecond = 60
        view.clearColor      = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm      // fallback; coordinator may override
        view.framebufferOnly = false

        context.coordinator.mtkView = view
        context.coordinator.setup(device: view.device)
        log.info("[METAL] MTKView created, device: \(view.device?.name ?? "nil", privacy: .public)")
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if let frame = engine.currentFrame {
            context.coordinator.enqueueFrame(frame)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
final class MetalCoordinator: NSObject, MTKViewDelegate {

    weak var mtkView: MTKView?

    // Metal objects
    private var device:          MTLDevice?
    private var commandQueue:    MTLCommandQueue?
    private var pipelineState:   MTLRenderPipelineState?
    private var texture:         MTLTexture?
    private var samplerState:    MTLSamplerState?
    private var vertexBuffer:    MTLBuffer?

    // Pending frame from emulation queue (lock-free single-slot mailbox)
    private var pendingFrame:    EmulatorFrame?
    private let frameLock        = NSLock()

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

        fragment float4 frag(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler smp          [[sampler(0)]]) {
            return tex.sample(smp, in.uv);
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

        let metalFormat: MTLPixelFormat
        switch format {
        case .xrgb8888: metalFormat = .bgra8Unorm
        case .rgb565:   metalFormat = .b5g6r5Unorm
        case .trgb1555: metalFormat = .bgr5A1Unorm
        @unknown default: metalFormat = .bgra8Unorm
        }

        // Update the MTKView pixel format to match (bgra8Unorm covers all cases after conversion)
        // We blit into bgra8Unorm always for simplicity; format conversion is in updateTexture.
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

        log.info("[METAL] Texture created: \(width)x\(height) fmt=\(metalFormat.rawValue)")
        _ = metalFormat // suppress unused warning
    }

    private func updateTexture(frame: EmulatorFrame) {
        guard let texture, let data = frame.data else { return }

        let w = frame.width, h = frame.height, pitch = frame.pitch

        // For BGRA8 / XRGB8888 we can blit directly; for 16-bit we convert to 32-bit.
        switch frame.pixelFormat {

        case .xrgb8888:
            // libretro XRGB8888 is actually stored as BGRA on little-endian — blit directly.
            data.withUnsafeBytes { ptr in
                texture.replace(region: MTLRegionMake2D(0, 0, w, h),
                                mipmapLevel: 0,
                                withBytes: ptr.baseAddress!,
                                bytesPerRow: pitch)
            }

        case .rgb565:
            // Convert RGB565 → BGRA8 row by row
            let dest = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
            defer { dest.deallocate() }
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
                        // Expand to 8 bits
                        let r8 = (r5 << 3) | (r5 >> 2)
                        let g8 = (g6 << 2) | (g6 >> 4)
                        let b8 = (b5 << 3) | (b5 >> 2)
                        // Pack as BGRA (Metal .bgra8Unorm)
                        rowDst[x] = 0xFF000000 | (r8 << 16) | (g8 << 8) | b8
                    }
                }
            }
            texture.replace(region: MTLRegionMake2D(0, 0, w, h),
                            mipmapLevel: 0,
                            withBytes: dest,
                            bytesPerRow: w * 4)

        case .trgb1555:
            // Convert 0RGB1555 → BGRA8
            let dest = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
            defer { dest.deallocate() }
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
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
