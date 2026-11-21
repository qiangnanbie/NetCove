//
//  DiscoverView.swift
//  发现页：环境头 + 模块列表（内置模块全部实现，自定义模块留脚本接入点）。
//

import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var modules: [HomeModule] = HomeModule.builtIn()
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    EnvironmentHeader()

                    ForEach(modules.filter(\.isEnabled)) { module in
                        ModuleSection(module: module)
                    }

                    if modules.isEmpty {
                        ContentUnavailableView("No modules", systemImage: "square.grid.2x2")
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.m)
            }
            .background(DesignTokens.Surface.base)
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        EnvironmentManagerView()
                    } label: {
                        Image(systemName: "switch.2")
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
    }
}

private struct EnvironmentHeader: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Viewing Environment")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                Text(container.currentEnvironment.name)
                    .font(DesignTokens.Typography.hero)
            }
            Spacer()
            Text("\(container.libraries.count) libraries")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
    }
}

private struct ModuleSection: View {
    let module: HomeModule
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text(LocalizedStringKey(module.title))
                .font(DesignTokens.Typography.title)
                .padding(.horizontal, DesignTokens.Spacing.m)

            switch module.kind {
            case .continueWatching:
                posterRow(items: container.recent)
            case .recent:
                posterRow(items: Array(container.recent.reversed()))
            case .recommended, .unwatched:
                posterRow(items: Array(container.recent.prefix(8)))
            case .genres:
                genreRow
            case .custom:
                Text("Custom module: \(module.scriptModuleID ?? "unbound")")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.m)
            }
        }
    }

    private func posterRow(items: [MediaItem]) -> some View {
        Group {
            if items.isEmpty {
                Text("Nothing here yet")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.m)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignTokens.Spacing.s) {
                        ForEach(items) { item in
                            NavigationLink {
                                DetailsView(item: item)
                            } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.m)
                }
            }
        }
    }

    private var genreRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.s) {
                ForEach(["Action", "Drama", "Sci-Fi", "Comedy", "Documentary", "Animation"],
                        id: \.self) { genre in
                    Text(genre)
                        .font(DesignTokens.Typography.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Surface.raised, in: Capsule())
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
        }
    }
}

struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .fill(DesignTokens.Surface.raised)
                if let posterURL = item.posterURL {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "film")
                                .font(.title2)
                                .foregroundStyle(DesignTokens.Accent.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(DesignTokens.Accent.secondary)
                }
            }
            .aspectRatio(DesignTokens.Aspect.poster, contentMode: .fit)
            .frame(width: 108)

            Text(item.title)
                .font(DesignTokens.Typography.caption)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
        }
    }
}
