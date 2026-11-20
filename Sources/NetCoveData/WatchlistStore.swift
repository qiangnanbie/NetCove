//
//  WatchlistStore.swift
//  片单：本地持久化（走 NetCovePersistence，接 WCDB 后自动用数据库）。
//  对应原 App 的 saved_mark / later_mark record type。
//

import Foundation

actor WatchlistStore {
    private var items: [MediaItem] = []
    private var loaded = false
    private let persistence: NetCovePersistence

    init(persistence: NetCovePersistence = PersistenceFactory.make()) {
        self.persistence = persistence
    }

    private func loadIfNeeded() async {
        guard !loaded else { return }
        items = await persistence.readWatchlist()
        loaded = true
    }

    func all() async -> [MediaItem] {
        await loadIfNeeded()
        return items
    }

    func contains(id: UUID) async -> Bool {
        await loadIfNeeded()
        return items.contains { $0.id == id }
    }

    @discardableResult
    func add(_ item: MediaItem) async -> Bool {
        await loadIfNeeded()
        guard !items.contains(where: { $0.sourceID == item.sourceID }) else { return false }
        items.insert(item, at: 0)
        await persistence.writeWatchlist(items)
        return true
    }

    func remove(sourceID: String) async {
        await loadIfNeeded()
        items.removeAll { $0.sourceID == sourceID }
        await persistence.writeWatchlist(items)
    }

    func remove(id: UUID) async {
        await loadIfNeeded()
        items.removeAll { $0.id == id }
        await persistence.writeWatchlist(items)
    }
}
