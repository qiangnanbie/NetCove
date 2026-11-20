//
//  SettingsView.swift
//  设置：环境、播放、字幕、能力清单、关于。无付费相关项。
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var asr = ASRModelManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("Status",
                                   value: container.auth.isSignedIn ? "Signed in" : "Local only")
                }

                Section("Environments") {
                    NavigationLink("Manage Environments") {
                        EnvironmentManagerView()
                    }
                    ForEach(container.environments) { environment in
                        Button {
                            container.select(environment: environment)
                        } label: {
                            HStack {
                                Text(environment.name)
                                Spacer()
                                if environment.id == container.currentEnvironment.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Sync") {
                    Toggle("iCloud sync", isOn: Binding(
                        get: { container.sync.isEnabled },
                        set: { newValue in
                            container.sync.isEnabled = newValue
                            if newValue { container.sync.startPeriodicSync() }
                        }
                    ))
                    if case .running(let step) = container.sync.state {
                        LabeledContent("Status", value: step)
                    }
                    Button("Sync now") {
                        Task { await container.sync.syncNow() }
                    }
                }

                Section("Playback") {
                    LabeledContent("Engines", value: "AVPlayer + FFmpeg")
                    LabeledContent("Formats", value: "4K · DV · HDR · 120fps")
                    LabeledContent("Hardware decode", value: "VideoToolbox (zero-copy)")
                    Toggle("Use measured tuning", isOn: Binding(
                        get: { container.useTunedPreferences },
                        set: { container.useTunedPreferences = $0 }
                    ))
                    Text(EnginePreferences.tuningSummary)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Subtitles") {
                    LabeledContent("Text formats", value: "SRT · ASS · VTT")
                    LabeledContent("Bitmap", value: "PGS · VobSub")
                    LabeledContent("AI subtitles", value: "On-device")
                }

                Section("AI subtitles") {
                    ForEach(ASRModelManager.catalog) { descriptor in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(descriptor.name)
                                Spacer()
                                if asr.isInstalled(descriptor.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(DesignTokens.Accent.primary)
                                }
                            }
                            Text("\(descriptor.languages.joined(separator: "/")) · ~\(descriptor.approxSizeMB) MB · \(descriptor.engine)")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                if asr.isInstalled(descriptor.id) {
                                    Button("Remove", role: .destructive) {
                                        asr.uninstall(descriptor.id)
                                    }
                                    .buttonStyle(.borderless)
                                } else {
                                    Button("Download") {
                                        Task { await asr.install(descriptor) }
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .font(DesignTokens.Typography.caption)
                        }
                    }

                    switch asr.state {
                    case .downloading(let id, let progress, let file):
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Downloading \(id) · \(Int(progress * 100))%")
                                .font(DesignTokens.Typography.caption)
                            ProgressView(value: progress)
                            Text(file).font(DesignTokens.Typography.caption).foregroundStyle(.secondary)
                        }
                    case .verifying(let id):
                        Text("Verifying \(id)…").font(DesignTokens.Typography.caption)
                    case .failed(let id, let message):
                        Text("\(id): \(message)")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.red)
                    default:
                        EmptyView()
                    }
                }

                Section("Modules") {
                    NavigationLink("Script Modules") {
                        ScriptDebugPanel()
                    }
                }

                Section("Capabilities") {
                    ForEach(container.features.capabilities, id: \.self) { capability in
                        Label(capability, systemImage: "checkmark.circle")
                            .font(DesignTokens.Typography.body)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "-")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
