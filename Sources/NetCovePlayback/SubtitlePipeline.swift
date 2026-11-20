//
//  SubtitlePipeline.swift
//  字幕管线：外部文件（SRT/ASS/VTT）、内嵌轨（PGS/VobSub）、在线下载、
//  以及 AI 生成字幕的对齐。ASS 走 libass，位图字幕走 FFmpeg 解码成图层。
//

import Foundation

enum SubtitleFormat: String, Codable, CaseIterable {
    case srt, ass, ssa, vtt, pgs, vobsub, unknown

    static func detect(fileName: String) -> SubtitleFormat {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "srt": return .srt
        case "ass": return .ass
        case "ssa": return .ssa
        case "vtt": return .vtt
        case "sup": return .pgs
        case "sub", "idx": return .vobsub
        default: return .unknown
        }
    }

    var isTextBased: Bool {
        switch self {
        case .srt, .ass, .ssa, .vtt: return true
        default: return false
        }
    }
}

struct SubtitleCue: Identifiable, Hashable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var style: SubtitleStyle?
}

struct SubtitleStyle: Hashable {
    var fontName: String = "PingFang SC"
    var fontSize: CGFloat = 22
    var primaryColor: String = "#FFFFFF"
    var outlineColor: String = "#000000"
    var outlineWidth: CGFloat = 2
    var shadow: CGFloat = 1
    var bottomInset: CGFloat = 28
    var alignment: Int = 2 // libass: 2 = bottom center
}

/// SRT/VTT 解析（纯文本，无第三方依赖）
enum SubtitleParser {

    static func parse(data: Data) -> [SubtitleCue] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return [] }
        if text.contains("[Script Info]") { return [] } // ASS 交给 libass
        return parseSRT(text)
    }

    static func parseSRT(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timeLine = lines.first(where: { $0.contains("-->") }) else { continue }
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }
            let textLines = lines.drop { $0 != timeLine && !$0.contains("-->") }
                .dropFirst()
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !textLines.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: textLines.joined(separator: "\n")))
        }
        return cues.sorted { $0.start < $1.start }
    }

    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ":")
        guard pieces.count == 3,
              let hours = Double(pieces[0]),
              let minutes = Double(pieces[1]),
              let seconds = Double(pieces[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}

