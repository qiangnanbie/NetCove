//
//  DolbyVision.swift
//  Dolby Vision 支持：profile 识别、RPU 解析、输出色彩决策。
//  P5 无回退层必须按 IPTPQc2 解；P8 有 HDR10/HLG 回退层可降级。
//

import Foundation

enum DolbyVisionProfile: Int {
    case p5 = 5
    case p7 = 7
    case p8 = 8

    var hasFallbackLayer: Bool {
        switch self {
        case .p5: return false
        case .p7, .p8: return true
        }
    }

    /// 输出应采用的传递函数
    var transferFunction: String {
        switch self {
        case .p5: return "PQ (SMPTE ST 2084) + IPTPQc2 色域"
        case .p7: return "PQ + 回退层（BL 为 HDR10）"
        case .p8: return "PQ + 回退层（BL 为 HDR10 或 HLG）"
        }
    }
}

struct DolbyVisionInfo: Equatable {
    var profile: DolbyVisionProfile
    var level: Int?
    var hasRPU: Bool
    var nits: Int?
    /// RPU source_min_pq（12bit，4095 = 10000 nits）
    var minPQ: Int? = nil
    /// RPU source_max_pq（12bit）
    var maxPQ: Int? = nil
    /// RPU level5 左右/上下裁剪（归一化 ×1000）
    var level5Trim: Int? = nil
}

enum DolbyVisionDetector {

    /// 从容器/码流元数据推断 profile。
    /// 优先顺序：AV1 Dolby Vision config → HEVC SEI(NAL 39) → 容器标签（dvh1/dvhe/dvav）
    static func detect(containerTags: [String], hevcSEIMessages: [Data] = []) -> DolbyVisionInfo? {
        let lower = containerTags.map { $0.lowercased() }
        if lower.contains("dvh1") || lower.contains("dvhe") {
            let profile = hevcSEIMessages.compactMap { rpuProfile(in: $0) }.first ?? .p8
            return DolbyVisionInfo(profile: profile, level: nil, hasRPU: !hevcSEIMessages.isEmpty, nits: nil)
        }
        if lower.contains("dvav") {
            return DolbyVisionInfo(profile: .p8, level: nil, hasRPU: true, nits: nil)
        }
        return nil
    }

    /// 解析 NAL unit（SEI，type 39 / unspec 62）里的 RPU：取 dovi_config 的 dv_profile 字段
    static func rpuProfile(in nal: Data) -> DolbyVisionProfile? {
        // RPU 头：rpu_type(6) rpu_format(11) vdr_rpu_profile(4)
        let bytes = [UInt8](nal)
        guard bytes.count > 6 else { return nil }
        let bitField = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])
        let vdrProfile = (bitField >> 4) & 0x0F
        switch Int(vdrProfile) {
        case 5: return .p5
        case 7: return .p7
        case 8: return .p8
        default: return nil
        }
    }

    /// 播放决策：P5 必须软解 + 自定义着色器；P7/P8 可走系统 tone mapping
    static func requiresSoftwarePipeline(_ info: DolbyVisionInfo) -> Bool {
        info.profile == .p5
    }
}
