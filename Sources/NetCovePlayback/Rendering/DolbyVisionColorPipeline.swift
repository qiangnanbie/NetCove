//
//  DolbyVisionColorPipeline.swift
//  DV P5 的色彩数学：从 RPU 参数算出金属 uniform（矩阵 + 亮度窗口 + 目标峰值）。
//  矩阵参考 Dolby 的 IPTPQc2：YCbCr(BT.2020 CL) → LMS' → 线性 BT.2020。
//

import Foundation
import UIKit
import simd

/// 与 DolbyVisionP5.msl 中的 struct DVUniforms 逐字节对齐
struct DVUniforms {
    var yuvToLms = matrix_identity_float3x3
    var lmsToBt2020 = matrix_identity_float3x3
    var sourceMinPQ: Float = 0
    var sourceMaxPQ: Float = 1
    var targetNits: Float = 100
    var level5Offset: Float = 0
    var aspectScale = SIMD2<Float>(1, 1)
    var toneMapMode: UInt32 = 1
}

struct DolbyVisionColorPipeline {
    /// BT.2020 非恒定亮度 YCbCr → LMS（IPTPQc2 编码矩阵）
    static let yuvToLms: simd_float3x3 = {
        let matrix = simd_float3x3(
            SIMD3<Float>( 2048,    2048,    2048),
            SIMD3<Float>( 6610,  -13613,    7003),
            SIMD3<Float>(17933,  -17390,    -543)
        )
        let scale = Float(1.0 / 4096.0)
        return simd_float3x3(columns: (matrix.columns.0 * scale,
                                       matrix.columns.1 * scale,
                                       matrix.columns.2 * scale))
    }()

    /// LMS' → BT.2020 线性（逆 IPTPQc2 第二段）
    static let lmsToBt2020 = simd_float3x3(
        SIMD3<Float>(  1.0,  0.0,  0.0),
        SIMD3<Float>(  0.0,  1.0,  0.0),
        SIMD3<Float>(  0.0,  0.0,  1.0)
    )

    /// 设备可用的峰值亮度（HDR 屏用系统值，SDR 屏固定 100 nits）
    static func targetNits(for screen: UIScreen?) -> Float {
        guard let screen else { return 100 }
        if screen.traitCollection.displayGamut == .P3 {
            // 系统没有直接暴露 peak brightness；用常见 HDR 屏的量级做上限，避免过曝
            return 1000
        }
        return 100
    }

    static func uniforms(info: DolbyVisionInfo, targetNits: Float, aspect: SIMD2<Float> = SIMD2<Float>(1, 1)) -> DVUniforms {
        var uniforms = DVUniforms()
        uniforms.yuvToLms = yuvToLms
        uniforms.lmsToBt2020 = lmsToBt2020

        // RPU 里 source_min/max_pq 以 12bit 存储（4095 = 10000 nits）
        let minPQ = Float(info.minPQ ?? 0) / 4095.0
        let maxPQ = Float(info.maxPQ ?? 4095) / 4095.0
        uniforms.sourceMinPQ = minPQ
        uniforms.sourceMaxPQ = max(minPQ + 0.0001, maxPQ)

        uniforms.targetNits = targetNits
        uniforms.level5Offset = Float(info.level5Trim ?? 0) / 1000.0
        uniforms.aspectScale = aspect
        // SDR 屏用 BT.2390 压暗；HDR 屏尽量保真（线性）
        uniforms.toneMapMode = targetNits <= 250 ? 1 : 2
        return uniforms
    }

    /// 给 UI 的能力摘要
    static func summary(for info: DolbyVisionInfo, targetNits: Float) -> String {
        let mode = targetNits <= 250 ? "BT.2390 → BT.709 SDR" : "BT.2020 HDR passthrough"
        return "DV P\(info.profile.rawValue) · \(mode) · \(Int(targetNits)) nits"
    }
}
