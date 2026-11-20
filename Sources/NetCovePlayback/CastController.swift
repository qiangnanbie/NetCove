//
//  CastController.swift
//  投屏：DLNA/UPnP（SSDP 发现 + AVTransport SOAP）、AirPlay（系统路由）、Chromecast（占位）。
//

import Foundation
import SwiftUI
import AVKit
import Darwin

struct CastTarget: Identifiable, Hashable {
    var id: String
    var name: String
    var kind: Kind
    var location: URL?

    enum Kind: String {
        case dlna
        case airplay
        case chromecast
    }
}

// MARK: - DLNA / UPnP

final class DLNAController: NSObject {
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
        super.init()
    }

    /// SSDP M-SEARCH 发现 MediaRenderer 设备（UDP 239.255.255.250:1900）
    func discover(timeout: TimeInterval = 2.5) async -> [CastTarget] {
        await withCheckedContinuation { continuation in
            var results: [CastTarget] = []
            let queue = DispatchQueue(label: "netcove.ssdp")
            let group = DispatchGroup()
            group.enter()

            queue.async {
                let fd = socket(AF_INET, SOCK_DGRAM, 0)
                guard fd >= 0 else {
                    group.leave()
                    return
                }
                defer { close(fd) }

                var reuse: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(1900).bigEndian
                address.sin_addr.s_addr = inet_addr("239.255.255.250")

                let message = """
                M-SEARCH * HTTP/1.1\r
                HOST: 239.255.255.250:1900\r
                MAN: "ssdp:discover"\r
                MX: 2\r
                ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
                \r

                """
                _ = message.withCString { pointer in
                    withUnsafePointer(to: &address) { addressPointer in
                        addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                            sendto(fd, pointer, strlen(pointer), 0, sockaddrPointer,
                                   socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }

                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, Int32(timeout * 1000))
                if ready > 0 {
                    var buffer = [CChar](repeating: 0, count: 4096)
                    var sender = sockaddr_in()
                    var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let received = withUnsafeMutablePointer(to: &sender) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            recvfrom(fd, &buffer, buffer.count - 1, 0, $0, &senderLength)
                        }
                    }
                    if received > 0 {
                        let response = String(cString: buffer)
                        if let locationLine = response
                            .components(separatedBy: "\r\n")
                            .first(where: { $0.lowercased().hasPrefix("location:") }),
                           let url = URL(string: locationLine
                                .replacingOccurrences(of: "location:", with: "", options: .caseInsensitive)
                                .trimmingCharacters(in: .whitespaces)) {
                            results.append(CastTarget(id: url.absoluteString,
                                                      name: url.host ?? "DLNA Device",
                                                      kind: .dlna,
                                                      location: url))
                        }
                    }
                }
                group.leave()
            }

            group.notify(queue: .main) { continuation.resume(returning: results) }
        }
    }

    /// 让电视播放指定 URL：SetAVTransportURI + Play
    func play(url: URL, on target: CastTarget, mediaTitle: String) async throws {
        guard let location = target.location else { throw CastError.targetUnavailable }
        let controlURL = try await controlURL(fromDescription: location)
        let body = soapEnvelope(action: "Play", service: "AVTransport",
                                inner: "<InstanceID>0</InstanceID><Speed>1</Speed>")
        try await postSOAP(url: controlURL, service: "AVTransport", action: "Play", body: body)

        let uriBody = soapEnvelope(action: "SetAVTransportURI", service: "AVTransport", inner: """
        <InstanceID>0</InstanceID>
        <CurrentURI>\(url.absoluteString)</CurrentURI>
        <CurrentURIMetaData>&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&#13;
        &lt;item id="1" parentID="0" restricted="1"&gt;&#13;
        &lt;dc:title xmlns:dc="http://purl.org/dc/elements/1.1/"&gt;\(escape(mediaTitle))&lt;/dc:title&gt;&#13;
        &lt;/item&gt;&lt;/DIDL-Lite&gt;</CurrentURIMetaData>
        """)
        try await postSOAP(url: controlURL, service: "AVTransport",
                           action: "SetAVTransportURI", body: uriBody)
        try await postSOAP(url: controlURL, service: "AVTransport", action: "Play", body: body)
    }

    func pause(on target: CastTarget) async throws {
        guard let location = target.location else { throw CastError.targetUnavailable }
        let controlURL = try await controlURL(fromDescription: location)
        try await postSOAP(url: controlURL, service: "AVTransport", action: "Pause",
                           body: soapEnvelope(action: "Pause", service: "AVTransport",
                                              inner: "<InstanceID>0</InstanceID>"))
    }

    // MARK: - helpers

    private func controlURL(fromDescription url: URL) async throws -> URL {
        let (data, _) = try await session.data(from: url)
        guard let xml = String(data: data, encoding: .utf8),
              let range = xml.range(of: "<controlURL>") else {
            throw CastError.descriptionMissing
        }
        let rest = xml[range.upperBound...]
        guard let end = rest.range(of: "</controlURL>") else { throw CastError.descriptionMissing }
        let path = String(rest[..<end.lowerBound])
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        return URL(string: path, relativeTo: url)?.absoluteURL ?? url
    }

    private func postSOAP(url: URL, service: String, action: String, body: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:\(service):1#\(action)\"",
                         forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CastError.soapFailed(String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func soapEnvelope(action: String, service: String, inner: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="urn:schemas-upnp-org:service:\(service):1">\(inner)</u:\(action)></s:Body>
        </s:Envelope>
        """
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

enum CastError: LocalizedError {
    case targetUnavailable
    case descriptionMissing
    case soapFailed(String)

    var errorDescription: String? {
        switch self {
        case .targetUnavailable: return "Cast target is not reachable."
        case .descriptionMissing: return "Device description is missing a control URL."
        case .soapFailed(let message): return "Cast command failed: \(message.prefix(200))"
        }
    }
}

// MARK: - AirPlay（系统路由面板）

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor.white
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - 统一入口

@MainActor
final class CastController: ObservableObject {
    @Published private(set) var targets: [CastTarget] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var connected: CastTarget?

    private let dlna = DLNAController()

    func discover() async {
        isDiscovering = true
        defer { isDiscovering = false }
        targets = await dlna.discover()
    }

    func cast(url: URL, title: String, to target: CastTarget) async throws {
        switch target.kind {
        case .dlna:
            try await dlna.play(url: url, on: target, mediaTitle: title)
            connected = target
        case .airplay:
            // AirPlay 由系统路由面板接管，无需自绘 UI
            connected = target
        case .chromecast:
            throw CastError.targetUnavailable
        }
    }
}
