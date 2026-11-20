import XCTest
@testable import NetCove

final class RexModPackageTests: XCTestCase {

    /// 与 tools/pack_module.py 的规范化结果逐字节一致的测试向量
    private let fixtureManifest = RexModManifest(
        id: "tv.netcove.test.fixture",
        name: "Fixture",
        version: "1.2.3",
        author: nil,
        entry: "main.js",
        capabilities: [.http, .storage],
        signature: "deadbeef"
    )

    private let expectedCanonical = #"{"author":null,"capabilities":["http","storage"],"entry":"main.js","id":"tv.netcove.test.fixture","name":"Fixture","version":"1.2.3"}"#

    private let expectedDigest = "d78f1b9b6c7b9906acb02edb5637fcbfd3ecb8232aed295484e0d39878cb77b2"

    func testCanonicalManifestMatchesPython() {
        let data = RexModPackage.canonicalManifest(fixtureManifest)
        XCTAssertEqual(String(data: data, encoding: .utf8), expectedCanonical)
    }

    func testDigestMatchesPython() {
        let files = ["main.js": Data("globalThis.ping=function(){return 'pong'};".utf8)]
        let digest = RexModPackage.digest(manifest: fixtureManifest, files: files)
        XCTAssertEqual(digest, expectedDigest)
    }

    func testDigestIgnoresSignatureField() {
        var signed = fixtureManifest
        signed.signature = "feedface"
        let files = ["main.js": Data("globalThis.ping=function(){return 'pong'};".utf8)]
        XCTAssertEqual(RexModPackage.digest(manifest: signed, files: files), expectedDigest)
    }
}
