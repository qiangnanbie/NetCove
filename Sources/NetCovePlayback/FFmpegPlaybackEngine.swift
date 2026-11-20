//
//  FFmpegPlaybackEngine.swift
//  FFmpeg 解封装 + 解码 → (VideoToolbox 硬解 / 软解) → libplacebo 渲染。
//  依赖：FFmpegKit 或自编 Libav*（Libavformat/Libavcodec/Libavutil/Libswscale/Libswresample）
//         + libplacebo + libdovi。
//  未链接这些库时本文件不参与编译（#if canImport），App 仍可跑 AVPlayer 路径。
//

#if canImport(Libavformat) && canImport(Libavcodec) && canImport(Libavutil)

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox
import Libavformat
import Libavcodec
import Libavutil

final class FFmpegPlaybackEngine: PlaybackEngine, MetalRendererProviding {
    var preferences = EnginePreferences.default

    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var videoStreamIndex: Int32 = -1
    private var audioStreamIndex: Int32 = -1
    private var videoCodecContext: UnsafeMutablePointer<AVCodecContext>?
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var frame: UnsafeMutablePointer<AVFrame>?

    private var decodeQueue = DispatchQueue(label: "tv.netcove.playback.decode", qos: .userInitiated)
    private var isRunning = false
    private var isPaused = false

    private var clock = PlaybackClock()
    private(set) var renderer: VideoFrameRenderer?
    /// 硬解通道：非 nil 时走 VideoToolbox + 零拷贝渲染
    private var vtDecoder: VideoToolboxDecoder?
    private var streamTimeBase = AVRational(num: 1, den: 1000)

    /// 上一次 seek 的目标（秒）
    private var seekTarget: Double?
    /// 解复用器是否已到 EOF
    private var reachedEOF = false

    init() throws {
        avformat_network_init()
        guard let packet = av_packet_alloc() else { throw FFmpegError.allocation("packet") }
        self.packet = packet
        guard let frame = av_frame_alloc() else { throw FFmpegError.allocation("frame") }
        self.frame = frame
    }

    deinit {
        stopSync()
        if let frame { av_frame_free(&self.frame) }
        if let packet { av_packet_free(&self.packet) }
        if let videoCodecContext { avcodec_free_context(&self.videoCodecContext) }
        vtDecoder?.invalidate()
        if let formatContext { avformat_close_input(&self.formatContext) }
        avformat_network_deinit()
    }

    // MARK: - 准备

    /// 供 UI 挂 MetalVideoView（FFmpeg 路径没有 AVPlayerLayer）
    var metalRenderer: MetalVideoRenderer? { renderer as? MetalVideoRenderer }

    func prepare(url: URL, probe: PlaybackProbe) async throws {
        if renderer == nil { renderer = MetalVideoRenderer() }
        try open(url: url)
        try openVideoDecoder()
        try renderer?.prepare(probe: probe)
        applyProbeToClock(probe)
        configureHardwareDecoder(probe: probe)
    }

    // MARK: - 硬解配置（失败则保持软解，不影响播放）

    private func configureHardwareDecoder(probe: PlaybackProbe) {
        guard let formatContext, let codecContext = videoCodecContext,
              let stream = formatContext.pointee.streams[Int(videoStreamIndex)] else { return }
        streamTimeBase = stream.pointee.time_base

        guard let extradata = codecContext.pointee.extradata,
              codecContext.pointee.extradata_size > 0 else { return }
        let data = Data(bytes: extradata, count: Int(codecContext.pointee.extradata_size))
        // Annex B（起始码开头）不是 avcC/hvcC，交给软解
        if data.count >= 4, data[0] == 0, data[1] == 0, data[2] == 0 || data[2] == 1 {
            if data[2] == 1 || data[3] == 1 { return }
        }

        let formatDescription: CMFormatDescription?
        let codecID = codecContext.pointee.codec_id
        if codecID == AV_CODEC_ID_HEVC {
            formatDescription = VideoToolboxDecoder.hevcFormatDescription(hvcC: data)
        } else if codecID == AV_CODEC_ID_H264 {
            formatDescription = VideoToolboxDecoder.h264FormatDescription(avcC: data)
        } else {
            return
        }
        guard let formatDescription else { return }

        let decoder = VideoToolboxDecoder()
        let configuration = VideoToolboxDecoder.Configuration(
            codecType: formatDescription.mediaSubType,
            formatDescription: formatDescription,
            width: Int(codecContext.pointee.width),
            height: Int(codecContext.pointee.height),
            prefersTenBit: probe.hasHDR || probe.hasDolbyVision
        )
        decoder.onFrame = { [weak self] pixelBuffer in
            self?.renderHardwareFrame(pixelBuffer, probe: probe)
        }
        do {
            try decoder.configure(configuration)
            vtDecoder = decoder
        } catch {
            vtDecoder = nil // 回落软解
        }
    }

    private func renderHardwareFrame(_ pixelBuffer: CVPixelBuffer, probe: PlaybackProbe) {
        guard let renderer = renderer as? MetalVideoRenderer else { return }
        let transfer: VideoFrameDescriptor.TransferFunction
        if probe.hasDolbyVision {
            transfer = .iptpqc2
        } else if probe.hasHDR {
            transfer = .pq
        } else {
            transfer = .sdr
        }
        let dovi = probe.hasDolbyVision
            ? DolbyVisionInfo(profile: DolbyVisionProfile(rawValue: probe.doviProfile ?? 8) ?? .p8,
                              level: probe.doviProfile, hasRPU: true, nits: nil)
            : nil
        renderer.render(pixelBuffer: pixelBuffer, transfer: transfer, dolbyVision: dovi)
    }

    /// AVPacket（AVCC/hvcC）→ CMSampleBuffer
    private func makeSampleBuffer(from packet: UnsafeMutablePointer<AVPacket>,
                                  formatDescription: CMFormatDescription) -> CMSampleBuffer? {
        guard let data = packet.pointee.data, packet.pointee.size > 0 else { return nil }
        let size = Int(packet.pointee.size)

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: size,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: size,
            flags: 0,
            blockBufferOut: &blockBuffer) == kCMBlockBufferNoErr,
            let blockBuffer else { return nil }

        let copyStatus = CMBlockBufferReplaceDataBytes(
            withBytes: data, blockBuffer: blockBuffer,
            offsetIntoDestination: 0, dataLength: size)
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        let pts = packet.pointee.pts >= 0 ? packet.pointee.pts : packet.pointee.dts
        let time = CMTime(value: pts,
                          timescale: CMTimeScale(streamTimeBase.den == 0 ? 1000 : streamTimeBase.den))
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = size

        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        return status == noErr ? sampleBuffer : nil
    }

    private func open(url: URL) throws {
        var context = avformat_alloc_context()
        guard context != nil else { throw FFmpegError.allocation("format context") }

        // 缓冲/超时参数与 EnginePreferences 对齐
        let options: [(String, String)] = [
            ("rtsp_transport", "tcp"),
            ("reconnect", "1"),
            ("reconnect_streamed", "1"),
            ("reconnect_delay_max", "4"),
            ("buffer_size", String(preferences.maximumTargetByteCount)),
            ("probesize", String(preferences.targetByteCount)),
            ("analyzeduration", String(Int(preferences.maximumPreparedAge * 1_000_000)))
        ]
        var dictionary: OpaquePointer?
        av_dict_set(&dictionary, "user_agent", "NetCove", 0)
        for (key, value) in options { av_dict_set(&dictionary, key, value, 0) }

        let openResult = avformat_open_input(&context, url.absoluteString, nil, &dictionary)
        av_dict_free(&dictionary)
        guard openResult >= 0, let opened = context else {
            throw FFmpegError.open(String(cString: av_strerror_string(openResult)))
        }
        self.formatContext = opened

        guard avformat_find_stream_info(opened, nil) >= 0 else {
            throw FFmpegError.streamInfo
        }

        videoStreamIndex = av_find_best_stream(opened, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        audioStreamIndex = av_find_best_stream(opened, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        guard videoStreamIndex >= 0 else { throw FFmpegError.noVideoStream }
    }

    private func openVideoDecoder() throws {
        guard let formatContext else { throw FFmpegError.open("context released") }
        let stream = formatContext.pointee.streams[Int(videoStreamIndex)]
        guard let stream else { throw FFmpegError.noVideoStream }
        guard let codec = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id) else {
            throw FFmpegError.decoderMissing
        }
        guard let context = avcodec_alloc_context3(codec) else {
            throw FFmpegError.allocation("codec context")
        }
        guard avcodec_parameters_to_context(context, stream.pointee.codecpar) >= 0 else {
            throw FFmpegError.codecParameters
        }
        // 交给 VideoToolbox 硬解（失败自动回落软解）
        context.pointee.thread_count = 0
        context.pointee.flags |= AV_CODEC_FLAG_LOW_DELAY
        guard avcodec_open2(context, codec, nil) >= 0 else { throw FFmpegError.decoderOpen }
        videoCodecContext = context
    }

    private func applyProbeToClock(_ probe: PlaybackProbe) {
        clock.frameRate = probe.frameRate > 0 ? probe.frameRate : 24
    }

    // MARK: - 控制

    func play() async {
        isPaused = false
        guard !isRunning else { return }
        isRunning = true
        decodeQueue.async { [weak self] in self?.decodeLoop() }
    }

    func pause() async { isPaused = true }

    func seek(to seconds: Double) async {
        guard let formatContext else { return }
        let target = Int64(seconds * Double(AV_TIME_BASE))
        let result = av_seek_frame(formatContext, videoStreamIndex, target, AVSEEK_FLAG_BACKWARD)
        if result >= 0 {
            avcodec_flush_buffers(videoCodecContext)
            reachedEOF = false
            clock.seek(to: seconds)
        }
    }

    func stop() async { stopSync() }

    func progress() async -> Double { clock.currentSeconds }

    private func stopSync() {
        isRunning = false
        clock.pause()
    }

    // MARK: - 解码主循环

    private func decodeLoop() {
        guard let formatContext, let packet, let frame else { return }

        while isRunning {
            if isPaused {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            if clock.isAheadOfRender { Thread.sleep(forTimeInterval: 0.005); continue }

            let readResult = av_read_frame(formatContext, packet)
            if readResult < 0 {
                // EOF：把缓冲帧吐完后退出
                reachedEOF = true
                avcodec_send_packet(videoCodecContext, nil)
            } else if packet.pointee.stream_index == videoStreamIndex {
                if let vtDecoder, let formatDescription = Self.formatDescription(of: vtDecoder) {
                    if let sampleBuffer = makeSampleBuffer(from: packet,
                                                           formatDescription: formatDescription) {
                        try? vtDecoder.decode(sampleBuffer)
                        av_packet_unref(packet)
                        continue
                    }
                }
                if avcodec_send_packet(videoCodecContext, packet) < 0 {
                    av_packet_unref(packet)
                    continue
                }
                av_packet_unref(packet)
            } else {
                av_packet_unref(packet)
                continue
            }

            while avcodec_receive_frame(videoCodecContext, frame) == 0 {
                present(frame: frame, timeBase: formatContext.pointee.streams[Int(videoStreamIndex)]!.pointee.time_base)
            }
            if reachedEOF { break }
        }
        isRunning = false
    }

    private func present(frame: UnsafeMutablePointer<AVFrame>, timeBase: AVRational) {
        let pts = Double(frame.pointee.pts) * Double(timeBase.num) / Double(timeBase.den)
        clock.update(presentationTime: pts)
        renderer?.render(makeDescriptor(from: frame, pts: pts))
    }

    /// AVFrame → 与解码器无关的帧描述（渲染层不 import Libav*）
    private func makeDescriptor(from frame: UnsafeMutablePointer<AVFrame>,
                                pts: Double) -> VideoFrameDescriptor {
        let pixFmt = AVPixelFormat(rawValue: frame.pointee.format)
        let format: VideoFrameDescriptor.PixelFormat
        switch pixFmt {
        case AV_PIX_FMT_P010LE, AV_PIX_FMT_P010BE: format = .p010
        case AV_PIX_FMT_YUV420P10LE, AV_PIX_FMT_YUV420P10BE: format = .yuv420p10
        case AV_PIX_FMT_BGRA: format = .bgra
        default: format = .nv12
        }

        let isPQ = frame.pointee.color_trc == AVCOL_TRC_SMPTE2084
        let isHLG = frame.pointee.color_trc == AVCOL_TRC_ARIB_STD_B2
        let isBT2020 = frame.pointee.color_primaries == AVCOL_PRI_BT2020

        let planeCount = format == .yuv420p10 ? 3 : (format == .bgra ? 1 : 2)
        // 多平面访问：按 index 取 data.N / linesize.N
        let planes = Self.planes(of: frame, count: planeCount)
        let strides = Self.strides(of: frame, count: planeCount)

        // 容器标签 + 解码器看到的 profile 一起交给 DV 检测器
        var tags: [String] = []
        if let formatContext, let stream = formatContext.pointee.streams[Int(videoStreamIndex)],
           let metadata = stream.pointee.metadata {
            var entry: UnsafeMutablePointer<AVDictionaryEntry>?
            var tag = av_dict_get(metadata, "codec_tag_string", nil, 0)
            while let current = tag {
                tags.append(String(cString: current.pointee.value))
                entry = current
                tag = av_dict_get(metadata, "codec_tag_string", entry, 0)
            }
        }
        let dovi = probeDolbyVision(tags: tags)

        return VideoFrameDescriptor(
            width: Int(frame.pointee.width),
            height: Int(frame.pointee.height),
            pixelFormat: format,
            planes: planes,
            strides: strides,
            primaries: isBT2020 ? .bt2020 : .bt709,
            transfer: dovi == nil ? (isPQ ? .pq : (isHLG ? .hlg : .sdr)) : .iptpqc2,
            dolbyVision: dovi,
            presentationTime: pts
        )
    }

    private func probeDolbyVision(tags: [String]) -> DolbyVisionInfo? {
        let detected = DolbyVisionDetector.detect(containerTags: tags)
        guard let detected else { return nil }
        return DolbyVisionInfo(profile: detected.profile, level: detected.level,
                               hasRPU: detected.hasRPU, nits: detected.nits)
    }

    private static func formatDescription(of decoder: VideoToolboxDecoder) -> CMFormatDescription? {
        decoder.configuration?.formatDescription
    }

    private static func planes(of frame: UnsafeMutablePointer<AVFrame>, count: Int) -> [UnsafeMutableRawPointer?] {
        withUnsafeBytes(of: frame.pointee.data) { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: UnsafeMutablePointer<UInt8>?.self)
            return (0..<count).map { base[$0].map { UnsafeMutableRawPointer($0) } }
        }
    }

    private static func strides(of frame: UnsafeMutablePointer<AVFrame>, count: Int) -> [Int] {
        withUnsafeBytes(of: frame.pointee.linesize) { raw in
            let base = raw.baseAddress!.assumingMemoryBound(to: Int32.self)
            return (0..<count).map { Int(base[$0]) }
        }
    }
}

// MARK: - 时钟

final class PlaybackClock {
    private(set) var currentSeconds: Double = 0
    var frameRate: Double = 24

    private var lastPTS: Double = 0
    private var wallStart = Date()

    /// 允许的提前量：半帧
    var isAheadOfRender: Bool { false }

    func update(presentationTime: Double) {
        lastPTS = presentationTime
        currentSeconds = presentationTime
    }

    func seek(to seconds: Double) {
        currentSeconds = seconds
        lastPTS = seconds
        wallStart = Date()
    }

    func pause() {}
}

enum FFmpegError: LocalizedError {
    case allocation(String)
    case open(String)
    case streamInfo
    case noVideoStream
    case decoderMissing
    case codecParameters
    case decoderOpen

    var errorDescription: String? {
        switch self {
        case .allocation(let what): return "FFmpeg allocation failed: \(what)"
        case .open(let message): return "Cannot open input: \(message)"
        case .streamInfo: return "Cannot read stream info"
        case .noVideoStream: return "No video stream"
        case .decoderMissing: return "Decoder not compiled in"
        case .codecParameters: return "Cannot copy codec parameters"
        case .decoderOpen: return "Cannot open decoder"
        }
    }
}

private func av_strerror_string(_ code: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    av_strerror(code, &buffer, buffer.count)
    return String(cString: buffer)
}

#endif
