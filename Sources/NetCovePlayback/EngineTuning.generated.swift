//
//  EngineTuning.generated.swift
//  由 tools/tuning_matrix.py 依据实测矩阵生成，请勿手改。
//  来源：results.sample.csv（149 条记录）
//  ⚠️ 本文件由示例数据生成，仅用于演示回填链路；请在真机上跑完 spec/tuning/matrix.csv 后用真实结果重新生成。
//

import Foundation

extension EnginePreferences {
    /// 实测回填：起播 P95 1380 ms · 平均掉帧 1.0 · 硬解率 17% · 功耗 P95 2340 mW
    static var tuned: EnginePreferences {
        var preferences = EnginePreferences.default
        preferences.prewarmEngine = true
        preferences.targetByteCount = 8 * 1024 * 1024
        preferences.maximumTargetByteCount = 32 * 1024 * 1024
        preferences.playbackCacheByteLimit = 256 * 1024 * 1024
        return preferences
    }

    /// 未达成判定线的用例数：0
    static var tuningSummary: String {
        "P95 起播 1380 ms · 掉帧 1.0 · 硬解 17% · 失败用例 0"
    }
}
