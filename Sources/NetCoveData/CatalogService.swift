//
//  CatalogService.swift
//  元数据与匹配：优先自己后端（/api/metadata、/api/catalog/match），
//  后端不可用时回落 TMDB 直连（自带 key 即可）。
//

import Foundation

struct ScoredMatch: Hashable {
    var externalID: String
    var title: String
    var year: Int?
    var posterURL: URL?
    var score: Double
}

@MainActor
final class CatalogService {
    private let api: APIClient
    private let tmdbKey: String?
    private let session: URLSession

    init(api: APIClient, tmdbKey: String? = nil) {
        self.api = api
        self.tmdbKey = tmdbKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    // MARK: - 服务端优先

    func match(guess: FilenameGuess, kind: MediaItem.Kind) async throws -> [ScoredMatch] {
        struct Request: Encodable {
            let title: String
            let year: Int?
            let kind: String
            let season: Int?
            let episode: Int?
        }
        struct Response: Decodable {
            let matches: [Item]
            struct Item: Decodable {
                let externalID: String
                let title: String
                let year: Int?
                let posterURL: URL?
                let score: Double
            }
        }
        let body = Request(title: guess.title, year: guess.year,
                           kind: kind.rawValue, season: guess.season, episode: guess.episode)
        do {
            let response: Response = try await api.request(.catalogMatch, body: body)
            return response.matches.map {
                ScoredMatch(externalID: $0.externalID, title: $0.title,
                            year: $0.year, posterURL: $0.posterURL, score: $0.score)
            }
        } catch {
            return try await tmdbSearch(title: guess.title, year: guess.year, kind: kind)
        }
    }

    func details(externalID: String, kind: MediaItem.Kind) async throws -> MediaItem? {
        struct Response: Decodable {
            let id: String
            let title: String
            let originalTitle: String?
            let year: Int?
            let overview: String?
            let posterPath: String?
            let backdropPath: String?
            let runtimeMinutes: Int?
            let genres: [String]?
            let voteAverage: Double?
        }
        let response: Response = try await api.request(.metadata,
                                                       query: ["tmdb": externalID, "kind": kind.rawValue])
        return MediaItem(
            sourceID: response.id,
            libraryID: UUID(),
            title: response.title,
            originalTitle: response.originalTitle,
            year: response.year,
            kind: kind,
            overview: response.overview,
            posterURL: response.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") },
            backdropURL: response.backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") },
            runtimeSeconds: response.runtimeMinutes.map { $0 * 60 },
            genres: response.genres ?? [],
            rating: response.voteAverage
        )
    }

    /// GET /api/metadata/search?q=&kind=&year=
    func search(query: String, kind: MediaItem.Kind? = nil, year: Int? = nil) async throws -> [ScoredMatch] {
        struct Response: Decodable {
            let results: [Item]
            struct Item: Decodable {
                let id: String
                let title: String
                let year: Int?
                let posterUrl: String?
                let score: Double?
            }
        }
        var queryItems = ["q": query]
        if let kind { queryItems["kind"] = kind.rawValue }
        if let year { queryItems["year"] = String(year) }

        do {
            let response: Response = try await api.request(.searchMetadata, query: queryItems)
            return response.results.map {
                ScoredMatch(externalID: $0.id, title: $0.title, year: $0.year,
                            posterURL: $0.posterUrl.flatMap { URL(string: $0) },
                            score: $0.score ?? 0.5)
            }
        } catch {
            return try await tmdbSearch(title: query, year: year, kind: kind ?? .movie)
        }
    }

    func aiSearch(query: String) async throws -> [ScoredMatch] {
        struct Request: Encodable { let query: String }
        struct Response: Decodable {
            let results: [Item]
            struct Item: Decodable {
                let externalID: String
                let title: String
                let year: Int?
                let posterURL: URL?
                let score: Double
            }
        }
        let response: Response = try await api.request(.aiSearch, body: Request(query: query))
        return response.results.map {
            ScoredMatch(externalID: $0.externalID, title: $0.title,
                        year: $0.year, posterURL: $0.posterURL, score: $0.score)
        }
    }

    // MARK: - TMDB 直连回落

    private func tmdbSearch(title: String, year: Int?, kind: MediaItem.Kind) async throws -> [ScoredMatch] {
        guard let tmdbKey else { return [] }
        let path = kind == .series ? "tv" : "movie"
        var components = URLComponents(string: "https://api.themoviedb.org/3/search/\(path)")!
        var items = [URLQueryItem(name: "query", value: title),
                     URLQueryItem(name: "api_key", value: tmdbKey),
                     URLQueryItem(name: "language", value: "zh-CN")]
        if let year {
            items.append(URLQueryItem(name: kind == .series ? "first_air_date_year" : "year",
                                      value: String(year)))
        }
        components.queryItems = items
        guard let url = components.url else { return [] }

        let (data, _) = try await session.data(from: url)
        struct TMDBResponse: Decodable {
            let results: [Item]
            struct Item: Decodable {
                let id: Int
                let title: String?
                let name: String?
                let releaseDate: String?
                let firstAirDate: String?
                let posterPath: String?
                let popularity: Double?
            }
        }
        let decoded = try JSONDecoder().decode(TMDBResponse.self, from: data)
        return decoded.results.prefix(10).map { item in
            let dateString = item.releaseDate ?? item.firstAirDate
            let year = dateString.flatMap { Int($0.prefix(4)) }
            return ScoredMatch(
                externalID: String(item.id),
                title: item.title ?? item.name ?? "",
                year: year,
                posterURL: item.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") },
                score: min((item.popularity ?? 0) / 100, 1)
            )
        }
    }
}
