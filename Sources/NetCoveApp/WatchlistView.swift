//
//  WatchlistView.swift
//  片单：查看、移除、进入详情。
//

import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var items: [MediaItem] = []

    var body: some View {
        List {
            if items.isEmpty {
                Text("Nothing saved yet. Tap Add to List on a details page.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                NavigationLink {
                    DetailsView(item: item)
                } label: {
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
            .onDelete { indexSet in
                let targets = indexSet.map { items[$0] }
                Task {
                    for target in targets {
                        await container.removeFromWatchlist(target)
                    }
                    await refresh()
                }
            }
        }
        .navigationTitle("Watchlist")
        .task { await refresh() }
    }

    private func refresh() async {
        items = await container.watchlist()
    }
}
