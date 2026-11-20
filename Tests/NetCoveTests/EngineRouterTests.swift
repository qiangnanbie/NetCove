import XCTest
@testable import NetCove

final class EngineRouterTests: XCTestCase {

    private func probe(hdr: Bool = false, dv: Bool = false, dovi: Int? = nil, fps: Double = 24) -> PlaybackProbe {
        PlaybackProbe(width: 1920, height: 1080, frameRate: fps, hasHDR: hdr,
                      hasDolbyVision: dv, doviProfile: dovi, isMP4Container: true,
                      hasCompleteMediaInfo: true, origin: .library)
    }

    func testMP4H264UsesAVPlayer() {
        let router = EngineRouter()
        XCTAssertEqual(router.decide(for: probe(), container: "mp4", codec: "h264"), .avPlayer)
    }

    func testMKVForcesFFmpeg() {
        let router = EngineRouter()
        XCTAssertEqual(router.decide(for: probe(), container: "mkv", codec: "h264"), .ffmpeg)
    }

    func testDolbyVisionProfile5RequiresFFmpeg() {
        let router = EngineRouter()
        XCTAssertEqual(router.decide(for: probe(hdr: true, dv: true, dovi: 5),
                                     container: "mp4", codec: "hevc"), .ffmpeg)
    }

    func testDolbyVisionProfile8CanUseSystem() {
        let router = EngineRouter()
        XCTAssertEqual(router.decide(for: probe(hdr: true, dv: true, dovi: 8),
                                     container: "mp4", codec: "hevc"), .avPlayer)
    }

    func testHighFrameRateUsesFFmpeg() {
        let router = EngineRouter()
        XCTAssertEqual(router.decide(for: probe(fps: 120), container: "mp4", codec: "h264"), .ffmpeg)
    }
}
