import XCTest
@testable import mDone

/// `ServerURL` is pure and branchy, and it decides whether a user can connect
/// at all, so it gets a table rather than a handful of examples. Extracted from
/// `ServerSetupView.connect()` for issue #153.
final class ServerURLTests: XCTestCase {
    // MARK: - Normalization

    func testMissingSchemeDefaultsToHTTPS() {
        XCTAssertEqual(ServerURL.normalized("vikunja.example.com")?.absoluteString, "https://vikunja.example.com")
    }

    func testExistingSchemesArePreserved() {
        XCTAssertEqual(ServerURL.normalized("http://vikunja.example.com")?.absoluteString, "http://vikunja.example.com")
        XCTAssertEqual(
            ServerURL.normalized("https://vikunja.example.com")?.absoluteString,
            "https://vikunja.example.com"
        )
    }

    func testTrailingSlashesAreStripped() {
        // Otherwise appending a path yields "//api/v1/...".
        XCTAssertEqual(ServerURL.normalized("https://example.com/")?.absoluteString, "https://example.com")
        XCTAssertEqual(ServerURL.normalized("https://example.com///")?.absoluteString, "https://example.com")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(ServerURL.normalized("  example.com \n")?.absoluteString, "https://example.com")
    }

    func testSubpathIsPreserved() {
        // Vikunja is often reverse-proxied under a path.
        XCTAssertEqual(ServerURL.normalized("example.com/vikunja")?.absoluteString, "https://example.com/vikunja")
    }

    func testPortIsPreserved() {
        XCTAssertEqual(ServerURL.normalized("http://localhost:3456")?.absoluteString, "http://localhost:3456")
    }

    // MARK: - Hosts a self-hoster legitimately uses

    func testSelfHostedShapesAreAccepted() {
        let accepted = [
            "localhost",
            "http://localhost:3456",
            "127.0.0.1",
            "http://127.0.0.1:3456",
            "192.168.1.50",
            "10.0.0.1:3456",
            "vikunja", // single-label intranet name
            "vikunja.local",
            "vikunja.example.com",
            "172.25.17.55.nip.io", // the dev stack's host
            "http://[::1]:3456"
        ]
        for input in accepted {
            XCTAssertTrue(ServerURL.isValid(input), "expected \(input) to be accepted")
        }
    }

    // MARK: - Rejections

    func testEmptyAndWhitespaceAreRejected() {
        XCTAssertNil(ServerURL.normalized(""))
        XCTAssertNil(ServerURL.normalized("   "))
        XCTAssertNil(ServerURL.normalized("\n\t"))
    }

    func testNonHTTPSchemesAreRejected() {
        // The user pasting one of these should not produce a "server URL".
        for input in ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com", "mdone://callback"] {
            XCTAssertNil(ServerURL.normalized(input), "expected \(input) to be rejected")
        }
    }

    func testSingleCharacterTLDIsRejected() {
        // Nearly always a truncated "example.co" or "example.com".
        XCTAssertNil(ServerURL.normalized("example.c"))
    }

    func testMalformedHostsAreRejected() {
        for input in ["https://", "http:///path", "exa mple.com", "example..com", ".example.com", "example.com."] {
            XCTAssertNil(ServerURL.normalized(input), "expected \(input) to be rejected")
        }
    }

    func testNumericTLDIsRejected() {
        // Distinct from a bare IPv4, which is allowed above.
        XCTAssertNil(ServerURL.normalized("example.123"))
    }
}
