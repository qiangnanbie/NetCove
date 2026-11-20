//
//  NetCoveApp.swift
//  NetCove
//
//  App 入口。对应原 App 的 Rex/RexSceneDelegate + UIWindowSceneSessionRoleApplication。
//

import SwiftUI

@main
struct NetCoveApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootShell()
                .environmentObject(container)
                .task { await container.bootstrap() }
        }
    }
}
