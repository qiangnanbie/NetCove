//
//  DetailsView.swift
//  详情页：hero 背景、海报、元数据、剧目/季集、播放入口。
//

import SwiftUI

struct DetailsView: View {
    let item: MediaItem
    @EnvironmentObject private var container: AppContainer
    @State private var showPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                hero

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Button {
                            showPlayer = true
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(DesignTokens.Typography.body.weight(.semibold))
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(DesignTokens.Accent.primary, in: Capsule())
                                .foregroundStyle(.black)
                        }

                        Button {
                        } label: {
                            Label("Add to List", systemImage: "plus")
                                .font(DesignTokens.Typography.body)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(DesignTokens.Surface.overlay, in: Capsule())
                        }
                    }

                    metadataLine

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(DesignTokens.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.m)
            }
        }
        .background(DesignTokens.Surface.base)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPlayer) {
            PlayerView(item: item)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let backdrop = item.backdropURL {
                AsyncImage(url: backdrop) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        DesignTokens.Surface.raised
                    }
                }
                .frame(height: 220)
                .clipped()
            } else {
                DesignTokens.Surface.raised.frame(height: 220)
            }

            LinearGradient(colors: [.clear, DesignTokens.Surface.base],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 220)

            Text(item.title)
                .font(DesignTokens.Typography.hero)
                .padding(DesignTokens.Spacing.m)
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 10) {
            if let year = item.year { Text(String(year)) }
            if let subtitle = item.displaySubtitle { Text(subtitle) }
            if let runtime = item.runtimeSeconds { Text("\(runtime / 60) min") }
            if let rating = item.rating { Text(String(format: "★ %.1f", rating)) }
        }
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(.secondary)
    }
}
