import XCTest
@testable import mDone

/// The redirect parser is the security-critical half of issue #153 and was
/// untested in PR #103, which is where two of these cases come from directly:
/// the `state` token that was generated and never compared, and the `error=`
/// response that left the user on a stuck web view.
final class OIDCCallbackTests: XCTestCase {
    private let state = "expected-state-abc123"

    private func callback(_ query: String, scheme: String = "mdone") -> URL {
        URL(string: "\(scheme)://auth/openid/authelia?\(query)")!
    }

    // MARK: - Success

    func testValidCallbackReturnsCode() {
        let result = OIDCLogin.parseCallback(callback("code=auth-code-xyz&state=\(state)"), expectedState: state)
        XCTAssertEqual(result, .success(code: "auth-code-xyz"))
    }

    func testParameterOrderDoesNotMatter() {
        let result = OIDCLogin.parseCallback(callback("state=\(state)&code=auth-code-xyz"), expectedState: state)
        XCTAssertEqual(result, .success(code: "auth-code-xyz"))
    }

    func testIssuerParameterIsTolerated() {
        // Authelia returns `iss` per RFC 9207, alongside code and state.
        let result = OIDCLogin.parseCallback(
            callback("code=abc&state=\(state)&iss=https%3A%2F%2Fauth.example.com&scope=openid+profile"),
            expectedState: state
        )
        XCTAssertEqual(result, .success(code: "abc"))
    }

    func testPercentEncodedCodeIsDecoded() {
        // Real Authelia codes contain "." and "-"; other providers emit "/" and
        // "+", which arrive percent-encoded.
        let result = OIDCLogin.parseCallback(
            callback("code=abc%2Fdef%2Bghi%3D&state=\(state)"),
            expectedState: state
        )
        XCTAssertEqual(result, .success(code: "abc/def+ghi="))
    }

    // MARK: - State validation (the #103 bug)

    func testMismatchedStateIsRejected() {
        let result = OIDCLogin.parseCallback(callback("code=abc&state=attacker-chosen"), expectedState: state)
        XCTAssertEqual(result, .stateMismatch)
    }

    func testMissingStateIsRejected() {
        let result = OIDCLogin.parseCallback(callback("code=abc"), expectedState: state)
        XCTAssertEqual(result, .stateMismatch)
    }

    func testEmptyStateIsRejected() {
        let result = OIDCLogin.parseCallback(callback("code=abc&state="), expectedState: state)
        XCTAssertEqual(result, .stateMismatch)
    }

    func testStateComparisonIsCaseSensitive() {
        let result = OIDCLogin.parseCallback(callback("code=abc&state=\(state.uppercased())"), expectedState: state)
        XCTAssertEqual(result, .stateMismatch)
    }

    func testStateIsCheckedBeforeErrorIsReported() {
        // A forged error response should not get as far as being surfaced.
        let result = OIDCLogin.parseCallback(callback("error=access_denied&state=wrong"), expectedState: state)
        XCTAssertEqual(result, .stateMismatch)
    }

    // MARK: - Provider errors (the other #103 bug)

    func testAccessDeniedIsSurfaced() {
        let result = OIDCLogin.parseCallback(
            callback("error=access_denied&error_description=User%20cancelled&state=\(state)"),
            expectedState: state
        )
        XCTAssertEqual(result, .providerError(error: "access_denied", description: "User cancelled"))
    }

    func testErrorWithoutDescriptionIsSurfaced() {
        let result = OIDCLogin.parseCallback(callback("error=server_error&state=\(state)"), expectedState: state)
        XCTAssertEqual(result, .providerError(error: "server_error", description: nil))
    }

    func testErrorWinsOverCode() {
        // A response carrying both is a failure pretending to be a success.
        let result = OIDCLogin.parseCallback(
            callback("code=abc&error=invalid_request&state=\(state)"),
            expectedState: state
        )
        XCTAssertEqual(result, .providerError(error: "invalid_request", description: nil))
    }

    // MARK: - Malformed input

    func testMissingCodeIsMalformed() {
        let result = OIDCLogin.parseCallback(callback("state=\(state)"), expectedState: state)
        XCTAssertEqual(result, .malformed(.missingCode))
    }

    func testEmptyCodeIsMalformed() {
        let result = OIDCLogin.parseCallback(callback("code=&state=\(state)"), expectedState: state)
        XCTAssertEqual(result, .malformed(.missingCode))
    }

    func testNoQueryParametersIsMalformed() throws {
        let result = try OIDCLogin.parseCallback(
            XCTUnwrap(URL(string: "mdone://auth/openid/authelia")),
            expectedState: state
        )
        XCTAssertEqual(result, .malformed(.noQueryParameters))
    }

    func testDuplicateCodeIsRejected() {
        // Which duplicate wins is a parser detail an attacker can aim at.
        let result = OIDCLogin.parseCallback(
            callback("code=good&code=evil&state=\(state)"),
            expectedState: state
        )
        XCTAssertEqual(result, .malformed(.duplicateParameter("code")))
    }

    func testDuplicateStateIsRejected() {
        let result = OIDCLogin.parseCallback(
            callback("code=abc&state=\(state)&state=other"),
            expectedState: state
        )
        XCTAssertEqual(result, .malformed(.duplicateParameter("state")))
    }

    func testUnexpectedSchemeIsRejected() {
        let result = OIDCLogin.parseCallback(
            callback("code=abc&state=\(state)", scheme: "https"),
            expectedState: state,
            expectedScheme: "mdone"
        )
        XCTAssertEqual(result, .malformed(.unexpectedCallbackScheme))
    }

    func testMatchingSchemeIsAccepted() {
        let result = OIDCLogin.parseCallback(
            callback("code=abc&state=\(state)"),
            expectedState: state,
            expectedScheme: "MDone" // registration is case-insensitive
        )
        XCTAssertEqual(result, .success(code: "abc"))
    }

    // MARK: - The code must not leak into logs

    func testDebugDescriptionRedactsTheCode() {
        let result = OIDCLogin.parseCallback(
            callback("code=super-secret-code&state=\(state)"),
            expectedState: state
        )
        // Catches the `print("\(result)")` that slips through review.
        XCTAssertFalse(String(reflecting: result).contains("super-secret-code"))
        XCTAssertTrue(String(reflecting: result).contains("redacted"))
    }

    func testProviderErrorDescriptionIsNotRedacted() {
        // The error is diagnostic, not a credential, so it stays readable.
        let result = OIDCLogin.parseCallback(
            callback("error=access_denied&state=\(state)"),
            expectedState: state
        )
        XCTAssertTrue(String(reflecting: result).contains("access_denied"))
    }

    func testDebugDescriptionCoversTheRejectionCases() {
        let mismatch = OIDCLogin.parseCallback(callback("code=abc&state=wrong"), expectedState: state)
        XCTAssertTrue(String(reflecting: mismatch).contains("stateMismatch"))

        let malformed = OIDCLogin.parseCallback(callback("state=\(state)"), expectedState: state)
        XCTAssertTrue(String(reflecting: malformed).contains("malformed"))
        XCTAssertTrue(String(reflecting: malformed).contains("missingCode"))
    }

    // MARK: - State generation

    func testGeneratedStateIsLongEnough() {
        // 32 bytes base64url, unpadded.
        XCTAssertEqual(OIDCLogin.generateState().count, 43)
    }

    func testGeneratedStateIsURLSafe() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for _ in 0 ..< 100 {
            let state = OIDCLogin.generateState()
            XCTAssertTrue(state.unicodeScalars.allSatisfy { allowed.contains($0) }, "not URL safe: \(state)")
        }
    }

    func testGeneratedStatesAreUnique() {
        let states = Set((0 ..< 2000).map { _ in OIDCLogin.generateState() })
        XCTAssertEqual(states.count, 2000)
    }

    // MARK: - Nonce generation

    func testGeneratedNonceIsLongEnough() {
        // 32 bytes base64url, unpadded. Providers enforce a floor: Authelia
        // rejects a short nonce with `insufficient_entropy`, and it surfaces at
        // the token exchange, long after the user finished logging in.
        XCTAssertEqual(OIDCLogin.generateNonce().count, 43)
    }

    func testGeneratedNonceIsURLSafe() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        for _ in 0 ..< 100 {
            let nonce = OIDCLogin.generateNonce()
            XCTAssertTrue(nonce.unicodeScalars.allSatisfy { allowed.contains($0) }, "not URL safe: \(nonce)")
        }
    }

    func testGeneratedNoncesAreUnique() {
        let nonces = Set((0 ..< 2000).map { _ in OIDCLogin.generateNonce() })
        XCTAssertEqual(nonces.count, 2000)
    }

    func testStateAndNonceAreIndependentValues() {
        // The one mistake worth guarding against here. They protect against
        // different attacks, and reusing a single token for both means a leak
        // of either defeats both.
        for _ in 0 ..< 100 {
            XCTAssertNotEqual(OIDCLogin.generateState(), OIDCLogin.generateNonce())
        }
    }

    func testStateAndNonceDrawFromTheSamePool() {
        // Not a security property, just a guard against one of them being
        // quietly reimplemented with a weaker or shorter source later.
        XCTAssertEqual(OIDCLogin.generateState().count, OIDCLogin.generateNonce().count)
    }

    // MARK: - Round trip

    func testGeneratedStateRoundTripsThroughAQueryString() {
        // The whole point of base64url: no escaping on the way out or back.
        let state = OIDCLogin.generateState()
        let result = OIDCLogin.parseCallback(callback("code=abc&state=\(state)"), expectedState: state)
        XCTAssertEqual(result, .success(code: "abc"))
    }
}
