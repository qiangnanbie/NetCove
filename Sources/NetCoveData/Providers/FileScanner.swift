//
//  FileScanner.swift
//  本地目录 / STRM 扫描：文件系统遍历 + STRM 内容解析（STRM 里存的是播放地址）。
//

import Foundation

struct ScannedFile {
    var url: URL
    var size: Int64
    var modified: Date?
}

struct FileScanner {
    var videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "ts", "m2ts", "wmv", "flv", "webm", "iso", "rmvb"
    ]
    var strmExtension = "strm"
    var maxDepth = 8
    var skipPaths: [String] = []

    func scan(root: URL) throws -> [ScannedFile] {
        var results: [ScannedFile] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth { enumerator.skipDescendants(); continue }
            if skipPaths.contains(where: { url.path.hasPrefix($0) }) {
                enumerator.skipDescendants(); continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            let ext = url.pathExtension.lowercased()
            guard videoExtensions.contains(ext) || ext == strmExtension else { continue }
            results.append(ScannedFile(url: url,
                                       size: Int64(values?.fileSize ?? 0),
                                       modified: values?.contentModificationDate))
        }
        return results
    }

    /// STRM：首行非空内容即播放地址（可能是 http/https/rtsp/smb 路径）
    func resolveStrm(_ url: URL) throws -> URL? {
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return URL(string: trimmed)
        }
        return nil
    }
}
