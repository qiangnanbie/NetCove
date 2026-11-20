//
//  SearchView.swift
//  搜索：本地库过滤 + 远端元数据搜索（/api/metadata/search），带 300ms 防抖。
//

import SwiftUI
import Combine

struct SearchView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var remoteResults: [ScoredMatch] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !localResults.isEmpty {
                    Section("In your libraries") {
                        ForEach(localResults) { item in
                            NavigationLink {
                                DetailsView(item: item)
                            } label: {
                                row(title: item.title, subtitle: item.displaySubtitle,
                                    poster: item.posterURL)
                            }
                        }
                    }
                }

                Section("Online catalog") {
                    if isSearching {
                        HStack { ProgressView(); Text("Searching…") }
                    }
                    ForEach(remoteResults, id: \.externalID) { match in
                        Button {
                            Task { await open(match) }
                        } label: {
                            row(title: match.title,
                                subtitle: match.year.map(String.init),
                                poster: match.posterURL)
                        }
                        .foregroundStyle(.primary)
                    }
                    if remoteResults.isEmpty && !isSearching && !query.isEmpty {
                        Text("No results").font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(DesignTokens.Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Titles, people, keywords")
            .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var localResults: [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 1 else { return [] }
        return container.recent.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private func row(title: String, subtitle: String?, poster: URL?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(DesignTokens.Surface.raised)
                if let poster {
                    AsyncImage(url: poster) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else { Color.clear }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: 44, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scheduleSearch(_ value: String) {
        debounceTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            remoteResults = []
            return
        }
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                remoteResults = try await container.catalog.search(query: trimmed)
                errorMessage = nil
            } catch {
                remoteResults = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func open(_ match: ScoredMatch) async {
        if let item = try? await container.catalog.details(externalID: match.externalID, kind: .movie) {
            await container.addToWatchlist(item)
        }
    }
}
