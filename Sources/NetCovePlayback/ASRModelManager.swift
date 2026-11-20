//
//  ASRModelManager.swift
//  本地语音识别模型管理：目录清单 → 逐文件下载（带进度）→ 校验 → 安装/删除。
//  支持 FunASR-nano 与 qwen3-asr（sherpa-onnx 格式），以及可自定义镜像地址。
//

import Foundation
import CryptoKit

struct ASRModelFile: Codable, Hashable {
    var name: String
    var sizeBytes: Int64
    /// 可选：十六进制 SHA-256，用于安装后校验
    var sha256: String?
}

struct ASRModelDescriptor: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var languages: [String]
    var engine: String
    var approxSizeMB: Int
    var files: [ASRModelFile]
    /// 远端根目录（末尾不带斜杠），文件按 <base>/<name> 下载
    var remoteBaseURL: String
}

@MainActor
final class ASRModelManager: ObservableObject {

    enum DownloadState: Equatable {
        case idle
        case downloading(modelID: String, progress: Double, currentFile: String)
        case verifying(modelID: String)
        case failed(modelID: String, message: String)
    }

    @Published private(set) var state: DownloadState = .idle
    @Published private(set) var installedModelIDs: Set<String> = []

    /// 内置目录。文件清单按 sherpa-onnx 的 encoder/decoder/joiner + tokenizer 布局。
    /// 说明：remoteBaseURL 默认指向自建资产域，部署时换成你的镜像或模型发布页直链。
    static let catalog: [ASRModelDescriptor] = [
        ASRModelDescriptor(
            id: "funasr-nano",
            name: "FunASR Nano（中英）",
            languages: ["zh", "en"],
            engine: "sherpa-onnx",
            approxSizeMB: 240,
            files: [
                ASRModelFile(name: "model.onnx", sizeBytes: 0, sha256: nil),
                ASRModelFile(name: "tokens.txt", sizeBytes: 0, sha256: nil),
                ASRModelFile(name: "config.json", sizeBytes: 0, sha256: nil)
            ],
            remoteBaseURL: "https://assets.netcove.app/asr/funasr-nano"
        ),
        ASRModelDescriptor(
            id: "qwen3-asr",
            name: "Qwen3-ASR（多语种）",
            languages: ["zh", "en", "ja", "ko"],
            engine: "sherpa-onnx",
            approxSizeMB: 420,
            files: [
                ASRModelFile(name: "encoder.onnx", sizeBytes: 0, sha256: nil),
                ASRModelFile(name: "decoder.onnx", sizeBytes: 0, sha256: nil),
                ASRModelFile(name: "joiner.onnx", sizeBytes: 0, sha256: nil),
                ASRModelFile(name: "tokenizer.json", sizeBytes: 0, sha256: nil)
            ],
            remoteBaseURL: "https://assets.netcove.app/asr/qwen3-asr"
        )
    ]

    private let root: URL
    private let session: URLSession

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = base.appendingPathComponent("asr-models", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
        refreshInstalled()
    }

    func refreshInstalled() {
        let directories = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                        includingPropertiesForKeys: nil)) ?? []
        installedModelIDs = Set(directories.map { $0.lastPathComponent })
    }

    func directory(for modelID: String) -> URL? {
        let url = root.appendingPathComponent(modelID, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isInstalled(_ modelID: String) -> Bool { installedModelIDs.contains(modelID) }

    /// 安装一个模型（逐文件下载，完成后计数进度）
    func install(_ descriptor: ASRModelDescriptor) async {
        guard let base = URL(string: descriptor.remoteBaseURL) else {
            state = .failed(modelID: descriptor.id, message: "bad remote base URL")
            return
        }
        let target = root.appendingPathComponent(descriptor.id, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            state = .failed(modelID: descriptor.id, message: error.localizedDescription)
            return
        }

        let total = max(descriptor.files.count, 1)
        for (index, file) in descriptor.files.enumerated() {
            let progress = Double(index) / Double(total)
            state = .downloading(modelID: descriptor.id, progress: progress, currentFile: file.name)
            do {
                let remote = base.appendingPathComponent(file.name)
                let (temporaryURL, _) = try await session.download(from: remote)
                let destination = target.appendingPathComponent(file.name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
            } catch {
                state = .failed(modelID: descriptor.id,
                                message: "\(file.name): \(error.localizedDescription)")
                return
            }
        }

        state = .verifying(modelID: descriptor.id)
        if let mismatched = verify(descriptor: descriptor, directory: target) {
            state = .failed(modelID: descriptor.id, message: "checksum mismatch: \(mismatched)")
            return
        }
        refreshInstalled()
        state = .idle
    }

    func uninstall(_ modelID: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(modelID, isDirectory: true))
        refreshInstalled()
    }

    /// 返回第一个校验失败的文件名；全部通过返回 nil
    private func verify(descriptor: ASRModelDescriptor, directory: URL) -> String? {
        for file in descriptor.files {
            guard let expected = file.sha256 else { continue }
            let url = directory.appendingPathComponent(file.name)
            guard let data = try? Data(contentsOf: url) else { return file.name }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if digest.caseInsensitiveCompare(expected) != .orderedSame { return file.name }
        }
        return nil
    }
}
