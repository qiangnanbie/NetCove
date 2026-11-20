//
//  ScriptHostBridge.swift
//  脚本模块的宿主桥：出网白名单 + 限流 + 请求合并 + 审计日志。
//  对应原 App 的 ScriptRequestGate / ScriptRequestCoalescer / ScriptPauseGate / RexScriptDebugLogStore。
//

import Foundation
import Combine
import JavaScriptCore

/// 脚本可出网的域名白名单（模块清单里申报，用户确认后生效）
struct ScriptSandboxPolicy {
    var allowedHosts: Set<String> = []
    var maxRequestsPerMinute = 30
    var requestTimeout: TimeInterval = 12
    var maxResponseBytes = 4 * 1024 * 1024

    func allows(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
            || allowedHosts.contains { host.hasSuffix("." + $0) }
    }
}

final class ScriptHostBridge: ScriptHTTPBridging {
    private let policy: ScriptSandboxPolicy
    private let session: URLSession
    private var timestamps: [Date] = []
    private let log: ScriptDebugLogStore

    init(policy: ScriptSandboxPolicy, log: ScriptDebugLogStore) {
        self.policy = policy
        self.log = log
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = policy.requestTimeout
        self.session = URLSession(configuration: config)
    }

    func fetch(_ request: ScriptHTTPRequest) async throws -> ScriptHTTPResponse {
        guard policy.allows(request.url) else {
            log.append("blocked \(request.url.host ?? "?")")
            throw ScriptError.hostNotAllowed(request.url.host ?? "?")
        }
        try throttle()

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let started = Date()
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ScriptError.transport }
        guard data.count <= policy.maxResponseBytes else { throw ScriptError.responseTooLarge }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        log.append("\(request.method) \(request.url.path) → \(http.statusCode) "
                   + String(format: "%.0fms", Date().timeIntervalSince(started) * 1000))
        return ScriptHTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    private func throttle() throws {
        let now = Date()
        timestamps = timestamps.filter { now.timeIntervalSince($0) < 60 }
        guard timestamps.count < policy.maxRequestsPerMinute else {
            throw ScriptError.rateLimited
        }
        timestamps.append(now)
    }
}

enum ScriptError: LocalizedError {
    case hostNotAllowed(String)
    case rateLimited
    case transport
    case responseTooLarge
    case signatureInvalid
    case invokeFailed(String)

    var errorDescription: String? {
        switch self {
        case .hostNotAllowed(let host): return "Module tried to reach \(host), which it didn't declare."
        case .rateLimited: return "Module hit its request rate limit."
        case .transport: return "Module request failed."
        case .responseTooLarge: return "Module response too large."
        case .signatureInvalid: return "Module signature is invalid."
        case .invokeFailed(let reason): return "Module call failed: \(reason)"
        }
    }
}

/// 调试日志（对应原 App 的 RexScriptDebugLogStore）
final class ScriptDebugLogStore: ObservableObject {
    @Published private(set) var lines: [String] = []
    private let limit = 400

    func append(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lines.append("[\(stamp)] \(line)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
    }

    func clear() { lines.removeAll() }
}

extension ScriptError {
    /// 供运行时把 JS 异常/缺函数统一成 ScriptError
    static func callFailed(_ reason: String) -> ScriptError { .invokeFailed(reason) }
}
