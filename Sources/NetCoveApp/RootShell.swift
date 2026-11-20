//
//  RootShell.swift
//  顶层壳：环境切换 + 四个一级入口（发现 / 媒体库 / 详情 / 设置）。
//  对应原 App 的 Shell + Dock（GlassDockBarView / DockSegmentedControl）。
//

import SwiftUI

struct RootShell: View {
    @EnvironmentObject private var container: AppContainer
    @State private var tab: DockTab = .discover
    @State private var showLockGate = false

    var body: some View {
        TabView(selection: $tab) {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles.tv") }
                .tag(DockTab.discover)

            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(DockTab.library)

            WatchingView()
                .tabItem { Label("Watching", systemImage: "play.rectangle") }
                .tag(DockTab.watching)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(DockTab.settings)
        }
        .tint(DesignTokens.Accent.primary)
        .task { evaluateLock() }
        .onChange(of: container.currentEnvironment) { _, _ in evaluateLock() }
        .fullScreenCover(isPresented: $showLockGate) {
            LockGateView(environment: container.currentEnvironment,
                         lock: container.currentLock) {
                showLockGate = false
            }
        }
    }

    private func evaluateLock() {
        showLockGate = container.currentLock.state == .locked
    }
}

enum DockTab: Hashable {
    case discover, library, watching, settings
}
