//
//  Persistence.swift
//  存储抽象：Rex 用 WCDB，这里给出协议 + JSON 实现 + WCDB 实现（链接后自动启用）。
//  三个 actor（LibraryStore / WatchHistoryStore / WatchlistStore）只依赖这个协议。
//

import Foundation

protocol NetCovePersistence: AnyObject {
    func readLibraries() async -> [Library]
    func writeLibraries(_ items: [Library]) async

    func readItems(libraryID: UUID) async -> [MediaItem]
    func writeItems(_ items: [MediaItem], libraryID: UUID) async

    func readWatchRecords() async -> [WatchRecord]
    func writeWatchRecords(_ items: [WatchRecord]) async

    func readWatchlist() async -> [MediaItem]
    func writeWatchlist(_ items: [MediaItem]) async
}

enum PersistenceFactory {
    /// 有 WCDB 就用 WCDB（与 Rex 一致），否则回落 JSON 文件
    static func make() -> NetCovePersistence {
        #if canImport(WCDB)
        if let store = try? WCDBPersistence() { return store }
        #endif
        return JSONPersistence()
    }
}

// MARK: - JSON 实现（默认，零依赖）

final class JSONPersistence: NetCovePersistence {
    private struct Snapshot: Codable {
        var libraries: [Library] = []
        var items: [String: [MediaItem]] = [:]
        var watchRecords: [WatchRecord] = []
        var watchlist: [MediaItem] = []
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "tv.netcove.persistence")
    private var snapshot = Snapshot()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("netcove-store.json")
        load()
    }

    func readLibraries() async -> [Library] { queue.sync { snapshot.libraries } }

    func writeLibraries(_ items: [Library]) async {
        queue.sync {
            snapshot.libraries = items
            persist()
        }
    }

    func readItems(libraryID: UUID) async -> [MediaItem] {
        queue.sync { snapshot.items[libraryID.uuidString] ?? [] }
    }

    func writeItems(_ items: [MediaItem], libraryID: UUID) async {
        queue.sync {
            snapshot.items[libraryID.uuidString] = items
            persist()
        }
    }

    func readWatchRecords() async -> [WatchRecord] { queue.sync { snapshot.watchRecords } }

    func writeWatchRecords(_ items: [WatchRecord]) async {
        queue.sync {
            snapshot.watchRecords = items
            persist()
        }
    }

    func readWatchlist() async -> [MediaItem] { queue.sync { snapshot.watchlist } }

    func writeWatchlist(_ items: [MediaItem]) async {
        queue.sync {
            snapshot.watchlist = items
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snapshot = decoded
    }
}
