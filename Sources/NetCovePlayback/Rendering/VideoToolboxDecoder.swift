//
//  VideoToolboxDecoder.swift
//  硬解：VTDecompressionSession 输出 CVPixelBuffer（Metal 兼容），交给零拷贝渲染。
//  优势：硬解 + 零拷贝，CPU 占用与功耗都比软解 + 纹理上传低一个量级。
//  软解回落：解码器不支持该 profile 时自动回退（见 FFmpegPlaybackEngine）。
//

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

final class VideoToolboxDecoder {

    struct Configuration {
        var codecType: CMVideoCodecType
        var formatDescription: CMFormatDescription
        var width: Int
        var height: Int
        var prefersTenBit: Bool
    }

    private var session: VTDecompressionSession?
    private(set) var configuration: Configuration?
    private(set) var isHardwareAccelerated = false

    /// 解码回调（在主线程外、由 VideoToolbox 决定）
    var onFrame: ((CVPixelBuffer) -> Void)?

    deinit { invalidate() }

    func configure(_ config: Configuration) throws {
        invalidate()
        configuration = config

        var decoderSpec: [CFString: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ]
        // 不希望系统悄悄回落到软解时打开这个开关（这里允许回落，便于兼容）
        decoderSpec[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder] = false

        let pixelFormat: OSType = config.prefersTenBit
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferWidthKey: config.width,
            kCVPixelBufferHeightKey: config.height
        ]

        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer, let refCon else { return }
                let decoder = Unmanaged<VideoToolboxDecoder>.fromOpaque(refCon).takeUnretainedValue()
                decoder.onFrame?(imageBuffer)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: config.formatDescription,
            decoderSpecification: decoderSpec as CFDictionary,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &newSession
        )
        guard status == noErr, let newSession else {
            throw DecoderError.sessionCreation(status)
        }
        session = newSession

        var hardware: CFBoolean?
        VTSessionCopyProperty(newSession,
                              key: kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as CFString,
                              allocator: kCFAllocatorDefault,
                              valueOut: &hardware)
        isHardwareAccelerated = (hardware as? Bool) ?? false
    }

    /// 提交一个压缩 sample（AVCC/hvcC 格式，长度前缀 4 字节）
    func decode(_ sampleBuffer: CMSampleBuffer) throws {
        guard let session else { throw DecoderError.notConfigured }
        let flags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression, ._EnableTemporalProcessing]
        var flagsOut: VTDecodeInfoFlags = []
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sampleBuffer, flags: flags, infoFlagsOut: &flagsOut,
            outputHandler: { [weak self] status, _, imageBuffer, _, _ in
                guard status == noErr, let imageBuffer else { return }
                self?.onFrame?(imageBuffer)
            }
        )
        guard status == noErr else { throw DecoderError.decode(status) }
    }

    func flush() {
        guard let session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    // MARK: - 格式描述构造（供 FFmpeg extradata 使用）

    /// avcC（AVCC）→ CMFormatDescription
    static func h264FormatDescription(avcC: Data) -> CMFormatDescription? {
        var spsList: [[UInt8]] = []
        var ppsList: [[UInt8]] = []
        let bytes = [UInt8](avcC)
        guard bytes.count > 7 else { return nil }
        var index = 5
        let numSPS = Int(bytes[index] & 0x1F)
        index += 1
        for _ in 0..<numSPS {
            guard index + 2 <= bytes.count else { return nil }
            let length = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
            index += 2
            guard index + length <= bytes.count else { return nil }
            spsList.append(Array(bytes[index..<(index + length)]))
            index += length
        }
        guard index < bytes.count else { return nil }
        let numPPS = Int(bytes[index])
        index += 1
        for _ in 0..<numPPS {
            guard index + 2 <= bytes.count else { return nil }
            let length = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
            index += 2
            guard index + length <= bytes.count else { return nil }
            ppsList.append(Array(bytes[index..<(index + length)]))
            index += length
        }
        guard !spsList.isEmpty, !ppsList.isEmpty else { return nil }

        var description: CMFormatDescription?
        let allSets = spsList + ppsList
        let sizes = allSets.map { $0.count }
        let status = allSets.withUnsafePointersAndSizes { pointers, lengths in
            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers,
                parameterSetSizes: lengths,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &description)
        }
        return status == noErr ? description : nil
    }

    /// hvcC（HEVC）→ CMFormatDescription
    static func hevcFormatDescription(hvcC: Data) -> CMFormatDescription? {
        let bytes = [UInt8](hvcC)
        guard bytes.count > 23 else { return nil }
        var index = 23 // numOfArrays 在偏移 22，参数集从 23 开始
        var parameterSets: [[UInt8]] = []
        while index + 3 <= bytes.count {
            let nalType = bytes[index] & 0x3F
            let numNalus = (Int(bytes[index + 1]) << 8) | Int(bytes[index + 2])
            index += 3
            for _ in 0..<numNalus {
                guard index + 2 <= bytes.count else { return nil }
                let length = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
                index += 2
                guard index + length <= bytes.count else { return nil }
                // VPS(32) / SPS(33) / PPS(34) 才需要传给格式描述
                if nalType == 32 || nalType == 33 || nalType == 34 {
                    parameterSets.append(Array(bytes[index..<(index + length)]))
                }
                index += length
            }
        }
        guard !parameterSets.isEmpty else { return nil }

        var description: CMFormatDescription?
        let status = parameterSets.withUnsafePointersAndSizes { pointers, lengths in
            CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: pointers,
                parameterSetSizes: lengths,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &description)
        }
        return status == noErr ? description : nil
    }
}

extension Array where Element == [UInt8] {
    /// 把 [[UInt8]] 转成 ([UnsafePointer<UInt8>], [Int])，回调期间指针有效
    func withUnsafePointersAndSizes<R>(_ body: ([UnsafePointer<UInt8>], [Int]) -> R) -> R {
        var pointers: [UnsafePointer<UInt8>] = []
        var lengths: [Int] = []
        func walk(_ index: Int) -> R {
            if index == count { return body(pointers, lengths) }
            return self[index].withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress { pointers.append(base) }
                lengths.append(buffer.count)
                return walk(index + 1)
            }
        }
        return walk(0)
    }
}

enum DecoderError: LocalizedError {
    case sessionCreation(OSStatus)
    case decode(OSStatus)
    case notConfigured
    case sampleBufferCreation

    var errorDescription: String? {
        switch self {
        case .sessionCreation(let status): return "VideoToolbox session failed (\(status))"
        case .decode(let status): return "Hardware decode failed (\(status))"
        case .notConfigured: return "Decoder isn't configured"
        case .sampleBufferCreation: return "Cannot build a sample buffer"
        }
    }
}
