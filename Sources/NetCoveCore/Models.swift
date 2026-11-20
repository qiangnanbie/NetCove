//
//  Models.swift
//  NetCove 领域模型。无付费墙：所有功能与格式全开。
//

import Foundation

// MARK: - 观看环境

struct ViewingEnvironment: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var isDefault: Bool
    var pinEnabled: Bool
    var autoLock: AutoLockPolicy
    var visibleDeviceTypes: [String]
    var libraryIDs: [UUID]

    enum AutoLockPolicy: String, Codable, CaseIterable {
        case immediately, minutes5, minutes30, never
    }

    static let home = ViewingEnvironment(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Home",
        isDefault: true,
        pinEnabled: false,
        autoLock: .minutes30,
        visibleDeviceTypes: ["iphone", "ipad", "appletv"],
        libraryIDs: []
    )
}

// MARK: - 媒体库与条目

enum MediaSourceType: String, Codable, CaseIterable, Identifiable {
    case jellyfin, emby, plex, smb, webdav, webdavs, pan115, ugreen, guangya, local, strm
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jellyfin: return "Jellyfin"
        case .emby: return "Emby"
        case .plex: return "Plex"
        case .smb: return "SMB"
        case .webdav: return "WebDAV"
        case .webdavs: return "WebDAV (TLS)"
        case .pan115: return "115"
        case .ugreen: return "UGREEN NAS"
        case .guangya: return "Guangya"
        case .local: return "Local"
        case .strm: return "STRM"
        }
    }

    var needsCredentials: Bool {
        switch self {
        case .local, .strm: return false
        default: return true
        }
    }
}

struct Library: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var sourceType: MediaSourceType
    var serverURL: URL? = nil
    var userName: String? = nil
    var lastScanAt: Date? = nil
    var itemCount: Int = 0
    var skipPaths: [String] = []
}

struct MediaItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    /// 服务端或文件系统内的稳定标识
    var sourceID: String
    var libraryID: UUID
    var title: String
    var originalTitle: String? = nil
    var year: Int?
    var kind: Kind
    var overview: String? = nil
    var posterURL: URL? = nil
    var backdropURL: URL? = nil
    var runtimeSeconds: Int? = nil
    var genres: [String] = []
    var rating: Double? = nil
    var parentID: String? = nil
    var indexNumber: Int? = nil
    var seasonNumber: Int? = nil

    enum Kind: String, Codable { case movie, series, season, episode, other }

    var displaySubtitle: String? {
        if kind == .episode, let season = seasonNumber, let index = indexNumber {
            return String(format: "S%02dE%02d", season, index)
        }
        return year.map(String.init)
    }
}

/// 一个可播放资源（同一 item 可能有多条：不同清晰度/编码）
struct PlayableResource: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var itemID: UUID
    var url: URL
    var container: String
    var videoCodec: String? = nil
    var audioCodec: String? = nil
    var width: Int
    var height: Int
    var frameRate: Double
    var bitrate: Int? = nil
    var hasHDR: Bool
    var hasDolbyVision: Bool
    var doviProfile: Int? = nil
    var hasCompleteMediaInfo: Bool
    var origin: Origin

    enum Origin: String, Codable { case library, module, cloudDrive }
}

// MARK: - 观看记录

struct WatchRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var itemID: UUID
    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date

    var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }
}
