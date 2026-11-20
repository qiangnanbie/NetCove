//
//  APIClient.swift
//  统一网络层：URLSession + 错误码映射。生产版可换 Alamofire 并接证书固定。
//

import Foundation

enum APIError: Error, LocalizedError {
    case transport(URLError)
    case http(status: Int, code: String?)
    case decoding(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .transport(let e): return "Network: \(e.localizedDescription)"
        case .http(let status, let code): return "HTTP \(status)\(code.map { " (\($0))" } ?? "")"
        case .decoding(let e): return "Decode: \(e.localizedDescription)"
        case .unauthorized: return "Session expired"
        }
    }
}

actor APIClient {
    private let config: AppConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(config: AppConfig) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.httpAdditionalHeaders = ["User-Agent": config.userAgent]
        self.session = URLSession(configuration: cfg)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    func baseURL(for endpoint: Endpoint) -> URL {
        endpoint.isAuthDomain ? config.authBaseURL : config.apiBaseURL
    }

    func request<T: Decodable>(
        _ endpoint: Endpoint,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        token: String? = nil
    ) async throws -> T {
        let data = try await perform(endpoint, query: query, body: body, token: token)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    @discardableResult
    func perform(
        _ endpoint: Endpoint,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        token: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: baseURL(for: endpoint)
            .appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw APIError.unauthorized }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue(token, forHTTPHeaderField: AppConfig.Header.accountToken)
        }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
                if http.statusCode == 401 { throw APIError.unauthorized }
                throw APIError.http(status: http.statusCode, code: envelope?.code)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.transport(error)
        }
    }
}

struct ErrorEnvelope: Decodable {
    let code: String?
    let message: String?
}

/// 类型擦除，便于把任意 Encodable 传进请求体
struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { encodeImpl = { try wrapped.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeImpl(encoder) }
}
