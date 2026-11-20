import XCTest
@testable import NetCove

final class SubtitleParserTests: XCTestCase {

    private let srt = """
    1
    00:00:01,000 --> 00:00:03,500
    Hello there.

    2
    00:00:04,000 --> 00:00:06,000
    Second line.
    Continues here.
    """

    func testParseSRT() {
        let cues = SubtitleParser.parseSRT(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "Hello there.")
        XCTAssertEqual(cues[1].text, "Second line.\nContinues here.")
    }

    func testTimestampParsing() {
        XCTAssertEqual(SubtitleParser.parseTimestamp("01:02:03,400") ?? -1, 3723.4, accuracy: 0.001)
        XCTAssertNil(SubtitleParser.parseTimestamp("nonsense"))
    }

    func testFormatDetection() {
        XCTAssertEqual(SubtitleFormat.detect(fileName: "movie.ass"), .ass)
        XCTAssertEqual(SubtitleFormat.detect(fileName: "movie.sup"), .pgs)
        XCTAssertTrue(SubtitleFormat.srt.isTextBased)
        XCTAssertFalse(SubtitleFormat.pgs.isTextBased)
    }
}
