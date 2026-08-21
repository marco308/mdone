import XCTest
@testable import mDone

/// The setup screen probes an unknown server before the user has any
/// credentials for it, so this has to work unauthenticated and must never touch
/// the shared client.
final class ServerInfoServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private let oidcJSON = """
    {
      "version": "v2.4.0",
      "auth": {
        "local": { "enabled": true, "registration_enabled": true },
        "ldap": { "enabled": false },
        "openid_connect": {
          "enabled": true,
          "providers": [
            { "name": "Authelia", "key": "authelia",
              "auth_url": "https://auth.example.com/api/oidc/authorization",
              "client_id": "vikunja", "scope": "openid profile email" }
          ]
        }
      }
    }
    """

    private func service() -> ServerInfoService {
        ServerInfoService(apiClient: APIClient(session: MockURLProtocol.mockSession()))
    }

    func testFetchesTheInfoEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(self.oidcJSON.utf8))
        }
        let info = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))

        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/info")
        XCTAssertEqual(info.auth.openidConnect.providers?.first?.key, "authelia")
    }

    func testSendsNoAuthorizationHeader() async throws {
        // The probe runs before the user has credentials. An empty bearer token
        // is not merely useless: a forward-auth proxy in front of Vikunja can
        // reject the malformed header, which reads as an unreachable server.
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(self.oidcJSON.utf8))
        }
        _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))

        let header = MockURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: "Authorization")
        XCTAssertNil(header)
    }

    func testDecodesWithSnakeCaseConversion() async throws {
        // Without convertFromSnakeCase, openid_connect fails to map and decodes
        // via decodeIfPresent to "disabled", so an SSO-capable server would
        // render with no SSO buttons and no error anywhere.
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(self.oidcJSON.utf8))
        }
        let info = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))

        XCTAssertTrue(info.auth.openidConnect.enabled)
        XCTAssertEqual(
            info.auth.openidConnect.providers?.first?.authUrl,
            "https://auth.example.com/api/oidc/authorization"
        )
        XCTAssertEqual(info.auth.local.registrationEnabled, true)
    }

    func testTargetsTheServerItWasGiven() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(self.oidcJSON.utf8))
        }
        _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://other.example.org:8443")))

        let url = MockURLProtocol.capturedRequests.first?.url
        XCTAssertEqual(url?.host, "other.example.org")
        XCTAssertEqual(url?.port, 8443)
    }

    func testServerErrorPropagates() async throws {
        // The caller degrades to AuthOptions.unknownServer; this only has to
        // fail rather than hang or return something invented.
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data("{}".utf8))
        }
        do {
            _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))
            XCTFail("expected a throw")
        } catch {
            // expected
        }
    }

    func testMalformedJSONPropagates() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data("not json".utf8))
        }
        do {
            _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))
            XCTFail("expected a throw")
        } catch {
            // expected
        }
    }

    func testDoesNotDisturbTheSharedClient() async throws {
        // Probing on every keystroke must not overwrite a signed-in user's
        // server URL and token on the shared singleton.
        await APIClient.shared.configure(serverURL: "https://real.example.com", token: "real-token")
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(self.oidcJSON.utf8))
        }
        _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://someone-elses.example.org")))

        // The probe configures its own client with an empty token. If it had
        // used the singleton, this would now be "".
        let stillConfigured = await APIClient.shared.currentToken()
        XCTAssertEqual(stillConfigured, "real-token")
        await APIClient.shared.clearCredentials()
    }
}
