//
//  Endpoints.swift
//  NetCove 后端契约（无付费墙版本）。
//  只保留账号、元数据/匹配、发现、集成、通知几组；原 license/points/security 已移除。
//

import Foundation

enum Endpoint {
    // 账号（auth 域）
    case emailLogin, emailCode, emailVerify, tokenRefresh, sessionLogout
    case passkeyList, passkeyRemove, nativeExchange

    // 元数据 / 匹配（api 域）
    case metadata            // GET  /api/metadata?tmdb=<id>&kind=movie
    case searchMetadata      // GET  /api/metadata/search?q=
    case playbackMetadata    // POST /api/metadata/playback/metadata
    case catalogMatch        // POST /api/catalog/match
    case catalogTitleHints   // POST /api/catalog/title-hints
    case aiSearch            // POST /api/discovery/ai-search

    // 其他
    case integrations        // GET  /api/integrations
    case notifications       // GET  /api/notifications
    case supportFeedback     // POST /api/support/feedback

    var path: String {
        switch self {
        case .emailLogin: return "/v1/native/email/login"
        case .emailCode: return "/v1/native/email/code"
        case .emailVerify: return "/v1/native/email/verify"
        case .tokenRefresh: return "/v1/native/token/refresh"
        case .sessionLogout: return "/v1/native/session/logout"
        case .passkeyList: return "/v1/native/passkeys/list"
        case .passkeyRemove: return "/v1/native/passkeys/remove"
        case .nativeExchange: return "/v1/native/exchange"
        case .metadata: return "/api/metadata"
        case .searchMetadata: return "/api/metadata/search"
        case .playbackMetadata: return "/api/metadata/playback/metadata"
        case .catalogMatch: return "/api/catalog/match"
        case .catalogTitleHints: return "/api/catalog/title-hints"
        case .aiSearch: return "/api/discovery/ai-search"
        case .integrations: return "/api/integrations"
        case .notifications: return "/api/notifications"
        case .supportFeedback: return "/api/support/feedback"
        }
    }

    var method: String {
        switch self {
        case .metadata, .searchMetadata, .integrations, .notifications, .passkeyList:
            return "GET"
        default:
            return "POST"
        }
    }

    var isAuthDomain: Bool {
        switch self {
        case .emailLogin, .emailCode, .emailVerify, .tokenRefresh,
             .sessionLogout, .passkeyList, .passkeyRemove, .nativeExchange:
            return true
        default:
            return false
        }
    }
}
