//
//  Danmaku.swift
//  弹幕：B 站 XML / JSON 解析、时间轴调度、防重叠轨道分配。
//

import Foundation
import SwiftUI

struct DanmakuComment: Identifiable, Hashable {
    var id: UUID = UUID()
    var time: TimeInterval
    var text: String
    var mode: Mode
    var colorHex: String
    var fontSize: Int

    enum Mode: Int, Codable {
        case scrolling = 1
        case bottom = 4
        case top = 5
        case reverse = 6
    }
}

enum DanmakuFormat {
    case xml, json
}

enum DanmakuParser {

    static func parse(data: Data, format: DanmakuFormat) -> [DanmakuComment] {
        switch format {
        case .xml: return parseXML(data)
        case .json: return parseJSON(data)
        }
    }

    /// B 站 XML：<d p="time,mode,size,color,timestamp,...">text</d>
    static func parseXML(_ data: Data) -> [DanmakuComment] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var comments: [DanmakuComment] = []

        for block in xml.components(separatedBy: "<d p=\"").dropFirst() {
            guard let quoteEnd = block.firstIndex(of: "\""),
                  let tagEnd = block.range(of: "\">") else { continue }
            let attributes = block[..<quoteEnd].split(separator: ",")
            guard attributes.count >= 4,
                  let time = Double(attributes[0]),
                  let mode = Int(attributes[1]),
                  let size = Int(attributes[2]),
                  let color = Int(attributes[3]) else { continue }

            let textEnd = block.range(of: "</d>")
            let textRange = tagEnd.upperBound..<(textEnd?.lowerBound ?? block.endIndex)
            let raw = String(block[textRange])
            comments.append(DanmakuComment(
                time: time,
                text: decodeEntities(raw),
                mode: DanmakuComment.Mode(rawValue: mode) ?? .scrolling,
                colorHex: String(format: "#%06X", color),
                fontSize: size
            ))
        }
        return comments.sorted { $0.time < $1.time }
    }

    /// 通用 JSON：[{ "time": 1.2, "text": "...", "mode": 1, "color": "#FFFFFF" }]
    static func parseJSON(_ data: Data) -> [DanmakuComment] {
        struct Raw: Decodable {
            let time: Double
            let text: String
            let mode: Int?
            let color: String?
            let size: Int?
        }
        guard let items = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        return items.map {
            DanmakuComment(time: $0.time,
                           text: $0.text,
                           mode: DanmakuComment.Mode(rawValue: $0.mode ?? 1) ?? .scrolling,
                           colorHex: $0.color ?? "#FFFFFF",
                           fontSize: $0.size ?? 22)
        }
        .sorted { $0.time < $1.time }
    }

    private static func decodeEntities(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

/// 时间轴调度 + 轨道分配（同屏不重叠）
final class DanmakuScheduler {
    struct Lanes {
        /// laneIndex → 该轨上一个弹幕的结束时间
        var occupiedUntil: [TimeInterval] = []
    }

    private(set) var comments: [DanmakuComment] = []
    private var cursor = 0
    private var laneState = Lanes()
    private let laneCount: Int

    init(laneCount: Int = 8) {
        self.laneCount = laneCount
        laneState.occupiedUntil = Array(repeating: 0, count: laneCount)
    }

    func load(_ comments: [DanmakuComment]) {
        self.comments = comments.sorted { $0.time < $1.time }
        cursor = 0
        laneState.occupiedUntil = Array(repeating: 0, count: laneCount)
    }

    /// 取出 [time - window, time] 期间该出现的弹幕，并分配轨道
    func active(at time: TimeInterval, window: TimeInterval = 0.25) -> [(comment: DanmakuComment, lane: Int)] {
        var out: [(DanmakuComment, Int)] = []
        while cursor < comments.count, comments[cursor].time <= time + window {
            let comment = comments[cursor]
            cursor += 1
            guard comment.time >= time - 3 else { continue } // 太旧直接丢
            out.append((comment, allocateLane(for: comment)))
        }
        return out
    }

    private func allocateLane(for comment: DanmakuComment) -> Int {
        let occupancy = max(comment.time + 4, comment.time + 6) // 滚动弹幕约 6 秒穿屏
        for lane in 0..<laneCount where laneState.occupiedUntil[lane] <= comment.time {
            laneState.occupiedUntil[lane] = occupancy
            return lane
        }
        // 全满：复用最早释放的轨
        var best = 0
        for lane in 1..<laneCount where laneState.occupiedUntil[lane] < laneState.occupiedUntil[best] {
            best = lane
        }
        laneState.occupiedUntil[best] = occupancy
        return best
    }

    func reset() { load(comments) }
}

/// 弹幕渲染层（SwiftUI 版；正式版建议 Metal/CALayer 批量绘制）
struct DanmakuOverlay: View {
    let items: [(comment: DanmakuComment, lane: Int)]
    let laneHeight: CGFloat = 30
    let topInset: CGFloat = 60

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.comment.id) { entry in
                Text(entry.comment.text)
                    .font(.system(size: CGFloat(entry.comment.fontSize) * 0.85, weight: .semibold))
                    .foregroundStyle(Color(hex: entry.comment.colorHex))
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .offset(y: topInset + CGFloat(entry.lane) * laneHeight)
            }
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
