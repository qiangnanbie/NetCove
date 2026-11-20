//
//  FeatureAccess.swift
//  NetCove 无付费墙：所有库、环境、格式、并发数全开。
//  （原 App 的 license/points/attestation 一层整体移除，保留本地偏好与统计。）
//

import Foundation

struct FeatureAccess {
    /// 库数量上限：nil = 不限
    let libraryLimit: Int? = nil
    /// 观看环境上限：nil = 不限
    let environmentLimit: Int? = nil
    /// 每日播放次数上限：nil = 不限
    let dailyPlaybackLimit: Int? = nil

    /// 是否允许某种播放格式（4K / DV / HDR / 120fps / 非 MP4 全部允许）
    func allowsPlayback(_ probe: PlaybackProbe) -> Bool { true }

    /// 需要提示的能力（不拦截，仅用于设置页展示）
    var capabilities: [String] {
        ["4K", "Dolby Vision P5/P8", "HDR10/HLG", "120 fps", "MKV/TS/AVI", "AV1",
         "PiP", "AirPlay", "外部显示器", "AI 字幕", "弹幕", "脚本模块"]
    }
}

/// 播放前的媒体探测结果（由解封装层填充）
struct PlaybackProbe {
    var width: Int = 0
    var height: Int = 0
    var frameRate: Double = 0
    var hasHDR: Bool = false
    var hasDolbyVision: Bool = false
    var doviProfile: Int?
    var isMP4Container: Bool = true
    var hasCompleteMediaInfo: Bool = true
    var origin: PlayableResource.Origin = .library

    var isUltraHD: Bool { width >= 3800 || height >= 2100 }
    var isHighFrameRate: Bool { frameRate >= 100 }
}
