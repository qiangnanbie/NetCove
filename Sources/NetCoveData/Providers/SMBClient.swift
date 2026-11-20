//
//  SMBClient.swift
//  SMB2 走 AMSMB2（MIT）。未链接时降级为不可用，UI 会提示。
//

import Foundation

#if canImport(AMSMB2)
import AMSMB2

actor SMBClient {
    private let manager: SMBManager

    init(serverURL: URL, domain: String, user: String, password: String) {
        manager = SMBManager(serverURL: serverURL, credential: SMBCredential(domain: domain,
                                                                            username: user,
                                                                            password: password))
    }

    func connect() async throws { try await manager.connectShare(name: "") }

    func list(_ path: String) async throws -> [(name: String, isDirectory: Bool, size: Int64)] {
        let items = try await manager.contentsOfDirectory(atPath: path)
        return items.map { item in
            (item.name, item.isDirectory, item.fileSize)
        }
    }
}
#else

actor SMBClient {
    init(serverURL: URL, domain: String, user: String, password: String) {
        _ = (serverURL, domain, user, password)
    }

    func connect() async throws {
        throw ProviderError.notConfigured("SMB support needs AMSMB2")
    }

    func list(_ path: String) async throws -> [(name: String, isDirectory: Bool, size: Int64)] {
        throw ProviderError.notConfigured("SMB support needs AMSMB2")
    }
}

#endif
