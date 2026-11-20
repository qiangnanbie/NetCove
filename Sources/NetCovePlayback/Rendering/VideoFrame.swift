//
//  VideoFrame.swift
//  与解码器解耦的帧描述：FFmpeg 解出的 AVFrame 通过它交给渲染层，
//  渲染层因此不需要依赖 Libav* 就能编译。
//

import Foundation
import CoreVideo

struct VideoFrameDescriptor {
    enum PixelFormat: Int {
        case nv12 = 0        // 8bit 4:2:0 双平面（Y + interleaved UV）
        case yuv420p10 = 1   // 10bit 三平面
        case p010 = 2        // 10bit 双平面（HDR/DV 常见）
        case bgra = 3
    }

    enum ColorPrimaries: Int {
        case bt709 = 0
        case bt2020 = 1
        case smpte432 = 2   // Display P3
    }

    enum TransferFunction: Int {
        case sdr = 0
        case hlg = 1
        case pq = 2
        case iptpqc2 = 3    // Dolby Vision P5
    }

    var width: Int
    var height: Int
    var pixelFormat: PixelFormat
    var planes: [UnsafeMutableRawPointer?]
    var strides: [Int]
    var primaries: ColorPrimaries = .bt709
    var transfer: TransferFunction = .sdr
    var dolbyVision: DolbyVisionInfo?
    var presentationTime: Double = 0

    var isHDR: Bool { transfer == .pq || transfer == .hlg || dolbyVision != nil }
}

/// 能提供 Metal 渲染器的引擎（FFmpeg 路径实现；AVPlayer 路径不实现）
protocol MetalRendererProviding: AnyObject {
    var metalRenderer: MetalVideoRenderer? { get }
}

/// 渲染层接口（Metal 实现见 MetalVideoRenderer）
protocol VideoFrameRenderer: AnyObject {
    func prepare(probe: PlaybackProbe) throws
    func render(_ frame: VideoFrameDescriptor)
    func flush()
}

enum RenderError: LocalizedError {
    case metalUnavailable
    case pipelineCompilation(String)
    case textureCreation
    case unsupportedPixelFormat(VideoFrameDescriptor.PixelFormat)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: return "Metal is not available on this device."
        case .pipelineCompilation(let message): return "Shader compilation failed: \(message)"
        case .textureCreation: return "Cannot create a video texture."
        case .unsupportedPixelFormat(let format): return "Unsupported pixel format: \(format)"
        }
    }
}
