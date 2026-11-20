//
//  WCDBPersistence.swift
//  WCDB 实现（Rex 同款数据库）。链接 WCDB 后自动替换 JSON 存储。
//  存法：一行一条 JSON payload —— 避免逐字段映射与模型演进时的迁移成本
//  （Rex 是全字段映射 + 明确索引；若需要按字段查询/排序，再把 payload 拆成列）。
//

#if canImport(WCDB)
import Foundation
import WCDBSwift

final class WCDBPersistence: NetCovePersistence {

    /// 通用行：kind 区分实体，payload 是 JSON
    final class Row: TableCodable {
        var key: String = ""
        var kind: String = ""
        var payload: String = ""

        enum CodingKeys: String, CodingTableKey {
            typealias Root = Row
            case key
            case kind
            case payload

            static let objectRelationalMapping = TableBinding(CodingKeys.self) {
                BindColumnConstraint(key, isPrimary: true)
            }
        }
    }

    private let database: Database
    private let table = "objects"

    init() throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        database = Database(at: base.appendingPathComponent("netcove.sqlite").path)
        try database.create(table: table, of: Row.self)
    }

    // MARK: - 通用读写

    private func write(_ objects: [Encodable], kind: String) {
        let encoder = JSONEncoder()
        let rows: [Row] = objects.compactMap { object in
            guard let data = try? encoder.encode(object),
                  let payload = String(data: data, encoding: .utf8) else { return nil }
            let row = Row()
            row.key = UUID().uuidString
            row.kind = kind
            row.payload = payload
            return row
        }
        try? database.delete(fromTable: table, where: Row.Properties.kind == kind)
        try? database.insert(rows, intoTable: table)
    }

    private func read<T: Decodable>(_ type: T.Type, kind: String) -> [T] {
        let rows = (try? database.getObjects(fromTable: table,
                                            where: Row.Properties.kind == kind)) ?? []
        let decoder = JSONDecoder()
        return rows.compactMap { row in
            guard let data = row.payload.data(using: .utf8) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    // MARK: - 具体实体

    func readLibraries() async -> [Library] { read(Library.self, kind: "library") }
    func writeLibraries(_ items: [Library]) async { write(items, kind: "library") }

    func readItems(libraryID: UUID) async -> [MediaItem] {
        read(MediaItem.self, kind: "items-\(libraryID.uuidString)")
    }

    func writeItems(_ items: [MediaItem], libraryID: UUID) async {
        write(items, kind: "items-\(libraryID.uuidString)")
    }

    func readWatchRecords() async -> [WatchRecord] { read(WatchRecord.self, kind: "watch") }
    func writeWatchRecords(_ items: [WatchRecord]) async { write(items, kind: "watch") }

    func readWatchlist() async -> [MediaItem] { read(MediaItem.self, kind: "watchlist") }
    func writeWatchlist(_ items: [MediaItem]) async { write(items, kind: "watchlist") }
}
#endif
