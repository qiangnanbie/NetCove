//
//  DanmakuMetalRenderer.swift
//  弹幕 Metal 渲染：一次 draw call 画完同屏所有弹幕（instanced quads + 文字图集）。
//  对比 SwiftUI 版：同屏 200+ 条时帧率差异明显，这是替换的理由。
//

import Foundation
import Metal
import SwiftUI
import UIKit
import simd

final class DanmakuMetalRenderer {

    /// 与 Danmaku.msl 的 DanmakuInstance 对齐（float2 ×4 + float4 = 48 bytes）
    struct Instance {
        var center: SIMD2<Float>
        var size: SIMD2<Float>
        var uvOrigin: SIMD2<Float>
        var uvSize: SIMD2<Float>
        var color: SIMD4<Float>
    }

    struct Layout {
        var fontSize: CGFloat = 22
        var laneHeight: CGFloat = 30
        var topInset: CGFloat = 60
        var scrollDuration: TimeInterval = 6
    }

    let layer: CAMetalLayer
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let atlas = DanmakuTextAtlas()
    private var pipeline: MTLRenderPipelineState?
    private var atlasTexture: MTLTexture?
    private var layout = Layout()
    private var instances: [Instance] = []

    init?(device: MTLDevice = MTLCreateSystemDefaultDevice()!) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        self.layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = false
        layer.framebufferOnly = true
        layer.contentsScale = UIScreen.main.scale
        buildPipeline()
    }

    func configure(_ layout: Layout) { self.layout = layout }

    private func buildPipeline() {
        guard let url = Bundle.main.url(forResource: "Danmaku", withExtension: "msl"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let library = try? device.makeLibrary(source: source, options: nil) else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "danmakuVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "danmakuFragment")
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = layer.pixelFormat
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - 每帧更新

    /// items 来自 DanmakuScheduler：comment + 轨道号
    func update(items: [(comment: DanmakuComment, lane: Int)], viewSize: CGSize) {
        instances.removeAll(keepingCapacity: true)
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        for item in items {
            guard let slot = atlas.slot(for: item.comment.text,
                                        fontSize: CGFloat(item.comment.fontSize)) else { continue }
            let pixelWidth = CGFloat(slot.pixelWidth)
            let pixelHeight = CGFloat(slot.pixelHeight)

            // 归一化：中心点在 +Y 向上的 NDC
            let centerX = 1.0 - (pixelWidth / viewSize.width) - 0.02
            let centerY = 1.0 - (2.0 * (layout.topInset + CGFloat(item.lane) * layout.laneHeight)
                                 + pixelHeight) / viewSize.height
            let color = UIColor(Color(hex: item.comment.colorHex))

            instances.append(Instance(
                center: SIMD2<Float>(Float(centerX), Float(centerY)),
                size: SIMD2<Float>(Float(2 * pixelWidth / viewSize.width),
                                   Float(2 * pixelHeight / viewSize.height)),
                uvOrigin: slot.uvOrigin,
                uvSize: slot.uvSize,
                color: SIMD4<Float>(Float(color.redComponent),
                                    Float(color.greenComponent),
                                    Float(color.blueComponent),
                                    1)
            ))
        }
    }

    func draw() {
        guard let pipeline, let drawable = layer.nextDrawable() else { return }
        uploadAtlasIfNeeded()
        guard let atlasTexture else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        if !instances.isEmpty {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(instances,
                                   length: MemoryLayout<Instance>.stride * instances.count,
                                   index: 0)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                   instanceCount: instances.count)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func uploadAtlasIfNeeded() {
        guard let image = atlas.snapshot() else { return }
        if atlasTexture == nil || atlas.hasChanges {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: atlas.width, height: atlas.height, mipmapped: false)
            descriptor.usage = [.shaderRead]
            atlasTexture = device.makeTexture(descriptor: descriptor)

            if let context = CGContext(
                data: nil, width: atlas.width, height: atlas.height, bitsPerComponent: 8,
                bytesPerRow: atlas.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: atlas.width, height: atlas.height))
                if let data = context.data, let texture = atlasTexture {
                    texture.replace(region: MTLRegionMake2D(0, 0, atlas.width, atlas.height),
                                    mipmapLevel: 0, withBytes: data,
                                    bytesPerRow: atlas.width * 4)
                }
            }
            atlas.markUploaded()
        }
    }
}

/// SwiftUI 容器：把弹幕层叠加在视频上
struct DanmakuMetalView: UIViewRepresentable {
    let renderer: DanmakuMetalRenderer
    let items: [(comment: DanmakuComment, lane: Int)]

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.layer.addSublayer(renderer.layer)
        view.renderer = renderer
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        renderer.layer.frame = uiView.bounds
        renderer.update(items: items, viewSize: uiView.bounds.size)
        renderer.draw()
    }

    final class HostView: UIView {
        weak var renderer: DanmakuMetalRenderer?
        override func layoutSubviews() {
            super.layoutSubviews()
            renderer?.layer.frame = bounds
        }
    }
}
