//
//  WatchHistoryStore.swift
//  本地观看记录（无云端依赖时的默认实现；接 CloudKit 后作为缓存层）。
//

import Foundation

actor WatchHistoryStore {
    private var records: [WatchRecord] = []
    private var items: [UUID: MediaItem] = [:]
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("watch-history.json")
        load()
    }

    func record(itemID: UUID, position: Double, duration: Double) async {
        if let index = records.firstIndex(where: { $0.itemID == itemID }) {
            records[index].positionSeconds = position
            records[index].updatedAt = Date()
        } else {
            records.append(WatchRecord(itemID: itemID, positionSeconds: position,
                                       durationSeconds: duration, updatedAt: Date()))
        }
        persist()
    }

    func attach(_ item: MediaItem) async {
        items[item.id] = item
        persist()
    }

    func recent(limit: Int) async -> [MediaItem] {
        records.sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .compactMap { items[$0.itemID] }
    }

    func progress(for itemID: UUID) async -> Double? {
        records.first { $0.itemID == itemID }?.progress
    }

    private func persist() {
        struct Snapshot: Codable {
            var records: [WatchRecord]
            var items: [UUID: MediaItem]
        }
        let snapshot = Snapshot(records: records, items: items)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        struct Snapshot: Codable {
            var records: [WatchRecord]
            var items: [UUID: MediaItem]
        }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        records = snapshot.records
        items = snapshot.items
    }
}
