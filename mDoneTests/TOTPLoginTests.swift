import XCTest
@testable import mDone

/// The two-factor half of the password login (issue #179): how Vikunja's
/// refusals of `POST /login` reach the setup screen.
///
/// Status codes and bodies here were captured from a real Vikunja v2.4.0 with
/// TOTP enrolled on the account, not written from the docs. Vikunja answers a
/// missing, empty or wrong passcode identically (412, code 1017), and a wrong
/// password with 403, code 1011.
final class TOTPLoginTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func login(
        status: Int,
        body: String,
        passcode: String? = nil
    ) async -> NetworkError? {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "")
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: status, url: request.url), Data(body.utf8))
        }
        do {
            let _: LoginResponse = try await client.send(
                Endpoint.login,
                body: LoginRequest(username: "devuser", password: "devpassword", totpPasscode: passcode)
            )
            XCTFail("Expected the login to be refused")
            return nil
        } catch let error as NetworkError {
            return error
        } catch {
            XCTFail("Unexpected error type: \(error)")
            return nil
        }
    }

    // MARK: - APIClient maps Vikunja's login refusals

    func testRejectedPasscodeBecomesInvalidTOTPPasscode() async {
        let error = await login(status: 412, body: #"{"code":1017,"message":"Invalid totp passcode."}"#)
        guard case .invalidTOTPPasscode = error else {
            return XCTFail("Expected .invalidTOTPPasscode, got \(String(describing: error))")
        }
    }

    func testWrongPasswordBecomesInvalidCredentials() async {
        let error = await login(status: 403, body: #"{"code":1011,"message":"Wrong username or password."}"#)
        guard case .invalidCredentials = error else {
            return XCTFail("Expected .invalidCredentials, got \(String(describing: error))")
        }
    }

    func testOther412StaysAServerError() async {
        // Only the two login codes get names. Anything else keeps the generic
        // path so no existing caller sees a new case it does not handle.
        let error = await login(status: 412, body: #"{"code":1016,"message":"Totp is not enabled for this user."}"#)
        guard case let .serverError(status, message) = error else {
            return XCTFail("Expected .serverError, got \(String(describing: error))")
        }
        XCTAssertEqual(status, 412)
        XCTAssertEqual(message, "Totp is not enabled for this user.")
    }

    func testLoginCodeUnderAnotherStatusStaysAServerError() async {
        // The mapping is on status and code together. Code 1017 under a
        // status Vikunja does not use for it is not the login refusal this
        // was written for, and must not masquerade as one.
        let error = await login(status: 400, body: #"{"code":1017,"message":"Invalid totp passcode."}"#)
        guard case let .serverError(status, _) = error else {
            return XCTFail("Expected .serverError, got \(String(describing: error))")
        }
        XCTAssertEqual(status, 400)

        let mismatched = await login(status: 412, body: #"{"code":1011,"message":"Wrong username or password."}"#)
        guard case .serverError = mismatched else {
            return XCTFail("Expected .serverError, got \(String(describing: mismatched))")
        }
    }

    func testBodyWithoutCodeStaysAServerError() async {
        let error = await login(status: 412, body: "not json")
        guard case let .serverError(status, message) = error else {
            return XCTFail("Expected .serverError, got \(String(describing: error))")
        }
        XCTAssertEqual(status, 412)
        XCTAssertNil(message)
    }

    func testPasscodeIsSentInTheBody() async {
        _ = await login(status: 412, body: #"{"code":1017,"message":"Invalid totp passcode."}"#, passcode: "123456")
        let body = MockURLProtocol.capturedRequests.first.flatMap(MockURLProtocol.bodyData(from:))
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(json?["totp_passcode"] as? String, "123456")
        XCTAssertEqual(json?["username"] as? String, "devuser")
    }

    func testNoPasscodeMeansNoField() async {
        _ = await login(status: 403, body: #"{"code":1011,"message":"Wrong username or password."}"#)
        let body = MockURLProtocol.capturedRequests.first.flatMap(MockURLProtocol.bodyData(from:))
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertNotNil(json)
        XCTAssertNil(json?["totp_passcode"])
    }

    // MARK: - The caller tells "missing" from "wrong"

    func testRejectedPasscodeWithNoneSentMeansRequired() {
        let error = NetworkError.invalidTOTPPasscode.forCredentialLogin(sentPasscode: false)
        guard case .totpRequired = error else {
            return XCTFail("Expected .totpRequired, got \(error)")
        }
    }

    func testRejectedPasscodeThatWasSentStaysRejected() {
        let error = NetworkError.invalidTOTPPasscode.forCredentialLogin(sentPasscode: true)
        guard case .invalidTOTPPasscode = error else {
            return XCTFail("Expected .invalidTOTPPasscode, got \(error)")
        }
    }

    func testOtherErrorsPassThroughUntouched() {
        guard case .invalidCredentials = NetworkError.invalidCredentials.forCredentialLogin(sentPasscode: false) else {
            return XCTFail("invalidCredentials should not be reinterpreted")
        }
        guard case .serverUnreachable = NetworkError.serverUnreachable.forCredentialLogin(sentPasscode: false) else {
            return XCTFail("serverUnreachable should not be reinterpreted")
        }
    }

    // MARK: - Copy

    func testMessagesNameTheProblem() throws {
        let required = try XCTUnwrap(NetworkError.totpRequired.errorDescription).lowercased()
        XCTAssertTrue(required.contains("two-factor"), required)
        XCTAssertTrue(required.contains("code"), required)

        let rejected = try XCTUnwrap(NetworkError.invalidTOTPPasscode.errorDescription).lowercased()
        XCTAssertTrue(rejected.contains("code"), rejected)
        XCTAssertTrue(rejected.contains("try again"), rejected)

        let credentials = try XCTUnwrap(NetworkError.invalidCredentials.errorDescription).lowercased()
        XCTAssertTrue(credentials.contains("password"), credentials)

        for error in [NetworkError.totpRequired, .invalidTOTPPasscode, .invalidCredentials] {
            XCTAssertNotNil(error.recoverySuggestion)
            XCTAssertFalse(error.iconName.isEmpty)
            XCTAssertFalse(error.isConnectivityFailure)
        }
    }
}
