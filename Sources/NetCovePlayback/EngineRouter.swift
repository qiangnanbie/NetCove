//
//  EngineRouter.swift
//  双引擎分流：能走系统解码就走 AVPlayer（省电、支持 AirPlay/PiP），
//  否则走 FFmpeg + libplacebo（MKV/TS/AVI、DV、缺系统解码器的编码）。
//

import Foundation

enum EngineKind: String {
    case avPlayer
    case ffmpeg
}

final class EngineRouter {
    var preferences = EnginePreferences.default

    /// 系统 AVPlayer 能可靠处理的容器/编码
    private let systemContainers: Set<String> = ["mp4", "m4v", "mov"]
    private let systemVideoCodecs: Set<String> = ["h264", "hevc", "av1"]

    func decide(for probe: PlaybackProbe, container: String = "mp4", codec: String? = nil) -> EngineKind {
        let normalizedContainer = container.lowercased()
        let normalizedCodec = (codec ?? "h264").lowercased()

        if !systemContainers.contains(normalizedContainer) { return .ffmpeg }
        if !systemVideoCodecs.contains(normalizedCodec) { return .ffmpeg }
        if probe.hasDolbyVision, (probe.doviProfile ?? 0) == 5 { return .ffmpeg } // P5 无回退层
        if probe.isHighFrameRate { return .ffmpeg }
        if !probe.hasCompleteMediaInfo { return .ffmpeg }
        return .avPlayer
    }

    func engine(for probe: PlaybackProbe, container: String = "mp4", codec: String? = nil) throws -> any PlaybackEngine {
        switch decide(for: probe, container: container, codec: codec) {
        case .avPlayer:
            let engine = AVPlaybackEngine()
            engine.preferences = preferences
            return engine
        case .ffmpeg:
            #if canImport(Libavformat)
            let engine = try FFmpegPlaybackEngine()
            engine.preferences = preferences
            return engine
            #else
            throw EngineRouterError.ffmpegUnavailable
            #endif
        }
    }
}

enum EngineRouterError: LocalizedError {
    case ffmpegUnavailable

    var errorDescription: String? {
        switch self {
        case .ffmpegUnavailable:
            return "This file needs the FFmpeg engine, which isn't linked into this build."
        }
    }
}
