import XCTest
@testable import mDone

final class JWTHelpersTests: XCTestCase {
    // MARK: - isJWT

    func testIsJWTRecognisesValidThreeSegmentToken() {
        let token = makeJWT(payload: ["sub": "user", "exp": 1_700_000_000])
        XCTAssertTrue(JWTHelpers.isJWT(token))
    }

    func testIsJWTRejectsAPITokens() {
        XCTAssertFalse(JWTHelpers.isJWT("tk_abcdef1234567890"))
    }

    func testIsJWTRejectsSingleSegmentString() {
        XCTAssertFalse(JWTHelpers.isJWT("not-a-jwt"))
    }

    func testIsJWTRejectsTwoSegmentString() {
        XCTAssertFalse(JWTHelpers.isJWT("header.payload"))
    }

    func testIsJWTRejectsFourSegmentString() {
        XCTAssertFalse(JWTHelpers.isJWT("a.b.c.d"))
    }

    func testIsJWTRejectsTokenWithUndecodablePayload() {
        // Three segments but the middle is not valid base64 JSON.
        XCTAssertFalse(JWTHelpers.isJWT("aaa.!!!.bbb"))
    }

    // MARK: - parseExpiry

    func testParseExpiryReturnsDateFromExpClaim() {
        let exp: TimeInterval = 1_716_500_000
        let token = makeJWT(payload: ["exp": exp])
        let date = JWTHelpers.parseExpiry(token)
        XCTAssertEqual(date?.timeIntervalSince1970, exp)
    }

    func testParseExpiryReturnsNilWhenExpMissing() {
        let token = makeJWT(payload: ["sub": "user"])
        XCTAssertNil(JWTHelpers.parseExpiry(token))
    }

    func testParseExpiryReturnsNilForAPIToken() {
        XCTAssertNil(JWTHelpers.parseExpiry("tk_abcdef1234567890"))
    }

    func testParseExpiryHandlesPayloadNeedingBase64Padding() throws {
        // Pick a payload whose base64 length is not a multiple of 4 so the
        // helper has to re-pad before decoding.
        let payload = ["e": 1] as [String: Int]
        let raw = try JSONSerialization.data(withJSONObject: payload)
        let unpadded = raw.base64EncodedString()
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        // Even if the payload doesn't have `exp`, we should still successfully
        // parse the JSON (and return nil because exp is missing, not throw).
        let token = "h.\(unpadded).s"
        XCTAssertNil(JWTHelpers.parseExpiry(token))
        XCTAssertTrue(JWTHelpers.isJWT(token))
    }

    func testParseExpiryReturnsNilForMalformedPayload() {
        XCTAssertNil(JWTHelpers.parseExpiry("h.!!!.s"))
    }

    // MARK: - Helpers

    /// Builds a JWT with the given payload. Header/signature are unused — we
    /// never verify, just inspect — so they can be any base64url-safe filler.
    private func makeJWT(payload: [String: Any]) -> String {
        let header = base64URL(Data("{\"alg\":\"HS256\"}".utf8))
        let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let body = base64URL(payloadData)
        let signature = base64URL(Data("sig".utf8))
        return "\(header).\(body).\(signature)"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
