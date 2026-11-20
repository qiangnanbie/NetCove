//
//  HomeModule.swift
//  发现页模块系统：内置模块 + 自定义模块，按环境独立配置。
//

import Foundation

struct HomeModule: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case continueWatching
        case recent
        case recommended
        case unwatched
        case genres
        case custom

        var displayName: String {
            switch self {
            case .continueWatching: return "Continue Watching"
            case .recent: return "Recently Added"
            case .recommended: return "Recommended"
            case .unwatched: return "Unwatched"
            case .genres: return "Genres"
            case .custom: return "Custom Module"
            }
        }
    }

    var id: UUID = UUID()
    var kind: Kind
    var title: String
    var isEnabled: Bool = true
    /// 自定义模块：脚本模块 ID（RexScript 同款能力）
    var scriptModuleID: String?
    /// 只显示指定库的内容（空 = 全部）
    var libraryIDs: [UUID] = []

    static func builtIn() -> [HomeModule] {
        [HomeModule(kind: .continueWatching, title: "Continue Watching"),
         HomeModule(kind: .recent, title: "Recently Added"),
         HomeModule(kind: .recommended, title: "Recommended"),
         HomeModule(kind: .unwatched, title: "Unwatched")]
    }
}
