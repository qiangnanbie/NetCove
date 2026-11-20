//
//  MetalVideoRenderer.swift
//  FFmpeg 解码帧的 Metal 渲染：DV P5 走 DolbyVisionP5.msl，其余走 SDRVideo.msl。
//  说明：这里用 replace(region:) 把帧拷进纹理（可跑、好读）。
//  生产优化方向：VideoToolbox 输出 CVPixelBuffer → CVMetalTextureCache 零拷贝。
//

import Foundation
import Metal
import MetalKit
import UIKit
import simd

final class MetalVideoRenderer: NSObject, VideoFrameRenderer {

    enum Path {
        case dolbyVisionP5
        case standard
    }

    let layer: CAMetalLayer
    let device: MTLDevice
    let queue: MTLCommandQueue
    var textureCache: CVMetalTextureCache?
    private var dvPipeline: MTLRenderPipelineState?
    private var sdrPipeline: MTLRenderPipelineState?
    private var path: Path = .standard
    private var probe: PlaybackProbe?
    var targetNits: Float = 100

    /// 供零拷贝扩展访问
    var dvPipelineState: MTLRenderPipelineState? { dvPipeline }
    var sdrPipelineState: MTLRenderPipelineState? { sdrPipeline }
    var targetNitsValue: Float { targetNits }

    private var planes: [MTLTexture] = []
    private var textureSize = (width: 0, height: 0)

    init?(device: MTLDevice = MTLCreateSystemDefaultDevice()!) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.layer = CAMetalLayer()
        super.init()

        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.contentsScale = UIScreen.main.scale
        targetNits = DolbyVisionColorPipeline.targetNits(for: UIScreen.main)
    }

    // MARK: - 准备

    func prepare(probe: PlaybackProbe) throws {
        self.probe = probe
        let wantsDV = probe.hasDolbyVision && (probe.doviProfile ?? 8) == 5
        path = wantsDV ? .dolbyVisionP5 : .standard

        if wantsDV, dvPipeline == nil {
            let info = DolbyVisionInfo(profile: .p5, level: probe.doviProfile,
                                       hasRPU: true, nits: nil)
            dvPipeline = try makePipeline(shader: "DolbyVisionP5",
                                          vertex: "dvVertex",
                                          fragment: "dvFragment",
                                          colorInfo: info)
        }
        if !wantsDV, sdrPipeline == nil {
            sdrPipeline = try makePipeline(shader: "SDRVideo",
                                           vertex: "sdrVertex",
                                           fragment: "sdrFragment",
                                           colorInfo: nil)
        }
    }

    private func makePipeline(shader: String, vertex: String, fragment: String,
                              colorInfo: DolbyVisionInfo?) throws -> MTLRenderPipelineState {
        guard let url = Bundle.main.url(forResource: shader, withExtension: "msl"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw RenderError.pipelineCompilation("\(shader).msl not found in bundle resources")
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw RenderError.pipelineCompilation("\(shader): \(error.localizedDescription)")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = layer.pixelFormat
        _ = colorInfo
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RenderError.pipelineCompilation(error.localizedDescription)
        }
    }

    // MARK: - 渲染

    func render(_ frame: VideoFrameDescriptor) {
        guard let drawable = layer.nextDrawable() else { return }
        upload(frame)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        switch path {
        case .dolbyVisionP5:
            guard let pipeline = dvPipeline, planes.count >= 3 else {
                encoder.endEncoding()
                commandBuffer.commit()
                return
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(planes[0], index: 0)
            encoder.setFragmentTexture(planes[1], index: 1)
            encoder.setFragmentTexture(planes[2], index: 2)
            var uniforms = DolbyVisionColorPipeline.uniforms(
                info: frame.dolbyVision ?? DolbyVisionInfo(profile: .p5, level: 5,
                                                           hasRPU: true, nits: nil),
                targetNits: targetNits
            )
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DVUniforms>.stride, index: 0)

        case .standard:
            guard let pipeline = sdrPipeline, planes.count >= 2 else {
                encoder.endEncoding()
                commandBuffer.commit()
                return
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(planes[0], index: 0)
            encoder.setFragmentTexture(planes[1], index: 1)
            var uniforms = SDRUniforms(yuvToRGB: Self.bt709YUVToRGB,
                                       transfer: frame.transfer == .hlg ? 1 : 0,
                                       hlgPeakNits: 1000,
                                       unused0: 0,
                                       unused1: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SDRUniforms>.stride, index: 0)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func flush() {
        planes.forEach { $0.setPurgeableState(.empty) }
        planes.removeAll()
    }

    // MARK: - 纹理上传

    private func upload(_ frame: VideoFrameDescriptor) {
        if textureSize.width != frame.width || textureSize.height != frame.height {
            planes.forEach { $0.setPurgeableState(.empty) }
            planes.removeAll()
            textureSize = (frame.width, frame.height)
            planes = makeTextures(for: frame)
        }

        for (index, texture) in planes.enumerated() {
            guard index < frame.planes.count, let base = frame.planes[index] else { continue }
            // 行长直接用解码器给的 linesize，避免不同像素格式各写一套算法
            let stride = index < frame.strides.count ? frame.strides[index] : texture.width * 4
            texture.replace(region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                            mipmapLevel: 0,
                            withBytes: base,
                            bytesPerRow: max(stride, 1))
        }
    }

    private func makeTextures(for frame: VideoFrameDescriptor) -> [MTLTexture] {
        func make(_ format: MTLPixelFormat, _ width: Int, _ height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: max(width, 1), height: max(height, 1), mipmapped: false)
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .managed
            return device.makeTexture(descriptor: descriptor)
        }

        let chromaWidth = frame.width / 2
        let chromaHeight = frame.height / 2

        switch frame.pixelFormat {
        case .bgra:
            return [make(.bgra8Unorm, frame.width, frame.height)].compactMap { $0 }

        case .nv12:
            // 平面 1 是交织 UV → rg8Unorm，着色器取 .rg
            return [make(.r8Unorm, frame.width, frame.height),
                    make(.rg8Unorm, chromaWidth, chromaHeight)].compactMap { $0 }

        case .p010:
            // 10bit 双平面：Y 用 r16Unorm，UV 交织用 rg16Unorm
            return [make(.r16Unorm, frame.width, frame.height),
                    make(.rg16Unorm, chromaWidth, chromaHeight)].compactMap { $0 }

        case .yuv420p10:
            return [make(.r16Unorm, frame.width, frame.height),
                    make(.r16Unorm, chromaWidth, chromaHeight),
                    make(.r16Unorm, chromaWidth, chromaHeight)].compactMap { $0 }
        }
    }

    static let bt709YUVToRGB = simd_float3x3(
        SIMD3<Float>(1.0, 1.0, 1.0),
        SIMD3<Float>(0.0, -0.1873, 1.8556),
        SIMD3<Float>(1.5748, -0.4681, 0.0)
    )
}

/// SDR 着色器的 uniform（与 SDRVideo.msl 对齐）
struct SDRUniforms {
    var yuvToRGB = simd_float3x3(1)
    var transfer: Float = 0
    var hlgPeakNits: Float = 1000
    var unused0: Float = 0
    var unused1: Float = 0
}

/// 把 Metal 的 CAMetalLayer 塞进 SwiftUI
struct MetalVideoView: UIViewRepresentable {
    let renderer: MetalVideoRenderer

    func makeUIView(context: Context) -> MetalHostView {
        let view = MetalHostView()
        view.layer.addSublayer(renderer.layer)
        view.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MetalHostView, context: Context) {
        renderer.layer.frame = uiView.bounds
    }

    final class MetalHostView: UIView {
        weak var renderer: MetalVideoRenderer?
        override func layoutSubviews() {
            super.layoutSubviews()
            renderer?.layer.frame = bounds
        }
    }
}
