//
//  WatchingView.swift
//  观看记录：继续观看 + 最近。
//

import SwiftUI

struct WatchingView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        NavigationStack {
            List {
                Section("Continue") {
                    if container.recent.isEmpty {
                        Text("Nothing in progress").foregroundStyle(.secondary)
                    }
                    ForEach(container.recent.prefix(10)) { item in
                        NavigationLink {
                            DetailsView(item: item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.rectangle")
                                    .foregroundStyle(DesignTokens.Accent.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                    if let subtitle = item.displaySubtitle {
                                        Text(subtitle)
                                            .font(DesignTokens.Typography.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Recent") {
                    if container.recent.isEmpty {
                        Text("History is empty").foregroundStyle(.secondary)
                    }
                    ForEach(Array(container.recent.reversed().prefix(20))) { item in
                        NavigationLink {
                            DetailsView(item: item)
                        } label: {
                            Text(item.title)
                        }
                    }
                }
            }
            .navigationTitle("Watching")
        }
    }
}
