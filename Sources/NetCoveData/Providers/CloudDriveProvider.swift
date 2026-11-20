//
//  CloudDriveProvider.swift
//  云盘抽象：115 / UGREEN / Guangya 各自实现，统一成"列目录 + 取播放地址"。
//

import Foundation

protocol CloudDriveProvider {
    var sourceType: MediaSourceType { get }
    /// 用凭据换取可用的 access token（部分平台是扫码/设备码流程）
    func authenticate(credentials: LibraryCredentials?) async throws -> String
    /// 列某一目录
    func list(path: String, token: String) async throws -> [CloudDriveEntry]
    /// 取播放直链（有效期通常很短，播放前必须现取）
    func playbackURL(fileID: String, token: String) async throws -> URL
}

struct CloudDriveEntry {
    var id: String
    var name: String
    var isDirectory: Bool
    var size: Int64
    var parentID: String?
}

enum CloudDriveRegistry {
    static func make(for type: MediaSourceType) -> CloudDriveProvider {
        switch type {
        case .pan115: return Pan115Client()
        case .ugreen: return UGreenCloudClient()
        case .guangya: return GuangyaCloudClient()
        default: return UnsupportedCloudDrive(type: type)
        }
    }
}

struct UnsupportedCloudDrive: CloudDriveProvider {
    let type: MediaSourceType
    var sourceType: MediaSourceType { type }
    func authenticate(credentials: LibraryCredentials?) async throws -> String {
        throw ProviderError.notConfigured("\(type.displayName) cloud drive")
    }
    func list(path: String, token: String) async throws -> [CloudDriveEntry] {
        throw ProviderError.notConfigured("\(type.displayName) cloud drive")
    }
    func playbackURL(fileID: String, token: String) async throws -> URL {
        throw ProviderError.notConfigured("\(type.displayName) cloud drive")
    }
}

// MARK: - 115

/// 115 网盘：设备码授权（passportapi）+ 文件列表 / 下载地址（proapi）
struct Pan115Client: CloudDriveProvider {
    let sourceType: MediaSourceType = .pan115

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    /// 第一步：申请设备码（用户在自己手机上确认）
    struct DeviceCode: Decodable {
        let uid: String?
        let code: String?
        let time: Int?
        let sign: String?
        let qrcode: String?
    }

    func requestDeviceCode(clientID: String) async throws -> DeviceCode {
        var components = URLComponents(string: "https://passportapi.115.com/open/authDeviceCode")!
        components.queryItems = [.init(name: "client_id", value: clientID)]
        var request = URLRequest(url: components.url!)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    /// 第二步：轮询换取 token
    func pollDeviceToken(uid: String, code: String) async throws -> String {
        var components = URLComponents(string: "https://passportapi.115.com/open/deviceCodeToToken")!
        components.queryItems = [.init(name: "uid", value: uid), .init(name: "code", value: code)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await session.data(for: request)
        struct Response: Decodable {
            let data: Payload?
            struct Payload: Decodable { let access_token: String }
        }
        return try JSONDecoder().decode(Response.self, from: data).data?.access_token ?? ""
    }

    func authenticate(credentials: LibraryCredentials?) async throws -> String {
        // 已存 token 直接用；否则需要走设备码流程（UI 侧展示二维码）
        guard let token = credentials?.password, !token.isEmpty else {
            throw ProviderError.notConfigured("115 access token (finish device-code login first)")
        }
        return token
    }

    func list(path: String, token: String) async throws -> [CloudDriveEntry] {
        var components = URLComponents(string: "https://proapi.115.com/open/ufile/files")!
        components.queryItems = [
            .init(name: "cid", value: path.isEmpty ? "0" : path),
            .init(name: "limit", value: "1000"),
            .init(name: "show_dir", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        struct Response: Decodable {
            let data: [Payload]?
            struct Payload: Decodable {
                let fid: String
                let fn: String
                let fc: String
                let fs: Int64?
            }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.data ?? []).map {
            CloudDriveEntry(id: $0.fid,
                            name: $0.fn,
                            isDirectory: $0.fc == "0",
                            size: $0.fs ?? 0,
                            parentID: path.isEmpty ? nil : path)
        }
    }

    func playbackURL(fileID: String, token: String) async throws -> URL {
        var components = URLComponents(string: "https://proapi.115.com/open/ufile/downurl")!
        components.queryItems = [.init(name: "pick_code", value: fileID)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        struct Response: Decodable {
            let data: [String: Payload]?
            struct Payload: Decodable { let url: PayloadURL }
            struct PayloadURL: Decodable { let url: String }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let raw = decoded.data?.values.first?.url.url,
              let url = URL(string: raw) else {
            throw ProviderError.parsing("115 download url")
        }
        return url
    }
}

// MARK: - UGREEN / Guangya

/// 绿联 NAS：官方开放平台按账号鉴权，接口随固件版本变化，这里给同构实现骨架
struct UGreenCloudClient: CloudDriveProvider {
    let sourceType: MediaSourceType = .ugreen
    private let session = URLSession(configuration: .default)

    func authenticate(credentials: LibraryCredentials?) async throws -> String {
        guard let base = credentials?.userName, let token = credentials?.password, !token.isEmpty else {
            throw ProviderError.notConfigured("UGREEN API base URL and token")
        }
        _ = base
        return token
    }

    func list(path: String, token: String) async throws -> [CloudDriveEntry] {
        _ = (path, token)
        throw ProviderError.notConfigured("UGREEN file listing (needs your NAS API endpoint)")
    }

    func playbackURL(fileID: String, token: String) async throws -> URL {
        _ = (fileID, token)
        throw ProviderError.notConfigured("UGREEN playback (needs your NAS API endpoint)")
    }
}

/// 光雅云盘：私有部署居多，用 WebDAV 兼容层最常见
struct GuangyaCloudClient: CloudDriveProvider {
    let sourceType: MediaSourceType = .guangya

    func authenticate(credentials: LibraryCredentials?) async throws -> String {
        credentials?.password ?? ""
    }

    func list(path: String, token: String) async throws -> [CloudDriveEntry] {
        // 走 WebDAV 兼容层：把云盘当 WebDAV 挂载
        guard let base = URL(string: path) else { throw ProviderError.badURL }
        let client = WebDAVClient(baseURL: base, userName: nil, password: token)
        let entries = try await client.list()
        return entries.map {
            CloudDriveEntry(id: $0.href.absoluteString,
                            name: $0.href.lastPathComponent,
                            isDirectory: $0.isDirectory,
                            size: Int64($0.size ?? 0),
                            parentID: nil)
        }
    }

    func playbackURL(fileID: String, token: String) async throws -> URL {
        guard let url = URL(string: fileID) else { throw ProviderError.badURL }
        return url
    }
}
