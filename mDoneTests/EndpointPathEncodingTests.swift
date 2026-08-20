import XCTest
@testable import mDone

/// `APIClient.buildRequest` builds URLs by string concatenation and a bare
/// `URL(string:)`, with no escaping, so any endpoint that interpolates a
/// server-supplied value into its path has to encode it itself.
///
/// This matters most for the OIDC callback, which is the request carrying the
/// authorization code.
final class EndpointPathEncodingTests: XCTestCase {
    func testOrdinaryProviderKeyIsUnchanged() {
        // The common case: Vikunja lowercases the provider name.
        XCTAssertEqual(Endpoint.openIDCallback(provider: "authelia").path, "/api/v1/auth/openid/authelia/callback")
        XCTAssertEqual(Endpoint.openIDCallback(provider: "keycloak-1").path, "/api/v1/auth/openid/keycloak-1/callback")
    }

    func testSlashCannotEscapeThePathSegment() {
        // Without encoding this would POST the authorization code to
        // /api/v1/auth/openid/../../../elsewhere.
        let path = Endpoint.openIDCallback(provider: "a/../../evil").path
        XCTAssertFalse(path.contains("a/"))
        XCTAssertFalse(path.contains(".."))
        XCTAssertEqual(path, "/api/v1/auth/openid/a%2F%2E%2E%2F%2E%2E%2Fevil/callback")
    }

    func testDotsAreEncodedSoTraversalCannotSurvive() {
        XCTAssertFalse(Endpoint.openIDCallback(provider: "..").path.contains(".."))
    }

    func testQueryAndFragmentCannotBeInjected() {
        let path = Endpoint.openIDCallback(provider: "x?a=b#frag").path
        XCTAssertFalse(path.contains("?"))
        XCTAssertFalse(path.contains("#"))
    }

    func testWhitespaceIsEncodedRatherThanProducingANilURL() {
        // URL(string:) returns nil on a raw space, which would surface as a
        // confusing invalidURL rather than a working request.
        XCTAssertFalse(Endpoint.openIDCallback(provider: "two words").path.contains(" "))
    }

    func testEncodedSegmentStillProducesAUsableURL() {
        for key in ["authelia", "a/b", "..", "two words", "ünïcode", ""] {
            let path = Endpoint.openIDCallback(provider: key).path
            XCTAssertNotNil(URL(string: "https://vikunja.example.com" + path), "unusable URL for key \(key)")
        }
    }

    func testUnicodeKeyIsEncoded() {
        let path = Endpoint.openIDCallback(provider: "ünïcode").path
        XCTAssertTrue(path.contains("%"))
        XCTAssertNotNil(URL(string: "https://vikunja.example.com" + path))
    }
}
