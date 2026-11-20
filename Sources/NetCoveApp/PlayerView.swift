//
//  PlayerView.swift
//  播放器：外壳取容器依赖，内核持有 PlaybackSession。
//

import SwiftUI

struct PlayerView: View {
    let item: MediaItem
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        PlayerCore(item: item, router: container.playbackRouter, history: container.history)
    }
}

struct PlayerCore: View {
    let item: MediaItem
    @StateObject private var session: PlaybackSession
    @Environment(\.dismiss) private var dismiss
    @State private var subtitleMode: SubtitleMode = .off
    @State private var danmakuEnabled = false
    @State private var danmakuScheduler = DanmakuScheduler()
    @State private var activeDanmaku: [(comment: DanmakuComment, lane: Int)] = []
    @State private var danmakuRenderer: DanmakuMetalRenderer? = DanmakuMetalRenderer()
    @StateObject private var castController = CastController()
    @State private var showCastSheet = false
    @State private var aiCues: [SubtitleCue] = []
    @State private var aiState: String?
    @State private var aiTask: Task<Void, Never>?

    enum SubtitleMode: String { case off = "Off", ai = "Auto (AI)", embedded = "Embedded" }

    init(item: MediaItem, router: EngineRouter, history: WatchHistoryStore) {
        self.item = item
        _session = StateObject(wrappedValue: PlaybackSession(router: router, history: history))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 视频画面：AVPlayer 走图层，FFmpeg 走 Metal
            if let player = session.displayPlayer {
                PlayerLayerView(player: player).ignoresSafeArea()
            } else if let renderer = session.displayRenderer {
                MetalVideoView(renderer: renderer).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    statusView
                    if subtitleMode == .ai, let cue = currentCue {
                        Text(cue.text)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .offset(y: 120)
                    }

                    if danmakuEnabled {
                        if let danmakuRenderer {
                            DanmakuMetalView(renderer: danmakuRenderer, items: activeDanmaku)
                        } else {
                            DanmakuOverlay(items: activeDanmaku)
                        }
                    }
                }
                Spacer(minLength: 0)
                controls
            }
            .padding()
        }
        .task { await start() }
        .onChange(of: session.progress) { _, newValue in
            if danmakuEnabled {
                activeDanmaku = danmakuScheduler.active(at: newValue)
            }
        }
        .onChange(of: subtitleMode) { _, newValue in
            if newValue == .ai { startAISubtitles() }
        }
        .sheet(isPresented: $showCastSheet) {
            CastSheet(controller: castController, item: item)
        }
        .onDisappear { Task { await session.stop() } }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private var statusView: some View {
        VStack(spacing: 10) {
            switch session.state {
            case .idle:
                Image(systemName: "play.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.7))
            case .preparing:
                ProgressView().tint(.white)
                Text("Preparing…").foregroundStyle(.white)
            case .playing, .paused:
                if let probe = session.probe {
                    Text(badge(for: probe))
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                        .foregroundStyle(.white)
                }
            case .failed(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.title)
                    Text(message).font(.footnote).multilineTextAlignment(.center)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ProgressView(value: session.progress, total: 1)
                .tint(DesignTokens.Accent.primary)
            if let aiState {
                Text(aiState)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 24) {
                Button {
                    Task { await session.togglePause() }
                } label: {
                    Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Menu {
                    ForEach([SubtitleMode.off, .ai, .embedded], id: \.self) { mode in
                        Button(mode.rawValue) { subtitleMode = mode }
                    }
                } label: {
                    Image(systemName: "captions.bubble").font(.title2)
                }

                Button {
                    danmakuEnabled.toggle()
                } label: {
                    Image(systemName: danmakuEnabled ? "text.bubble.fill" : "text.bubble")
                        .font(.title2)
                }

                Button {
                    showCastSheet = true
                    Task { await castController.discover() }
                } label: {
                    Image(systemName: "airplayvideo").font(.title2)
                }
                Spacer()
                Button("Done") { dismiss() }.font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .padding()
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sheet))
    }

    private func badge(for probe: PlaybackProbe) -> String {
        if probe.hasDolbyVision { return "Dolby Vision P\(probe.doviProfile ?? 8)" }
        if probe.hasHDR { return "HDR" }
        if probe.isUltraHD { return "4K" }
        return "SDR"
    }

    /// 当前播放位置对应的 AI 字幕
    private var currentCue: SubtitleCue? {
        let time = session.progress
        return aiCues.first { time >= $0.start && time <= $0.end }
    }

    private func startAISubtitles() {
        guard aiCues.isEmpty, aiTask == nil else { return }
        guard let url = URL(string: item.sourceID), url.scheme != nil else {
            aiState = "No local media to transcribe."
            return
        }
        aiState = "Generating on-device subtitles…"
        aiTask = Task {
            defer { aiTask = nil }
            do {
                let service = AISubtitleService(backend: .system,
                                                language: Locale.current.language.languageCode?.identifier ?? "en")
                aiCues = try await service.transcribe(videoURL: url)
                aiState = aiCues.isEmpty ? "No speech detected." : nil
            } catch {
                aiState = error.localizedDescription
            }
        }
    }

    private func start() async {
        let resource = PlayableResource(
            itemID: item.id,
            url: URL(string: item.sourceID) ?? URL(fileURLWithPath: "/dev/null"),
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            width: 1920,
            height: 1080,
            frameRate: 23.976,
            bitrate: 8_000_000,
            hasHDR: false,
            hasDolbyVision: false,
            doviProfile: nil,
            hasCompleteMediaInfo: true,
            origin: .library
        )
        await session.start(resource, itemID: item.id)
    }
}

/// 投屏选择面板
struct CastSheet: View {
    @ObservedObject var controller: CastController
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("AirPlay") {
                    HStack {
                        Label("System route", systemImage: "airplayvideo")
                        Spacer()
                        AirPlayRouteButton().frame(width: 44, height: 44)
                    }
                }

                Section("DLNA") {
                    if controller.isDiscovering {
                        HStack { ProgressView(); Text("Searching…") }
                    }
                    ForEach(controller.targets) { target in
                        Button {
                            Task {
                                do {
                                    try await controller.cast(
                                        url: URL(string: item.sourceID) ?? URL(fileURLWithPath: "/"),
                                        title: item.title,
                                        to: target
                                    )
                                    dismiss()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        } label: {
                            Label(target.name, systemImage: "tv")
                        }
                    }
                    if controller.targets.isEmpty && !controller.isDiscovering {
                        Text("No DLNA renderer found on this network.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await controller.discover() }
                    } label: {
                        Label("Search again", systemImage: "arrow.clockwise")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Cast")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// AVPlayer 的视频输出层
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.backgroundColor = .black
        (view.layer as? AVPlayerLayer)?.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        (uiView.layer as? AVPlayerLayer)?.player = player
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    }
}
