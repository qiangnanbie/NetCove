//
//  WatchlistStore.swift
//  「稍后看 / 片单」：本地持久化的条目快照（接 CloudKit 后作为缓存层）。
//  对应原 App 的 saved_mark / later_mark record type。
//

import Foundation

actor WatchlistStore {
    private var items: [MediaItem] = []
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("watchlist.json")
        load()
    }

    func all() -> [MediaItem] { items }

    func contains(id: UUID) -> Bool { items.contains { $0.id == id } }

    @discardableResult
    func add(_ item: MediaItem) -> Bool {
        guard !items.contains(where: { $0.sourceID == item.sourceID }) else { return false }
        items.insert(item, at: 0)
        persist()
        return true
    }

    func remove(sourceID: String) {
        items.removeAll { $0.sourceID == sourceID }
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) else { return }
        items = decoded
    }
}
