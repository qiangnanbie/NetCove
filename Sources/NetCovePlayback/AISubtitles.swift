//
//  AISubtitles.swift
//  本机 AI 字幕：音频轨抽取 → 语音识别 → 时间轴对齐 → 生成字幕轨。
//  两条路线：
//    1) Speech.framework（系统识别，免费、离线可用，精度一般）
//    2) sherpa-onnx + FunASR-nano / qwen3-asr（权重运行期下载，精度高，纯本地）
//

import Foundation
import Speech
import AVFoundation

struct AISubtitleService {
    enum Backend {
        case system          // Speech.framework
        case sherpaOnnx      // onnxruntime + sherpa-onnx
    }

    var backend: Backend = .system
    var language: String = "zh-CN"

    /// 从视频里抽一条音轨到临时文件（16k mono PCM，识别器最爱）
    func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AISubtitleError.noAudioTrack
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("netcove-asr-\(UUID().uuidString).m4a")

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(trackOutput)
        reader.startReading()

        // 简化实现：把 PCM 直接写 WAV 头 + 数据
        var pcm = Data()
        while let buffer = trackOutput.copyNextSampleBuffer(),
              let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                        totalLengthOut: &length, dataPointerOut: &pointer)
            if let pointer {
                pcm.append(UnsafeBufferPointer(start: pointer, count: length))
            }
        }
        try WAVWriter.write(pcm: pcm, sampleRate: 16_000, to: output)
        return output
    }

    /// 生成字幕轨（时间轴按识别结果回填）
    func transcribe(videoURL: URL, language: String? = nil) async throws -> [SubtitleCue] {
        let audioURL = try await extractAudio(from: videoURL)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        switch backend {
        case .system:
            return try await transcribeWithSpeech(url: audioURL, language: language ?? self.language)
        case .sherpaOnnx:
            return try SherpaOnnxBridge.shared.transcribe(audioURL: audioURL, language: language ?? self.language)
        }
    }

    private func transcribeWithSpeech(url: URL, language: String) async throws -> [SubtitleCue] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable else {
            throw AISubtitleError.recognizerUnavailable
        }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else { throw AISubtitleError.notAuthorized }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            var cues: [SubtitleCue] = []
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else { return }
                cues = result.bestTranscription.segments.map { segment in
                    SubtitleCue(start: segment.timestamp,
                                end: segment.timestamp + segment.duration,
                                text: segment.substring)
                }
                if result.isFinal {
                    finished = true
                    continuation.resume(returning: cues)
                }
            }
        }
    }
}

enum AISubtitleError: LocalizedError {
    case noAudioTrack
    case recognizerUnavailable
    case notAuthorized
    case sherpaUnavailable

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "This file has no audio track."
        case .recognizerUnavailable: return "Speech recognition is unavailable for this language."
        case .notAuthorized: return "Speech recognition permission was denied."
        case .sherpaUnavailable: return "The on-device ASR model is not installed."
        }
    }
}

enum WAVWriter {
    static func write(pcm: Data, sampleRate: Int, to url: URL) throws {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = channels * (bits / 8)

        data.append("RIFF".data(using: .ascii)!)
        append(UInt32(36 + pcm.count))
        data.append("WAVEfmt ".data(using: .ascii)!)
        append(UInt32(16))
        append(UInt16(1))
        append(channels)
        append(UInt32(sampleRate))
        append(byteRate)
        append(blockAlign)
        append(bits)
        data.append("data".data(using: .ascii)!)
        append(UInt32(pcm.count))
        data.append(pcm)
        try data.write(to: url, options: .atomic)
    }
}

/// sherpa-onnx 桥：模型路径由设置页导入（tokenizer.json / model.onnx / 热词表）
struct SherpaOnnxBridge {
    static let shared = SherpaOnnxBridge()

    /// 优先已安装的模型目录（ASRModelManager 装到 asr-models/<id>）
    func modelDirectory(preferredModelID: String? = nil) -> URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("asr-models")
        guard let base else { return nil }
        if let preferredModelID {
            let candidate = base.appendingPathComponent(preferredModelID, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let installed = (try? FileManager.default.contentsOfDirectory(at: base,
                                                                     includingPropertiesForKeys: nil)) ?? []
        return installed.first { url in
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?
                .contains { $0.pathExtension == "onnx" } ?? false
        }
    }

    func transcribe(audioURL: URL, language: String) throws -> [SubtitleCue] {
        guard let modelDirectory = modelDirectory(),
              FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw AISubtitleError.sherpaUnavailable
        }
        #if canImport(sherpa_onnx)
        // 真正调用 sherpa-onnx C API：创建 recognizer → 喂 16k PCM → 取 segments
        // 这里保留接口，接入后按 segment.start_time / end_time / text 映射成 SubtitleCue
        #endif
        throw AISubtitleError.sherpaUnavailable
    }
}
