//
//  DanmakuTextAtlas.swift
//  弹幕文字图集：CoreText 把每段文字画进位图，按行打包进一张纹理。
//  同一条文案只做一次，命中缓存后直接取 uv。
//

import Foundation
import CoreText
import CoreGraphics
import UIKit

struct AtlasSlot {
    var uvOrigin: SIMD2<Float>
    var uvSize: SIMD2<Float>
    var pixelWidth: Int
    var pixelHeight: Int
}

final class DanmakuTextAtlas {
    private(set) var bitmap: CGContext
    let width: Int
    let height: Int
    private var cursorX = 1
    private var cursorY = 1
    private var rowHeight = 0
    private var cache: [String: AtlasSlot] = [:]
    private var dirty = true

    /// 图集尺寸：2048×2048 在 iPad 上足够放几百条常见弹幕
    init(width: Int = 2048, height: Int = 2048) {
        self.width = width
        self.height = height
        self.bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        bitmap.setFillColor(UIColor.clear.cgColor)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    var hasChanges: Bool { dirty }
    func markUploaded() { dirty = false }

    /// 把文字画进图集（白字黑描边由渲染时叠加阴影实现），返回 uv
    func slot(for text: String, fontSize: CGFloat) -> AtlasSlot? {
        let key = "\(Int(fontSize))|\(text)"
        if let cached = cache[key] { return cached }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let pad: CGFloat = 2
        let pixelWidth = Int(ceil(bounds.width + pad * 2))
        let pixelHeight = Int(ceil(bounds.height + pad * 2))
        guard pixelWidth < width - 2, pixelHeight < height - 2 else { return nil }

        if cursorX + pixelWidth + 1 >= width {
            cursorX = 1
            cursorY += rowHeight + 1
            rowHeight = 0
        }
        guard cursorY + pixelHeight + 1 < height else { return nil }

        // CoreText 原点在左下，图集按左上排版 → 翻转
        bitmap.saveGState()
        bitmap.textMatrix = .identity
        bitmap.translateBy(x: CGFloat(cursorX) + pad,
                           y: CGFloat(height - cursorY - pixelHeight) + pad)
        CTLineDraw(line, bitmap)
        bitmap.restoreGState()

        let slot = AtlasSlot(
            uvOrigin: SIMD2<Float>(Float(cursorX) / Float(width),
                                   Float(cursorY) / Float(height)),
            uvSize: SIMD2<Float>(Float(pixelWidth) / Float(width),
                                 Float(pixelHeight) / Float(height)),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )

        cursorX += pixelWidth + 1
        rowHeight = max(rowHeight, pixelHeight)
        cache[key] = slot
        dirty = true
        return slot
    }

    func snapshot() -> CGImage? { bitmap.makeImage() }
}
