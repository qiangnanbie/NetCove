//
//  WebDAVClient.swift
//  WebDAV/WebDAVS：PROPFIND 列目录。零依赖，纯 URLSession。
//

import Foundation

struct WebDAVEntry: Hashable {
    var href: URL
    var isDirectory: Bool
    var size: Int?
    var modified: Date?
    var contentType: String?
}

struct WebDAVClient {
    let baseURL: URL
    let userName: String?
    let password: String?
    private let session: URLSession

    init(baseURL: URL, userName: String?, password: String?) {
        self.baseURL = baseURL
        self.userName = userName
        self.password = password
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }

    private var authHeader: String? {
        guard let userName, let password else { return nil }
        let raw = Data("\(userName):\(password)".utf8).base64EncodedString()
        return "Basic \(raw)"
    }

    func list(_ url: URL? = nil) async throws -> [WebDAVEntry] {
        let target = url ?? baseURL
        var request = URLRequest(url: target)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        if let authHeader { request.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:"><d:prop>
        <d:getcontentlength/><d:getlastmodified/><d:getcontenttype/><d:resourcetype/>
        </d:prop></d:propfind>
        """.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.transport }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError.http(http.statusCode) }
        return WebDAVParser.parse(data: data, base: target)
    }
}

/// 极简 multistatus 解析：按 <d:response> 分块取字段，不引入 XML 依赖
enum WebDAVParser {

    static func parse(data: Data, base: URL) -> [WebDAVEntry] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var entries: [WebDAVEntry] = []
        for block in xml.components(separatedBy: "<D:response").dropFirst() {
            guard let raw = firstTag("D:href", in: block) else { continue }
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                                relativeTo: base)?.absoluteURL else { continue }
            if url.path == base.path { continue }
            entries.append(WebDAVEntry(
                href: url,
                isDirectory: block.contains("<D:collection"),
                size: firstTag("D:getcontentlength", in: block).flatMap(Int.init),
                modified: firstTag("D:getlastmodified", in: block).flatMap(parseHTTPDate),
                contentType: firstTag("D:getcontenttype", in: block)))
        }
        return entries
    }

    private static func firstTag(_ tag: String, in block: String) -> String? {
        guard let start = block.range(of: "<\(tag)>"),
              let end = block.range(of: "</\(tag)>", range: start.upperBound..<block.endIndex) else { return nil }
        return String(block[start.upperBound..<end.lowerBound])
    }

    private static func parseHTTPDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: raw)
    }
}
