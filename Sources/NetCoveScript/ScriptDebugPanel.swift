//
//  ScriptDebugPanel.swift
//  模块调试面板：已装模块、装载状态、日志、安装 / 卸载 / 重载。
//

import SwiftUI
import UniformTypeIdentifiers

struct ScriptDebugPanel: View {
    @StateObject private var repository = RexModRepository()
    @StateObject private var log = ScriptDebugLogStore()
    @State private var runtime: ScriptRuntime?
    @State private var showImporter = false
    @State private var errorMessage: String?
    @State private var probeResult: String?

    private let policy = ScriptSandboxPolicy(allowedHosts: ["api.netcove.app", "image.tmdb.org"],
                                             maxRequestsPerMinute: 30,
                                             requestTimeout: 12,
                                             maxResponseBytes: 4 * 1024 * 1024)

    var body: some View {
        List {
            Section("Installed modules") {
                if repository.installed.isEmpty {
                    Text("No modules installed. Import a .rexmod package to get started.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(repository.installed, id: \.id) { manifest in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(manifest.name).font(DesignTokens.Typography.body.weight(.semibold))
                            Spacer()
                            Text(manifest.version)
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(manifest.id)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                        Text(manifest.capabilities.map(\.rawValue).joined(separator: " · "))
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(DesignTokens.Accent.secondary)
                        HStack(spacing: 12) {
                            Button("Load") { load(manifest) }
                                .buttonStyle(.bordered)
                            Button("Probe onDiscover") { probe(manifest) }
                                .buttonStyle(.bordered)
                            Button("Uninstall", role: .destructive) {
                                repository.uninstall(manifest)
                                runtime?.unload()
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(DesignTokens.Typography.caption)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Runtime") {
                switch runtime?.state {
                case .ready(let id): LabeledContent("State", value: "ready · \(id)")
                case .loading(let id): LabeledContent("State", value: "loading · \(id)")
                case .failed(let message): LabeledContent("State", value: "failed: \(message)")
                default: LabeledContent("State", value: "idle")
                }
                if let probeResult {
                    Text(probeResult)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sandbox") {
                LabeledContent("Allowed hosts", value: policy.allowedHosts.sorted().joined(separator: ", "))
                LabeledContent("Rate limit", value: "\(policy.maxRequestsPerMinute)/min")
                LabeledContent("Max response", value: "\(policy.maxResponseBytes / 1024) KB")
            }

            Section("Log") {
                if log.lines.isEmpty {
                    Text("No output yet.").font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Button("Clear log") { log.clear() }
                    .font(DesignTokens.Typography.caption)
            }
        }
        .navigationTitle("Script Modules")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "rexmod") ?? .data],
                      allowsMultipleSelection: false) { result in
            install(result)
        }
        .alert("Module error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 动作

    private func install(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let manifest = try repository.install(fileURL: url)
            log.append("installed \(manifest.id) \(manifest.version)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ manifest: RexModManifest) {
        let bridge = ScriptHostBridge(policy: policy, log: log)
        let runtime = ScriptRuntime(namespace: manifest.id, bridge: bridge, policy: policy, log: log)
        runtime.load(module: manifest, directory: repository.moduleDirectory(for: manifest.id))
        self.runtime = runtime
    }

    private func probe(_ manifest: RexModManifest) {
        if runtime == nil { load(manifest) }
        guard let runtime else { return }
        Task {
            do {
                let value = try await runtime.call("onDiscover",
                                                   argument: ["libraryName": "Probe Library"])
                let items = (value as? [[String: Any]])?.count ?? 0
                probeResult = "onDiscover returned \(items) item(s)"
                log.append("probe \(manifest.id): \(items) item(s)")
            } catch {
                probeResult = "probe failed: \(error.localizedDescription)"
            }
        }
    }
}
