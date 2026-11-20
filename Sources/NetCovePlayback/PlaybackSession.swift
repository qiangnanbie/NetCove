//
//  PlaybackSession.swift
//  一次播放的生命周期（无付费墙）：探测 → 选引擎 → 预取 → 播放 → 记录进度。
//

import Foundation
import AVFoundation

@MainActor
final class PlaybackSession: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case playing
        case paused
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var probe: PlaybackProbe?
    @Published private(set) var progress: Double = 0
    @Published private(set) var displayPlayer: AVPlayer?
    @Published private(set) var displayRenderer: MetalVideoRenderer?

    private let router: EngineRouter
    private let history: WatchHistoryStore
    private var engine: (any PlaybackEngine)?
    private var itemID: UUID?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?

    init(router: EngineRouter, history: WatchHistoryStore) {
        self.router = router
        self.history = history
    }

    func start(_ resource: PlayableResource, itemID: UUID) async {
        state = .preparing
        self.itemID = itemID
        do {
            let probed = PlaybackProbe(width: resource.width,
                                       height: resource.height,
                                       frameRate: resource.frameRate,
                                       hasHDR: resource.hasHDR,
                                       hasDolbyVision: resource.hasDolbyVision,
                                       doviProfile: resource.doviProfile,
                                       isMP4Container: resource.container.lowercased() == "mp4",
                                       hasCompleteMediaInfo: resource.hasCompleteMediaInfo,
                                       origin: resource.origin)
            probe = probed

            let engine = try router.engine(for: probed)
            self.engine = engine
            try await engine.prepare(url: resource.url, probe: probed)
            displayPlayer = engine.playerForDisplay
            displayRenderer = (engine as? MetalRendererProviding)?.metalRenderer
            await engine.play()
            startedAt = Date()
            state = .playing
            startTicker()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func togglePause() async {
        guard let engine else { return }
        switch state {
        case .playing:
            await engine.pause()
            state = .paused
        case .paused:
            await engine.play()
            state = .playing
        default:
            break
        }
    }

    func stop() async {
        ticker?.cancel()
        ticker = nil
        await engine?.stop()
        engine = nil
        if let itemID, let startedAt {
            let watched = Date().timeIntervalSince(startedAt)
            await history.record(itemID: itemID, position: progress, duration: max(watched, 1))
        }
        state = .idle
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let engine = self.engine else { return }
                self.progress = await engine.progress()
            }
        }
    }
}
