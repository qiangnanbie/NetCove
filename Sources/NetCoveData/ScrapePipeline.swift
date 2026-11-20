//
//  ScrapePipeline.swift
//  刮削：文件名 → 结构化猜测 → 标题提示 → 服务端匹配。
//  文件名规则参考社区惯例：Title.2023.1080p.WEB-DL.x265-GROUP.mkv / S01E02 / 剧场版。
//

import Foundation

struct FilenameGuess {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
    var resolution: String?
    var source: String?
    var codec: String?
    var group: String?
    var confidence: Double
}

enum ScrapePipeline {
    private static let noiseTokens: Set<String> = [
        "1080p", "2160p", "720p", "480p", "4k", "uhd", "hdr", "hdr10", "dv", "dovi",
        "web-dl", "webrip", "bluray", "blu-ray", "bdrip", "hdtv", "remux", "x264", "x265",
        "h264", "h265", "hevc", "av1", "aac", "ac3", "eac3", "ddp", "dts", "truehd",
        "10bit", "8bit", "proper", "repack", "extended", "imax", "multi", "chs", "cht", "eng"
    ]

    static func guess(fileName: String) -> FilenameGuess {
        let base = (fileName as NSString).deletingPathExtension
        var working = base.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        var season: Int?
        var episode: Int?
        if let match = firstMatch(in: working, pattern: #"S(\d{1,2})E(\d{1,3})"#) {
            season = Int(match.0)
            episode = Int(match.1)
        } else if let match = firstMatch(in: working, pattern: #"第(\d{1,2})季.*?第(\d{1,3})集"#) {
            season = Int(match.0)
            episode = Int(match.1)
        }

        var year: Int?
        if let match = firstMatch(in: working, pattern: #"(19\d{2}|20\d{2})"#) {
            year = Int(match.0)
        }

        // 去掉 SxxExx 之前的剧集名残留与噪声 token
        var tokens = working.split(separator: " ").map(String.init)
        if let year, let index = tokens.firstIndex(of: String(year)) {
            tokens = Array(tokens.prefix(index))
        }
        let cleaned = tokens.filter { token in
            let lower = token.lowercased()
            if noiseTokens.contains(lower) { return false }
            if lower.hasPrefix("s") && lower.contains("e") && lower.count <= 6 { return false }
            if lower.hasPrefix("[") || lower.hasPrefix("【") { return false }
            return true
        }
        var title = cleaned.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if title.isEmpty { title = base }

        let resolution = ["2160p", "1080p", "720p", "480p"].first {
            base.lowercased().contains($0)
        }
        let confidence: Double = (season != nil ? 0.5 : 0.2) + (year != nil ? 0.3 : 0)
            + (resolution != nil ? 0.2 : 0)

        return FilenameGuess(title: title, year: year, season: season, episode: episode,
                             resolution: resolution, source: nil, codec: nil, group: nil,
                             confidence: confidence)
    }

    private static func firstMatch(in text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2 else {
            return nil
        }
        let first = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
        let second = match.numberOfRanges > 2
            ? Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            : ""
        return (first, second)
    }
}
