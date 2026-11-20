//
//  EnvironmentManagerView.swift
//  观看环境管理：创建、复制、设默认、删除、PIN（无数量限制）。
//

import SwiftUI

struct EnvironmentManagerView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var newName = ""
    @State private var pendingDelete: ViewingEnvironment?

    var body: some View {
        List {
            Section("Environments") {
                ForEach(container.environments) { environment in
                    Button {
                        container.select(environment: environment)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(environment.name)
                                Text(environment.isDefault ? "Default" : environment.autoLock.rawValue)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if environment.id == container.currentEnvironment.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DesignTokens.Accent.primary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = environment
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            duplicate(environment)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
            }

            Section("Lock") {
                NavigationLink("PIN and Face ID") {
                    EnvironmentLockView(environment: container.currentEnvironment)
                }
            }

            Section {
                HStack {
                    TextField("New environment name", text: $newName)
                    Button("Create") { create() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Each environment keeps its own libraries, modules and watch history.")
                    .font(DesignTokens.Typography.caption)
            }
        }
        .navigationTitle("Environments")
        .confirmationDialog("Delete this environment and all its viewing data?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let target = pendingDelete {
                    container.environments.removeAll { $0.id == target.id }
                    if container.currentEnvironment.id == target.id,
                       let first = container.environments.first {
                        container.select(environment: first)
                    }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var environment = ViewingEnvironment.home
        environment.id = UUID()
        environment.name = trimmed
        environment.isDefault = container.environments.isEmpty
        container.environments.append(environment)
        container.select(environment: environment)
        newName = ""
    }

    private func duplicate(_ environment: ViewingEnvironment) {
        var copy = environment
        copy.id = UUID()
        copy.name = "\(environment.name) Copy"
        copy.isDefault = false
        container.environments.append(copy)
    }
}
