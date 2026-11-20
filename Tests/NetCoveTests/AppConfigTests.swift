import XCTest
@testable import NetCove

final class AppConfigTests: XCTestCase {

    func testBundleIdentity() {
        let config = AppConfig()
        XCTAssertEqual(config.bundleIdentifier.isEmpty, false)
        XCTAssertTrue(config.userAgent.hasPrefix("NetCove/"))
    }

    func testEndpointMethodsAndDomains() {
        XCTAssertEqual(Endpoint.metadata.method, "GET")
        XCTAssertEqual(Endpoint.catalogMatch.method, "POST")
        XCTAssertTrue(Endpoint.nativeExchange.isAuthDomain)
        XCTAssertFalse(Endpoint.metadata.isAuthDomain)
    }

    func testAllEndpointsHaveAbsolutePaths() {
        let endpoints: [Endpoint] = [.emailLogin, .emailCode, .emailVerify, .tokenRefresh,
                                     .sessionLogout, .passkeyList, .passkeyRemove, .nativeExchange,
                                     .metadata, .searchMetadata, .playbackMetadata, .catalogMatch,
                                     .catalogTitleHints, .aiSearch, .integrations, .notifications,
                                     .supportFeedback]
        XCTAssertEqual(endpoints.count, 17)
        for endpoint in endpoints {
            XCTAssertTrue(endpoint.path.hasPrefix("/"), "bad path: \(endpoint.path)")
        }
    }

    func testFeatureAccessIsUnlimited() {
        let features = FeatureAccess()
        XCTAssertNil(features.libraryLimit)
        XCTAssertNil(features.environmentLimit)
        XCTAssertNil(features.dailyPlaybackLimit)
    }
}
