//
//  PlexClient.swift
//  Plex：PIN 登录 → token → 列 section → 拉 metadata → Direct Play。
//

import Foundation

struct PlexClient {
    let baseURL: URL
    let token: String
    private let session: URLSession

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["Accept": "application/json", "X-Plex-Token": token]
        self.session = URLSession(configuration: config)
    }

    static func requestPin() async throws -> (id: Int, code: String) {
        var request = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins?strong=true")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Pin: Decodable { let id: Int; let code: String }
        let pin = try JSONDecoder().decode(Pin.self, from: data)
        return (pin.id, pin.code)
    }

    struct SectionsResponse: Decodable {
        let mediaContainer: MediaContainer?
        struct MediaContainer: Decodable { let directory: [Directory]? }
        struct Directory: Decodable { let key: String; let title: String; let type: String }
    }

    func sections() async throws -> [SectionsResponse.Directory] {
        let (data, _) = try await session.data(from: baseURL.appendingPathComponent("library/sections"))
        return try JSONDecoder().decode(SectionsResponse.self, from: data).mediaContainer?.directory ?? []
    }

    struct ItemsResponse: Decodable {
        let mediaContainer: MediaContainer?
        struct MediaContainer: Decodable { let metadata: [Item]? }
        struct Item: Decodable {
            let ratingKey: String
            let title: String
            let type: String
            let year: Int?
            let summary: String?
            let thumb: String?
            let art: String?
            let duration: Int?
            let index: Int?
            let parentIndex: Int?
            let grandparentTitle: String?
        }
    }

    func items(sectionKey: String) async throws -> [ItemsResponse.Item] {
        let url = baseURL.appendingPathComponent("library/sections/\(sectionKey)/all")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(ItemsResponse.self, from: data).mediaContainer?.metadata ?? []
    }

    func streamURL(ratingKey: String) -> URL? {
        var components = URLComponents(url: baseURL
            .appendingPathComponent("library/metadata/\(ratingKey)/file"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "X-Plex-Token", value: token)]
        return components?.url
    }

    func imageURL(path: String?, width: Int = 400) -> URL? {
        guard let path else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("photo/:/transcode"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "url", value: path),
                                  .init(name: "width", value: String(width)),
                                  .init(name: "X-Plex-Token", value: token)]
        return components?.url
    }
}
