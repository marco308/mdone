import XCTest
@testable import mDone

/// The app builds the authorization URL itself: Vikunja supplies only the
/// resolved endpoint in `auth_url`. Getting a parameter wrong here fails at the
/// provider, or worse at the token exchange, long after the user has finished
/// logging in.
final class OIDCAuthorizationURLTests: XCTestCase {
    private let redirectURI = "mdone://oidc-callback"

    private func provider(
        authUrl: String = "https://auth.example.com/api/oidc/authorization",
        clientId: String? = "vikunja",
        scope: String? = "openid profile email"
    ) -> OIDCProvider {
        OIDCProvider(name: "Authelia", key: "authelia", authUrl: authUrl, clientId: clientId, scope: scope)
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    // MARK: - Happy path

    func testBuildsEveryRequiredParameter() throws {
        let url = try OIDCLogin.authorizationURL(
            for: provider(),
            redirectURI: redirectURI,
            state: "the-state",
            nonce: "the-nonce"
        )
        let params = query(url)
        XCTAssertEqual(params["client_id"], "vikunja")
        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["redirect_uri"], redirectURI)
        XCTAssertEqual(params["scope"], "openid profile email")
        XCTAssertEqual(params["state"], "the-state")
        XCTAssertEqual(params["nonce"], "the-nonce")
    }

    func testKeepsTheProvidersEndpointIntact() throws {
        let url = try OIDCLogin.authorizationURL(
            for: provider(),
            redirectURI: redirectURI,
            state: "s",
            nonce: "n"
        )
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "auth.example.com")
        XCTAssertEqual(url.path, "/api/oidc/authorization")
    }

    func testCustomSchemeRedirectSurvivesEncoding() throws {
        // The redirect URI has to match what Vikunja is later sent byte for
        // byte, or the exchange fails with invalid_grant.
        let url = try OIDCLogin.authorizationURL(
            for: provider(),
            redirectURI: redirectURI,
            state: "s",
            nonce: "n"
        )
        XCTAssertEqual(query(url)["redirect_uri"], "mdone://oidc-callback")
    }

    func testExistingQueryParametersOnTheEndpointArePreserved() throws {
        // Some providers publish an authorization endpoint that already carries
        // parameters. Replacing them would break those providers.
        let url = try OIDCLogin.authorizationURL(
            for: provider(authUrl: "https://auth.example.com/authorize?tenant=acme"),
            redirectURI: redirectURI,
            state: "s",
            nonce: "n"
        )
        let params = query(url)
        XCTAssertEqual(params["tenant"], "acme")
        XCTAssertEqual(params["client_id"], "vikunja")
    }

    func testFallsBackToADefaultScope() throws {
        // Vikunja normally advertises one, but do not send an empty scope if not.
        let url = try OIDCLogin.authorizationURL(
            for: provider(scope: nil),
            redirectURI: redirectURI,
            state: "s",
            nonce: "n"
        )
        XCTAssertEqual(query(url)["scope"], OIDCLogin.defaultScope)
        XCTAssertTrue(OIDCLogin.defaultScope.contains("openid"))
    }

    func testServerSuppliedScopeWins() throws {
        let url = try OIDCLogin.authorizationURL(
            for: provider(scope: "openid email groups"),
            redirectURI: redirectURI,
            state: "s",
            nonce: "n"
        )
        XCTAssertEqual(query(url)["scope"], "openid email groups")
    }

    // MARK: - Rejections

    func testInsecureEndpointIsRejected() throws {
        // App Transport Security would refuse to load it anyway. Failing here
        // gives a better message than a generic network error.
        XCTAssertThrowsError(try OIDCLogin.authorizationURL(
            for: provider(authUrl: "http://auth.example.com/authorize"),
            redirectURI: redirectURI, state: "s", nonce: "n"
        )) { XCTAssertEqual($0 as? OIDCLoginError, .insecureAuthorizationEndpoint) }
    }

    func testMissingClientIDIsRejected() throws {
        XCTAssertThrowsError(try OIDCLogin.authorizationURL(
            for: provider(clientId: nil), redirectURI: redirectURI, state: "s", nonce: "n"
        )) { XCTAssertEqual($0 as? OIDCLoginError, .missingClientID) }
    }

    func testEmptyClientIDIsRejected() throws {
        XCTAssertThrowsError(try OIDCLogin.authorizationURL(
            for: provider(clientId: ""), redirectURI: redirectURI, state: "s", nonce: "n"
        )) { XCTAssertEqual($0 as? OIDCLoginError, .missingClientID) }
    }

    func testUnusableEndpointsAreRejected() throws {
        for bad in ["", "not a url", "/authorize", "https://"] {
            XCTAssertThrowsError(try OIDCLogin.authorizationURL(
                for: provider(authUrl: bad), redirectURI: redirectURI, state: "s", nonce: "n"
            ), "expected \(bad) to be rejected")
        }
    }

    func testEveryErrorHasAUserFacingMessage() {
        // These surface on the setup screen, so none may fall through to the
        // default "The operation couldn't be completed" text.
        for error in [
            OIDCLoginError.invalidAuthorizationEndpoint,
            .insecureAuthorizationEndpoint,
            .missingClientID,
        ] {
            XCTAssertFalse(error.localizedDescription.isEmpty)
            XCTAssertFalse(error.localizedDescription.contains("couldn't be completed"))
        }
    }

    // MARK: - Round trip with the real generators

    func testGeneratedStateAndNonceSurviveTheURLAndComeBack() throws {
        let state = OIDCLogin.generateState()
        let nonce = OIDCLogin.generateNonce()
        let url = try OIDCLogin.authorizationURL(
            for: provider(), redirectURI: redirectURI, state: state, nonce: nonce
        )
        let params = query(url)
        XCTAssertEqual(params["state"], state)
        XCTAssertEqual(params["nonce"], nonce)
        XCTAssertNotEqual(params["state"], params["nonce"])

        // And the state we put in is the state the callback parser expects out.
        let callback = try XCTUnwrap(URL(string: "mdone://oidc-callback?code=abc&state=\(state)"))
        XCTAssertEqual(
            OIDCLogin.parseCallback(callback, expectedState: state, expectedScheme: "mdone"),
            .success(code: "abc")
        )
    }
}
