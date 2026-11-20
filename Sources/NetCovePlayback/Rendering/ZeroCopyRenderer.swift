//
//  ZeroCopyRenderer.swift
//  VideoToolbox 解出的 CVPixelBuffer 直接映射成 Metal 纹理（CVMetalTextureCache），
//  不经 CPU 拷贝 —— 这是把逐帧 replace(region:) 的 CPU 占用砍掉一个量级的关键。
//  作为 MetalVideoRenderer 的扩展实现，与软件解码路径共用同一套着色器。
//

import Foundation
import CoreVideo
import Metal
import MetalKit

extension MetalVideoRenderer {

    /// 预创建纹理缓存（一次性，之后每帧零拷贝）
    func prepareTextureCache() {
        guard textureCache == nil else { return }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device,
                                  nil, &cache)
        textureCache = cache
    }

    /// 零拷贝路径：CVPixelBuffer → 纹理 → 着色 → drawable
    func render(pixelBuffer: CVPixelBuffer,
                transfer: VideoFrameDescriptor.TransferFunction,
                dolbyVision: DolbyVisionInfo? = nil) {
        prepareTextureCache()
        guard let textureCache,
              let drawable = layer.nextDrawable() else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        let isTenBit = Self.isTenBit(pixelBuffer)

        var cvTextures: [CVMetalTexture] = []
        var textures: [MTLTexture] = []

        if planeCount >= 2 {
            // 双平面：Y + CbCr（NV12 / P010）
            let yFormat: MTLPixelFormat = isTenBit ? .r16Unorm : .r8Unorm
            let uvFormat: MTLPixelFormat = isTenBit ? .rg16Unorm : .rg8Unorm
            let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)

            if let y = makeTexture(textureCache, pixelBuffer, plane: 0,
                                   format: yFormat, width: width, height: height),
               let uv = makeTexture(textureCache, pixelBuffer, plane: 1,
                                    format: uvFormat, width: chromaWidth, height: chromaHeight) {
                cvTextures = [y.texture, uv.texture]
                textures = [y.metal, uv.metal]
            }
        } else {
            // 单平面 BGRA
            if let bgra = makeTexture(textureCache, pixelBuffer, plane: nil,
                                      format: .bgra8Unorm, width: width, height: height) {
                cvTextures = [bgra.texture]
                textures = [bgra.metal]
            }
        }

        guard !textures.isEmpty else { return }
        present(textures: textures, drawable: drawable,
                transfer: transfer, dolbyVision: dolbyVision)

        // CVMetalTexture 必须活到命令提交之后
        cvTextures.forEach { _ = $0 }
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    // MARK: - 内部

    private func makeTexture(_ cache: CVMetalTextureCache,
                             _ pixelBuffer: CVPixelBuffer,
                             plane: Int?,
                             format: MTLPixelFormat,
                             width: Int,
                             height: Int) -> (texture: CVMetalTexture, metal: MTLTexture)? {
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil, format,
            width, height, plane ?? 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture,
              let metal = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return (cvTexture, metal)
    }

    /// 与软件路径共用的绘制逻辑
    private func present(textures: [MTLTexture],
                         drawable: CAMetalDrawable,
                         transfer: VideoFrameDescriptor.TransferFunction,
                         dolbyVision: DolbyVisionInfo?) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        if let dolbyVision, dolbyVision.profile == .p5, let pipeline = dvPipelineState, textures.count >= 2 {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(textures[0], index: 0)
            encoder.setFragmentTexture(textures[1], index: 1)
            // 双平面时把 UV 同时喂给 Cb / Cr 槽（着色器按 .r/.g 取值）
            encoder.setFragmentTexture(textures[1], index: 2)
            var uniforms = DolbyVisionColorPipeline.uniforms(info: dolbyVision, targetNits: targetNitsValue)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DVUniforms>.stride, index: 0)
        } else if let pipeline = sdrPipelineState {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(textures[0], index: 0)
            encoder.setFragmentTexture(textures.count > 1 ? textures[1] : textures[0], index: 1)
            var uniforms = SDRUniforms(yuvToRGB: MetalVideoRenderer.bt709YUVToRGB,
                                       transfer: transfer == .hlg ? 1 : 0,
                                       hlgPeakNits: 1000)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SDRUniforms>.stride, index: 0)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    static func isTenBit(_ pixelBuffer: CVPixelBuffer) -> Bool {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return true
        default:
            return false
        }
    }
}
