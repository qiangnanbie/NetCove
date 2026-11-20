import XCTest
@testable import NetCove

final class ScrapePipelineTests: XCTestCase {

    func testMovieFileName() {
        let guess = ScrapePipeline.guess(fileName: "The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv")
        XCTAssertEqual(guess.title, "The Matrix")
        XCTAssertEqual(guess.year, 1999)
        XCTAssertEqual(guess.resolution, "1080p")
        XCTAssertNil(guess.season)
    }

    func testEpisodeFileName() {
        let guess = ScrapePipeline.guess(fileName: "Breaking.Bad.S01E02.1080p.WEB-DL.mkv")
        XCTAssertEqual(guess.season, 1)
        XCTAssertEqual(guess.episode, 2)
        XCTAssertEqual(guess.title, "Breaking Bad")
    }

    func testChineseEpisodeFileName() {
        let guess = ScrapePipeline.guess(fileName: "走向共和.第01季第03集.mkv")
        XCTAssertEqual(guess.season, 1)
        XCTAssertEqual(guess.episode, 3)
    }

    func testConfidencePrefersStructuredNames() {
        let structured = ScrapePipeline.guess(fileName: "Dune.2021.2160p.HDR.mkv")
        let bare = ScrapePipeline.guess(fileName: "random recording.mkv")
        XCTAssertGreaterThan(structured.confidence, bare.confidence)
    }
}
