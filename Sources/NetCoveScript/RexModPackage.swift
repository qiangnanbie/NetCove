//
//  RexModPackage.swift
//  .rexmod 模块包：zip 容器（module.json + 入口脚本 + 可选 assets）。
//  校验：清单字段 + 内容 SHA-256 + 可选 Ed25519 签名。
//  说明：只支持 stored（不压缩）条目 —— 模块脚本很小，打包工具默认即 stored，
//        遇到 deflate 条目会给出明确错误提示，而不是静默失败。
//

import Foundation
import CryptoKit

struct RexModManifest: Codable {
    var id: String
    var name: String
    var version: String
    var author: String?
    var entry: String
    var capabilities: [Capability]
    var signature: String?

    enum Capability: String, Codable, CaseIterable {
        case http, tmdb, playback, danmaku, subtitle, storage
    }
}

enum RexModError: LocalizedError {
    case notAZip
    case unsupportedCompression(UInt16)
    case missingEntry(String)
    case badManifest(String)
    case digestMismatch
    case signatureInvalid
    case versionTooLow(String)

    var errorDescription: String? {
        switch self {
        case .notAZip: return "This file isn't a valid .rexmod package."
        case .unsupportedCompression(let method):
            return "Unsupported zip compression \(method). Repack with the default stored format."
        case .missingEntry(let name): return "Package is missing \(name)."
        case .badManifest(let reason): return "module.json is invalid: \(reason)"
        case .digestMismatch: return "Module content doesn't match its declared digest."
        case .signatureInvalid: return "Module signature is invalid."
        case .versionTooLow(let version): return "Module requires a newer NetCove (\(version))."
        }
    }
}

// MARK: - 最小 zip 读取（stored 条目）

struct ZipEntry {
    var name: String
    var method: UInt16
    var compressedSize: Int
    var uncompressedSize: Int
    var headerOffset: Int
}

enum ZipReader {

    static func entries(in data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard let eocd = findEOCD(bytes) else { throw RexModError.notAZip }
        let entryCount = Int(readUInt16(bytes, eocd + 10))
        var offset = Int(readUInt32(bytes, eocd + 16))
        var result: [ZipEntry] = []

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count,
                  readUInt32(bytes, offset) == 0x0201_4b50 else { throw RexModError.notAZip }
            let method = readUInt16(bytes, offset + 10)
            let compressed = Int(readUInt32(bytes, offset + 20))
            let uncompressed = Int(readUInt32(bytes, offset + 24))
            let nameLength = Int(readUInt16(bytes, offset + 28))
            let extraLength = Int(readUInt16(bytes, offset + 30))
            let commentLength = Int(readUInt16(bytes, offset + 32))
            let headerOffset = Int(readUInt32(bytes, offset + 42))
            let nameStart = offset + 46
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)

            result.append(ZipEntry(name: name, method: method,
                                   compressedSize: compressed,
                                   uncompressedSize: uncompressed,
                                   headerOffset: headerOffset))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return result
    }

    static func extract(_ entry: ZipEntry, from data: Data) throws -> Data {
        guard entry.method == 0 else {
            throw RexModError.unsupportedCompression(entry.method)
        }
        let bytes = [UInt8](data)
        let header = entry.headerOffset
        guard header + 30 <= bytes.count, readUInt32(bytes, header) == 0x0403_4b50 else {
            throw RexModError.notAZip
        }
        let nameLength = Int(readUInt16(bytes, header + 26))
        let extraLength = Int(readUInt16(bytes, header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw RexModError.notAZip }
        return data.subdata(in: start..<(start + entry.compressedSize))
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count > 22 else { return nil }
        let minimum = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= minimum {
            if readUInt32(bytes, index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

// MARK: - 清单 / 校验 / 安装

enum RexModPackage {

    struct Loaded {
        var manifest: RexModManifest
        var files: [String: Data]
        var digest: String
    }

    /// 与 tools/pack_module.py 完全一致的摘要算法：
    ///   1) "module.json" + \0 + 规范化清单 JSON（不含 signature） + \0
    ///   2) 其余文件按路径排序：路径 + \0 + 内容 + \0
    static func digest(manifest: RexModManifest, files: [String: Data]) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("module.json".utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: canonicalManifest(manifest))
        hasher.update(data: Data([0]))
        for path in files.keys.sorted() where path != "module.json" {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: files[path] ?? Data())
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 规范化清单：键按字母序、无空白、不转义非 ASCII、不含 signature 字段。
    /// 必须与 Python 侧 json.dumps(sort_keys=True, separators=(',', ':'), ensure_ascii=False) 逐字节一致。
    static func canonicalManifest(_ manifest: RexModManifest) -> Data {
        let capabilities = manifest.capabilities.map { "\"\(escape($0.rawValue))\"" }.joined(separator: ",")
        let author = manifest.author.map { "\"\(escape($0))\"" } ?? "null"
        let json = "{\"author\":\(author)"
            + ",\"capabilities\":[\(capabilities)]"
            + ",\"entry\":\"\(escape(manifest.entry))\""
            + ",\"id\":\"\(escape(manifest.id))\""
            + ",\"name\":\"\(escape(manifest.name))\""
            + ",\"version\":\"\(escape(manifest.version))\"}"
        return Data(json.utf8)
    }

    private static func escape(_ value: String) -> String {
        var out = ""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out
    }

    static func read(_ data: Data) throws -> Loaded {
        var files: [String: Data] = [:]
        for entry in try ZipReader.entries(in: data) where !entry.name.hasSuffix("/") {
            files[entry.name] = try ZipReader.extract(entry, from: data)
        }
        guard let manifestData = files["module.json"] else {
            throw RexModError.missingEntry("module.json")
        }
        let manifest: RexModManifest
        do {
            manifest = try JSONDecoder().decode(RexModManifest.self, from: manifestData)
        } catch {
            throw RexModError.badManifest(error.localizedDescription)
        }
        guard !manifest.id.isEmpty else { throw RexModError.badManifest("empty id") }
        guard files[manifest.entry] != nil else { throw RexModError.missingEntry(manifest.entry) }

        return Loaded(manifest: manifest, files: files,
                      digest: digest(manifest: manifest, files: files))
    }

    /// 验签：签名是对 digest 的 Ed25519 签名（hex）。
    /// 公钥由 App 内置（受信任发布者），没有内置公钥时只做完整性校验。
    static func verify(_ loaded: Loaded,
                       trustedPublicKey: Curve25519.Signing.PublicKey?,
                       expectedDigest: String? = nil) throws {
        if let expectedDigest, expectedDigest != loaded.digest {
            throw RexModError.digestMismatch
        }
        guard let signatureHex = loaded.manifest.signature else { return }
        guard let trustedPublicKey else {
            throw RexModError.signatureInvalid
        }
        guard let signature = Data(hexString: signatureHex),
              let payload = Data(hexString: loaded.digest) else {
            throw RexModError.signatureInvalid
        }
        guard trustedPublicKey.isValidSignature(signature, for: payload) else {
            throw RexModError.signatureInvalid
        }
    }
}

extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}

// MARK: - 仓库（安装 / 卸载 / 列表）

@MainActor
final class RexModRepository: ObservableObject {
    @Published private(set) var installed: [RexModManifest] = []
    @Published private(set) var lastError: String?

    private let root: URL
    private let trustedKey: Curve25519.Signing.PublicKey?

    init(trustedKeyBase64: String? = Bundle.main.object(forInfoDictionaryKey: "NetCoveModuleKey") as? String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent("script-modules")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let trustedKeyBase64, let keyData = Data(base64Encoded: trustedKeyBase64) {
            trustedKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } else {
            trustedKey = nil
        }
        refresh()
    }

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                includingPropertiesForKeys: nil)) ?? []
        installed = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("module.json")),
                  let manifest = try? JSONDecoder().decode(RexModManifest.self, from: data) else {
                return nil
            }
            return manifest
        }
        .sorted { $0.name < $1.name }
    }

    /// 安装：校验 → 解到 script-modules/<id>/
    @discardableResult
    func install(data: Data) throws -> RexModManifest {
        let loaded = try RexModPackage.read(data)
        try RexModPackage.verify(loaded, trustedPublicKey: trustedKey)

        let target = root.appendingPathComponent(loaded.manifest.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for (path, content) in loaded.files {
            let destination = target.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.write(to: destination, options: .atomic)
        }
        refresh()
        return loaded.manifest
    }

    func install(fileURL: URL) throws -> RexModManifest {
        try install(data: Data(contentsOf: fileURL))
    }

    func uninstall(_ manifest: RexModManifest) {
        let target = root.appendingPathComponent(manifest.id, isDirectory: true)
        try? FileManager.default.removeItem(at: target)
        refresh()
    }

    func moduleDirectory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }
}
