//
//  EmbyFamilyClient.swift
//  Jellyfin / Emby 同源 API（AuthenticateByName、Items、PlaybackInfo）。
//

import Foundation

struct EmbyFamilyClient {
    enum Family: String {
        case jellyfin, emby
        var authHeader: String {
            switch self {
            case .jellyfin: return "Authorization"
            case .emby: return "X-Emby-Authorization"
            }
        }
    }

    let family: Family
    let baseURL: URL
    let userName: String
    let password: String
    private let session: URLSession

    init(family: Family, baseURL: URL, userName: String, password: String) {
        self.family = family
        self.baseURL = baseURL
        self.userName = userName
        self.password = password
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    struct AuthResult: Decodable {
        let accessToken: String
        let user: User
        struct User: Decodable { let id: String; let name: String }
    }

    func authenticate() async throws -> AuthResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientAuthorization, forHTTPHeaderField: family.authHeader)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": userName, "Pw": password])
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AuthResult.self, from: data)
    }

    struct ItemsResponse: Decodable {
        let items: [Item]?
        struct Item: Decodable {
            let id: String
            let name: String
            let type: String
            let productionYear: Int?
            let overview: String?
            let runTimeTicks: Int64?
            let indexNumber: Int?
            let parentIndexNumber: Int?
            let seriesId: String?
            let imageTags: [String: String]?
            let genres: [String]?
            let communityRating: Double?
        }
    }

    func fetchItems(token: String, userID: String,
                    includeTypes: [String] = ["Movie", "Series"],
                    limit: Int = 500) async throws -> [ItemsResponse.Item] {
        var components = URLComponents(url: baseURL.appendingPathComponent("Items"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: includeTypes.joined(separator: ",")),
            .init(name: "Fields", value: "Overview,ProductionYear,RunTimeTicks,Genres,CommunityRating,ImageTags"),
            .init(name: "Limit", value: String(limit)),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "UserId", value: userID)
        ]
        guard let url = components?.url else { throw ProviderError.badURL }
        var request = URLRequest(url: url)
        request.setValue(authorization(token: token), forHTTPHeaderField: family.authHeader)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ItemsResponse.self, from: data).items ?? []
    }

    struct PlaybackInfo: Decodable {
        let mediaSources: [MediaSource]?
        struct MediaSource: Decodable {
            let id: String
            let path: String?
            let container: String?
            let directStreamUrl: String?
            let mediaStreams: [MediaStream]?
            struct MediaStream: Decodable {
                let type: String
                let codec: String?
                let width: Int?
                let height: Int?
                let realFrameRate: Double?
                let bitRate: Int?
                let videoRange: String?
            }
        }
    }

    func playbackInfo(itemID: String, token: String, userID: String) async throws -> PlaybackInfo {
        var components = URLComponents(url: baseURL
            .appendingPathComponent("Items/\(itemID)/PlaybackInfo"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "UserId", value: userID)]
        guard let url = components?.url else { throw ProviderError.badURL }
        var request = URLRequest(url: url)
        request.setValue(authorization(token: token), forHTTPHeaderField: family.authHeader)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PlaybackInfo.self, from: data)
    }

    func imageURL(itemID: String, tag: String?, kind: String = "Primary", width: Int = 400) -> URL? {
        var components = URLComponents(url: baseURL
            .appendingPathComponent("Items/\(itemID)/Images/\(kind)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [.init(name: "maxWidth", value: String(width)),
                                  .init(name: "tag", value: tag)]
        return components?.url
    }

    private var clientAuthorization: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "MediaBrowser Client=\"NetCove\", Device=\"iOS\", DeviceId=\"netcove-ios\", Version=\"\(version)\""
    }

    private func authorization(token: String) -> String {
        "\(clientAuthorization), Token=\"\(token)\""
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ProviderError.transport }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError.http(http.statusCode) }
    }
}

enum ProviderError: LocalizedError {
    case badURL
    case transport
    case http(Int)
    case notConfigured(String)
    case parsing(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server URL"
        case .transport: return "Network error"
        case .http(let code): return "Server returned HTTP \(code)"
        case .notConfigured(let what): return "\(what) is not configured"
        case .parsing(let what): return "Cannot parse \(what)"
        }
    }
}
