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
        ServerInfoService(apiClient: MockURLProtocol.mockClient())
    }

    func testFetchesTheInfoEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(self.oidcJSON.utf8))
        }
        let info = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))

        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, VikunjaAPI.path("/info"))
        XCTAssertEqual(info.auth.openidConnect.providers?.first?.key, "authelia")
    }

    // MARK: - Fallback for servers without the v2 API (#291)

    /// A server older than Vikunja 2.4.0 has no `/api/v2`, so its version has
    /// to come from v1 for the app to be able to say "update your server".
    func testFallsBackToTheV1InfoWhenV2AnswersNotFound() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == VikunjaAPI.path("/info") {
                return (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data(#"{"message":"Not Found"}"#.utf8))
            }
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(#"{"version": "v2.3.0"}"#.utf8))
        }

        let info = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))

        XCTAssertEqual(info.version, "v2.3.0")
        XCTAssertEqual(
            MockURLProtocol.capturedRequests.map(\.url?.path),
            [VikunjaAPI.path("/info"), VikunjaAPI.legacyPath("/info")]
        )
    }

    func testDoesNotFallBackWhenV2Answers() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(#"{"version": "v2.8.0"}"#.utf8))
        }

        _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))

        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.url?.path), [VikunjaAPI.path("/info")])
    }

    /// Only "this route does not exist" means an old server. A proxy refusing
    /// the request, or the server failing, says nothing about its version.
    func testDoesNotFallBackOnOtherFailures() async throws {
        for status in [403, 500] {
            MockURLProtocol.reset()
            MockURLProtocol.requestHandler = { request in
                (MockURLProtocol.makeResponse(statusCode: status, url: request.url), Data("{}".utf8))
            }
            do {
                _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://vikunja.example.com")))
                XCTFail("expected a throw for \(status)")
            } catch {}
            XCTAssertTrue(
                MockURLProtocol.capturedRequests.allSatisfy { $0.url?.path == VikunjaAPI.path("/info") },
                "\(status) must not be retried on v1"
            )
        }
    }

    func testFallbackFailurePropagates() async throws {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
        }
        do {
            _ = try await service().fetch(from: XCTUnwrap(URL(string: "https://not-vikunja.example.com")))
            XCTFail("expected a throw")
        } catch {}
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2)
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
