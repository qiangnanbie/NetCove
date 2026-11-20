//
//  ScriptModule.swift
//  第三方「模块」体系：CommonJS 风格脚本 + 宿主桥（HTTP / TMDB / 内容密钥）。
//  对应原 App 的 RexScript（ScriptModuleEngine / ScriptPauseGate / ScriptRequestCoalescer）。
//

import Foundation
import JavaScriptCore

/// 宿主桥：脚本只能通过这里出网，统一限流、超时与审计。
protocol ScriptHTTPBridging {
    func fetch(_ request: ScriptHTTPRequest) async throws -> ScriptHTTPResponse
}

struct ScriptHTTPRequest {
    var url: URL
    var method: String
    var headers: [String: String]
    var body: Data?
}

struct ScriptHTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data
}
