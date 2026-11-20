//
//  AppConfig.swift
//  后端地址与协议常量。原 App 用三个子域：api / auth / assets，外加 feedback。
//

import Foundation

struct AppConfig {
    var apiBaseURL = URL(string: "https://api.netcove.app")!
    var authBaseURL = URL(string: "https://auth.netcove.app")!
    var assetsBaseURL = URL(string: "https://assets.netcove.app")!
    var feedbackBaseURL = URL(string: "https://feedback.netcove.app")!

    var bundleIdentifier = Bundle.main.bundleIdentifier ?? "tv.netcove.app"
    var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "NetCove/\(version) (\(build))"
    }

    enum Header {
        static let accountToken = "x-netcove-account-token"
        static let userID = "x-user-id"
    }
}
