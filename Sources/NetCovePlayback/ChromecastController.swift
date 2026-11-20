//
//  ChromecastController.swift
//  发现：走 Bonjour（`_googlecast._tcp`），不依赖 SDK 也能列出设备。
//  投放：需要 Google Cast SDK（CocoaPods `google-cast-sdk`）。链接后下面的扩展自动启用；
//        没链接时抛出明确错误，而不是静默失败。
//

import Foundation

final class ChromecastDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {

    struct Device {
        var name: String
        var host: String?
        var port: Int
        var model: String?
    }

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var found: [Device] = []
    private var continuation: CheckedContinuation<[Device], Never>?
    private var timeoutTask: Task<Void, Never>?

    /// 搜索 1.5 秒，返回发现的设备（Bonjour 只在本网段有效）
    func discover(timeout: TimeInterval = 1.5) async -> [Device] {
        found = []
        services = []
        browser.delegate = self
        browser.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish()
            }
        }
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        browser.stop()
        continuation?.resume(returning: found)
        continuation = nil
    }

    // MARK: - NetServiceBrowserDelegate

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 1.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        finish()
    }

    // MARK: - NetServiceDelegate

    func netServiceDidResolveAddress(_ sender: NetService) {
        let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        found.append(Device(name: sender.name, host: host,
                            port: sender.port,
                            model: sender.txtRecordData().flatMap(Self.model(from:))))
    }

    private static func model(from txt: Data) -> String? {
        // TXT 记录格式：<len><key>=<value>
        var index = 0
        let bytes = [UInt8](txt)
        while index < bytes.count {
            let length = Int(bytes[index])
            index += 1
            guard index + length <= bytes.count else { break }
            let entry = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
            if entry.hasPrefix("md=") { return String(entry.dropFirst(3)) }
            index += length
        }
        return nil
    }
}

#if canImport(GoogleCast)
import GoogleCast

/// Google Cast SDK 已链接时：真正建立会话并加载媒体
final class ChromecastSession: NSObject, GCKSessionManagerListener {

    private let discovery = GCKCastContext.sharedInstance().discoveryManager
    private var pendingLoad: (url: URL, title: String)?

    func startSession(deviceName: String) -> Bool {
        let devices = discovery.devices
        guard let device = devices.first(where: { $0.friendlyName == deviceName }) else {
            return false
        }
        GCKCastContext.sharedInstance().sessionManager.add(self)
        GCKCastContext.sharedInstance().sessionManager.startSession(with: device)
        return true
    }

    func load(url: URL, title: String) throws {
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentCastSession?
            .remoteMediaClient else {
            pendingLoad = (url, title)
            throw CastError.targetUnavailable
        }
        let info = GCKMediaInformationBuilder(contentURL: url)
        info.streamType = .buffered
        info.contentType = "video/mp4"
        info.metadata = {
            let metadata = GCKMediaMetadata(metadataType: .movie)
            metadata.setString(title, forKey: kGCKMetadataKeyTitle)
            return metadata
        }()
        client.loadMedia(info.build())
    }

    func sessionManager(_ sessionManager: GCKSessionManager,
                        didStart session: GCKSession) {
        if let pendingLoad {
            try? load(url: pendingLoad.url, title: pendingLoad.title)
            self.pendingLoad = nil
        }
    }
}
#endif
