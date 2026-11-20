//
//  CloudSyncEngine.swift
//  CloudKit 私有库同步（对应 spec/07-cloudkit.md 的 26 个 record type）。
//  策略：本地优先写入 → 增量推送到 netcove-main zone → 拉取对端变更 → 按 modifiedAt 合并。
//

import Foundation
import CloudKit

/// 同步实体（先覆盖最常变的五类，其余 record type 按同一模式扩展）
enum SyncEntityKind: String, CaseIterable {
    case library        = "catalog"
    case environment    = "environment"
    case watchRecord    = "media_watched"
    case progress       = "playback_progress"
    case settings       = "settings_sync"

    var recordType: String { rawValue }
}

struct SyncEnvelope: Codable {
    var recordName: String
    var kind: SyncEntityKind
    var modifiedAt: Double
    var deleted: Bool
    var payload: [String: String]
}

@MainActor
final class CloudSyncEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case running(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastSyncAt: Date?
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "netcove.sync.enabled")

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let local: LocalSyncStore
    private var timer: Task<Void, Never>?

    /// zone 名与 schema 对齐：原 App 是 rex-main，这里 netcove-main
    static let zoneName = "netcove-main"

    init(containerIdentifier: String? = nil, local: LocalSyncStore = LocalSyncStore()) {
        let container = containerIdentifier.map { CKContainer(identifier: $0) } ?? CKContainer.default()
        self.container = container
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        self.local = local
    }

    // MARK: - 生命周期

    func startPeriodicSync(interval: TimeInterval = 300) {
        timer?.cancel()
        guard isEnabled else { return }
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                await self?.syncNow()
            }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - 主流程

    func syncNow() async {
        guard isEnabled else { return }
        state = .running("Preparing")
        do {
            try await ensureZone()
            state = .running("Pushing")
            try await pushLocalChanges()
            state = .running("Pulling")
            try await pullRemoteChanges()
            lastSyncAt = Date()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 首次同步时确保自定义 zone 存在（已存在会抛 zoneNotFound 以外的错误则忽略）
    private func ensureZone() async throws {
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // 已存在：忽略
            _ = error
        }
    }

    // MARK: - 推送

    private func pushLocalChanges() async throws {
        let pending = await local.pendingEnvelopes()
        guard !pending.isEmpty else { return }

        let records: [CKRecord] = pending.map { envelope in
            let record = CKRecord(recordType: envelope.kind.recordType,
                                  recordID: CKRecord.ID(recordName: envelope.recordName, zoneID: zoneID))
            for (key, value) in envelope.payload {
                record[key] = value as CKRecordValue
            }
            record["modifiedAt"] = envelope.modifiedAt as CKRecordValue
            return record
        }

        let result = try await database.modifyRecords(saving: records,
                                                     deleting: [],
                                                     savePolicy: .changedKeys,
                                                     atomically: true)
        for (_, outcome) in result.saveResults {
            if case .success(let saved) = outcome {
                await local.markSynced(recordName: saved.recordID.recordName,
                                       serverModifiedAt: saved["modifiedAt"] as? Double ?? 0)
            }
        }
    }

    // MARK: - 拉取

    private func pullRemoteChanges() async throws {
        let token = await local.changeToken()

        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: token,
            resultsLimit: 200,
            desiredKeys: nil
        )

        var incoming: [SyncEnvelope] = []
        var deletedNames: [String] = []
        var nextToken: CKServerChangeToken?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.recordWasChangedBlock = { _, result in
                guard case .success(let record) = result else { return }
                var payload: [String: String] = [:]
                for key in record.allKeys() {
                    if let string = record[key] as? String { payload[key] = string }
                    else if let number = record[key] as? NSNumber { payload[key] = number.stringValue }
                }
                incoming.append(SyncEnvelope(
                    recordName: record.recordID.recordName,
                    kind: SyncEntityKind(rawValue: record.recordType) ?? .settings,
                    modifiedAt: record["modifiedAt"] as? Double ?? 0,
                    deleted: false,
                    payload: payload
                ))
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                deletedNames.append(recordID.recordName)
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case .success(let fetched) = result {
                    nextToken = fetched.serverChangeToken
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }

        await local.merge(incoming, deletedRecordNames: deletedNames)
        if let nextToken {
            await local.setChangeToken(nextToken)
        }
    }
}

/// 本地同步队列：记录待推送改动、保存 change token、按 modifiedAt 合并
actor LocalSyncStore {
    private var pending: [SyncEnvelope] = []
    private var token: CKServerChangeToken?
    private let pendingURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        pendingURL = base.appendingPathComponent("sync-pending.json")
        load()
    }

    func enqueue(_ envelope: SyncEnvelope) {
        if let index = pending.firstIndex(where: { $0.recordName == envelope.recordName }) {
            pending[index] = envelope
        } else {
            pending.append(envelope)
        }
        persist()
    }

    func pendingEnvelopes() -> [SyncEnvelope] { pending }

    func markSynced(recordName: String, serverModifiedAt: Double) {
        _ = serverModifiedAt
        pending.removeAll { $0.recordName == recordName }
        persist()
    }

    func merge(_ incoming: [SyncEnvelope], deletedRecordNames: [String] = []) {
        pending.removeAll { deletedRecordNames.contains($0.recordName) }
        for envelope in incoming {
            guard let index = pending.firstIndex(where: { $0.recordName == envelope.recordName }) else {
                pending.append(envelope)
                continue
            }
            // 冲突：以 modifiedAt 较新的一方为准
            if envelope.modifiedAt > pending[index].modifiedAt {
                pending[index] = envelope
            }
        }
        persist()
    }

    func changeToken() -> CKServerChangeToken? { token }
    func setChangeToken(_ value: CKServerChangeToken?) { token = value }

    private func persist() {
        if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: pendingURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: pendingURL),
              let decoded = try? JSONDecoder().decode([SyncEnvelope].self, from: data) else { return }
        pending = decoded
    }
}
