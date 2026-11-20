//
//  PlaybackEngine.swift
//  引擎协议 + AVPlayer 实现。FFmpeg 路径见 FFmpegPlaybackEngine.swift。
//

import Foundation
import AVFoundation
import Combine

protocol PlaybackEngine: AnyObject {
    var preferences: EnginePreferences { get set }
    /// AVPlayer 路径用于挂 AVPlayerLayer
    var playerForDisplay: AVPlayer? { get }
    func prepare(url: URL, probe: PlaybackProbe) async throws
    func play() async
    func pause() async
    func seek(to seconds: Double) async
    func stop() async
    func progress() async -> Double
}

extension PlaybackEngine {
    var playerForDisplay: AVPlayer? { nil }
}

/// 引擎预热与缓冲策略（字段名与原 App 对齐，取值需按真机矩阵实测）
struct EnginePreferences: Codable, Equatable {
    var prewarmEngine = true
    var prewarmDanmakuPrefetch = true
    var prewarmSkipAnalyzer = true

    var noCreditsTriggerFraction = 0.92
    var creditsLeadTime: TimeInterval = 3
    var endGuard: TimeInterval = 12

    var targetByteCount = 8 * 1024 * 1024
    var maximumTargetByteCount = 32 * 1024 * 1024
    var playbackCacheByteLimit = 256 * 1024 * 1024
    var minimumAdoptionProgress = 0.35
    var maximumPreparedAge: TimeInterval = 30
    var resourceExpirationSafetyInterval: TimeInterval = 20

    static let `default` = EnginePreferences()
}

// MARK: - AVPlayer 路径

final class AVPlaybackEngine: PlaybackEngine {
    var preferences = EnginePreferences.default
    var playerForDisplay: AVPlayer? { player }

    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var currentTime: Double = 0

    deinit {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
    }

    func prepare(url: URL, probe: PlaybackProbe) async throws {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        _ = try await asset.load(.tracks)

        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration =
            Double(preferences.targetByteCount) / 1_000_000
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        self.item = item

        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player
        observeTime(player)

        // HDR / DV：AVPlayer 会自动按显示器能力选择 tone mapping，
        // 但 DV P5 需要容器里带正确的色彩标签，否则会偏色。
        _ = probe
    }

    func play() async { player?.play() }
    func pause() async { player?.pause() }

    func seek(to seconds: Double) async {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        await player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() async {
        player?.pause()
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player = nil
        item = nil
        currentTime = 0
    }

    func progress() async -> Double { currentTime }

    private func observeTime(_ player: AVPlayer) {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
}
