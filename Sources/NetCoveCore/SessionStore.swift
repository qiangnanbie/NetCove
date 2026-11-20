//
//  SessionStore.swift
//  账号会话：token 刷新、钥匙串存储、客态与登录态切换。
//  原 App 对应 auth.rexnow.tv/v1/native/*，并支持 passkey。
//

import Foundation
import Security

@MainActor
final class SessionStore: ObservableObject {
    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    @Published private(set) var tokens: Tokens?

    private let config: AppConfig
    private let service = "tv.netcove.app.session"
    private let account = "primary"

    init(config: AppConfig) {
        self.config = config
    }

    var isSignedIn: Bool { tokens != nil }

    func restore() async {
        guard let data = Keychain.read(service: service, account: account),
              let stored = try? JSONDecoder().decode(Tokens.self, from: data) else { return }
        tokens = stored
        if stored.expiresAt <= Date() { await refresh() }
    }

    func persist(_ newTokens: Tokens) {
        tokens = newTokens
        if let data = try? JSONEncoder().encode(newTokens) {
            Keychain.write(data, service: service, account: account)
        }
    }

    func signOut() {
        tokens = nil
        Keychain.delete(service: service, account: account)
    }

    private func refresh() async {
        guard let current = tokens else { return }
        // POST /v1/native/token/refresh
        _ = current
    }
}

enum Keychain {
    static func write(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
