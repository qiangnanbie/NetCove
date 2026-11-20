//
//  LibraryView.swift
//  媒体库：列表、新增（无数量限制）、扫描、删除。
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var showAdd = false
    @State private var scanning: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Libraries") {
                    ForEach(container.libraries) { library in
                        LibraryRow(library: library, isScanning: scanning == library.id) {
                            Task { await scan(library) }
                        }
                    }
                    .onDelete { indexSet in
                        let targets = indexSet.map { container.libraries[$0] }
                        Task { for target in targets { await container.remove(target) } }
                    }

                    if container.libraries.isEmpty {
                        Text("No libraries yet. Add Jellyfin, Emby, Plex, SMB, WebDAV or a local folder.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button { showAdd = true } label: {
                        Label("Add Library", systemImage: "plus")
                    }
                } footer: {
                    Text("Unlimited libraries and viewing environments.")
                        .font(DesignTokens.Typography.caption)
                }
            }
            .navigationTitle("Library")
            .sheet(isPresented: $showAdd) {
                AddLibrarySheet { library, credentials in
                    Task {
                        await container.add(library)
                        await scan(library, credentials: credentials)
                    }
                }
            }
            .alert("Scan failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func scan(_ library: Library, credentials: LibraryCredentials? = nil) async {
        scanning = library.id
        defer { scanning = nil }
        do {
            _ = try await container.store.scan(library, credentials: credentials)
            container.libraries = await container.store.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LibraryRow: View {
    let library: Library
    let isScanning: Bool
    let onScan: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(library.name)
                Text("\(library.sourceType.displayName) · \(library.itemCount) items")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isScanning {
                ProgressView()
            } else {
                Button(action: onScan) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct AddLibrarySheet: View {
    let onAdd: (Library, LibraryCredentials?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: MediaSourceType = .jellyfin
    @State private var server = ""
    @State private var userName = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Source", selection: $type) {
                        ForEach(MediaSourceType.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                }

                Section("Server") {
                    TextField(type == .local || type == .strm ? "Folder path" : "URL", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if type.needsCredentials {
                        TextField("User", text: $userName)
                            .textInputAutocapitalization(.never)
                        SecureField("Password / token", text: $password)
                    }
                }
            }
            .navigationTitle("New Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let url = URL(string: server)
                            ?? (type == .local || type == .strm ? URL(fileURLWithPath: server) : nil)
                        let library = Library(name: name.isEmpty ? type.displayName : name,
                                              sourceType: type,
                                              serverURL: url)
                        let credentials = type.needsCredentials
                            ? LibraryCredentials(userName: userName, password: password)
                            : nil
                        onAdd(library, credentials)
                        dismiss()
                    }
                    .disabled(server.isEmpty)
                }
            }
        }
    }
}
