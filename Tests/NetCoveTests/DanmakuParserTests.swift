import XCTest
@testable import NetCove

final class DanmakuParserTests: XCTestCase {

    func testParseBilibiliXML() {
        let xml = """
        <i><d p="1.5,1,25,16777215,0,0,0,0">first &amp; one</d>
        <d p="3.0,5,25,16711680,0,0,0,0">top comment</d></i>
        """
        let comments = DanmakuParser.parse(data: Data(xml.utf8), format: .xml)
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].time, 1.5, accuracy: 0.001)
        XCTAssertEqual(comments[0].text, "first & one")
        XCTAssertEqual(comments[0].mode, .scrolling)
        XCTAssertEqual(comments[1].mode, .top)
        XCTAssertEqual(comments[1].colorHex, "#FF0000")
    }

    func testLaneAllocationAvoidsOverlap() {
        let scheduler = DanmakuScheduler(laneCount: 2)
        scheduler.load([
            DanmakuComment(time: 1, text: "a", mode: .scrolling, colorHex: "#FFFFFF", fontSize: 22),
            DanmakuComment(time: 1.1, text: "b", mode: .scrolling, colorHex: "#FFFFFF", fontSize: 22),
            DanmakuComment(time: 1.2, text: "c", mode: .scrolling, colorHex: "#FFFFFF", fontSize: 22)
        ])
        let active = scheduler.active(at: 1.2, window: 0.5)
        XCTAssertEqual(active.count, 3)
        // 前两条应在不同轨道，第三条因两轨都占用而复用较早的一条
        XCTAssertNotEqual(active[0].lane, active[1].lane)
    }
}
