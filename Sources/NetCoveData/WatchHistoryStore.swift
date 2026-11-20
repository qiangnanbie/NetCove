//
//  WatchHistoryStore.swift
//  本地观看记录（无云端依赖时的默认实现；接 CloudKit 后作为缓存层）。
//

import Foundation

actor WatchHistoryStore {
    private var records: [WatchRecord] = []
    private var items: [UUID: MediaItem] = [:]
    private let persistence: NetCovePersistence

    init(persistence: NetCovePersistence = PersistenceFactory.make()) {
        self.persistence = persistence
    }

    private func loadIfNeeded() async {
        if records.isEmpty { records = await persistence.readWatchRecords() }
        if items.isEmpty {
            let stored = await persistence.readWatchlist()
            for item in stored { items[item.id] = item }
        }
    }

    func record(itemID: UUID, position: Double, duration: Double) async {
        await loadIfNeeded()
        if let index = records.firstIndex(where: { $0.itemID == itemID }) {
            records[index].positionSeconds = position
            records[index].updatedAt = Date()
        } else {
            records.append(WatchRecord(itemID: itemID, positionSeconds: position,
                                       durationSeconds: duration, updatedAt: Date()))
        }
        await persist()
    }

    func attach(_ item: MediaItem) async {
        await loadIfNeeded()
        items[item.id] = item
        await persist()
    }

    func recent(limit: Int) async -> [MediaItem] {
        await loadIfNeeded()
        return records.sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .compactMap { items[$0.itemID] }
    }

    func progress(for itemID: UUID) async -> Double? {
        await loadIfNeeded()
        return records.first { $0.itemID == itemID }?.progress
    }

    private func persist() async {
        await persistence.writeWatchRecords(records)
        await persistence.writeWatchlist(Array(items.values))
    }
}
