import XCTest
@testable import mDone

/// Decoding of `GET /api/v1/info` and the rules that turn it into a setup
/// screen, for issue #153.
///
/// The JSON here is copied from a real Vikunja v2.4.0 with Authelia in front of
/// it (see `scripts/dev-oidc-up.sh`), not hand-written from the docs.
final class AuthOptionsTests: XCTestCase {
    private func decode(_ json: String) throws -> ServerInfo {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ServerInfo.self, from: Data(json.utf8))
    }

    // MARK: - Fixtures

    /// Stock server, no identity provider configured. The common case.
    private let stockJSON = """
    {
      "version": "v2.4.0",
      "auth": {
        "local": { "enabled": true, "registration_enabled": true },
        "ldap": { "enabled": false },
        "openid_connect": { "enabled": false, "providers": null }
      }
    }
    """

    /// Authelia configured, local auth still on.
    private let oidcJSON = """
    {
      "version": "v2.4.0",
      "auth": {
        "local": { "enabled": true, "registration_enabled": true },
        "ldap": { "enabled": false },
        "openid_connect": {
          "enabled": true,
          "providers": [
            {
              "name": "Authelia",
              "key": "authelia",
              "auth_url": "https://auth.example.com/api/oidc/authorization",
              "logout_url": "",
              "client_id": "vikunja",
              "scope": "openid profile email",
              "email_fallback": false,
              "username_fallback": false,
              "force_user_info": false
            }
          ]
        }
      }
    }
    """

    // MARK: - Decoding

    func testStockServerDecodes() throws {
        let info = try decode(stockJSON)
        XCTAssertEqual(info.version, "v2.4.0")
        XCTAssertTrue(info.auth.local.enabled)
        XCTAssertEqual(info.auth.local.registrationEnabled, true)
        XCTAssertFalse(info.auth.ldap.enabled)
        XCTAssertFalse(info.auth.openidConnect.enabled)
    }

    func testNullProvidersDecodesRatherThanThrowing() throws {
        // Vikunja sends null, not [], when nothing is configured. Decoding this
        // as a non-optional array would fail on almost every real server.
        let info = try decode(stockJSON)
        XCTAssertNil(info.auth.openidConnect.providers)
        XCTAssertTrue(AuthOptions(info: info).providers.isEmpty)
    }

    func testProviderDecodes() throws {
        let info = try decode(oidcJSON)
        let provider = try XCTUnwrap(info.auth.openidConnect.providers?.first)
        XCTAssertEqual(provider.name, "Authelia")
        XCTAssertEqual(provider.key, "authelia")
        XCTAssertEqual(provider.clientId, "vikunja")
        XCTAssertEqual(provider.scope, "openid profile email")
        // Fully resolved by Vikunja from the provider's discovery document, so
        // the app never has to build it.
        XCTAssertEqual(provider.authorizationURL?.absoluteString, "https://auth.example.com/api/oidc/authorization")
        XCTAssertEqual(provider.id, provider.key)
    }

    func testUnknownProviderFieldsAreIgnored() throws {
        // email_fallback and friends are in the real payload and unused here.
        XCTAssertNoThrow(try decode(oidcJSON))
    }

    // MARK: - Tolerating older or unexpected servers

    func testMissingAuthBlockFallsBackToLocalOnly() throws {
        // A server old enough to omit `auth` predates both OIDC and LDAP.
        let info = try decode(#"{ "version": "v0.20.0" }"#)
        XCTAssertTrue(info.auth.local.enabled)
        XCTAssertFalse(info.auth.ldap.enabled)
        XCTAssertFalse(info.auth.openidConnect.enabled)
        XCTAssertTrue(AuthOptions(info: info).showsCredentials)
    }

    func testMissingLDAPKeyDefaultsToDisabled() throws {
        let info = try decode("""
        { "auth": { "local": { "enabled": true }, "openid_connect": { "enabled": false, "providers": null } } }
        """)
        XCTAssertFalse(info.auth.ldap.enabled)
    }

    func testEmptyProviderArrayIsTreatedLikeNone() throws {
        let info = try decode("""
        { "auth": { "local": { "enabled": true }, "openid_connect": { "enabled": true, "providers": [] } } }
        """)
        XCTAssertTrue(AuthOptions(info: info).providers.isEmpty)
    }

    // MARK: - The rules

    func testStockServerShowsCredentialsAndNoSSO() throws {
        let options = try AuthOptions(info: decode(stockJSON))
        XCTAssertTrue(options.showsCredentials)
        XCTAssertTrue(options.providers.isEmpty)
        XCTAssertFalse(options.isAPITokenOnly)
    }

    func testBothAvailableShowsCredentialsAndSSO() throws {
        let options = try AuthOptions(info: decode(oidcJSON))
        XCTAssertTrue(options.showsCredentials)
        XCTAssertEqual(options.providers.map(\.key), ["authelia"])
    }

    func testLocalAuthDisabledHidesCredentials() throws {
        // The SSO-only case. Leaving the fields visible is not merely untidy:
        // POST /api/v1/login returns 404 on such a server, so the user gets
        // "Not Found" rather than anything actionable.
        let info = try decode("""
        {
          "auth": {
            "local": { "enabled": false, "registration_enabled": false },
            "ldap": { "enabled": false },
            "openid_connect": { "enabled": true, "providers": [
              { "name": "Authelia", "key": "authelia", "auth_url": "https://auth.example.com/authorize" }
            ] }
          }
        }
        """)
        let options = AuthOptions(info: info)
        XCTAssertFalse(options.showsCredentials)
        XCTAssertEqual(options.providers.count, 1)
        XCTAssertFalse(options.isAPITokenOnly)
    }

    func testLDAPOnlyServerStillShowsCredentials() throws {
        // The regression this rule exists to prevent. LDAP binds go through the
        // same POST /login, so hiding the form on `local.enabled == false`
        // alone would lock LDAP users out entirely. See issue #156.
        let info = try decode("""
        {
          "auth": {
            "local": { "enabled": false },
            "ldap": { "enabled": true },
            "openid_connect": { "enabled": false, "providers": null }
          }
        }
        """)
        XCTAssertTrue(AuthOptions(info: info).showsCredentials)
    }

    func testNoPasswordAndNoSSOLeavesOnlyAPIToken() throws {
        let info = try decode("""
        {
          "auth": {
            "local": { "enabled": false },
            "ldap": { "enabled": false },
            "openid_connect": { "enabled": false, "providers": null }
          }
        }
        """)
        let options = AuthOptions(info: info)
        XCTAssertFalse(options.showsCredentials)
        XCTAssertTrue(options.providers.isEmpty)
        XCTAssertTrue(options.isAPITokenOnly)
        XCTAssertTrue(options.showsAPIToken)
    }

    func testProvidersIgnoredWhenOIDCDisabled() throws {
        // Trust the flag over a stale list.
        let info = try decode("""
        {
          "auth": {
            "local": { "enabled": true },
            "openid_connect": { "enabled": false, "providers": [
              { "name": "Authelia", "key": "authelia", "auth_url": "https://auth.example.com/authorize" }
            ] }
          }
        }
        """)
        XCTAssertTrue(AuthOptions(info: info).providers.isEmpty)
    }

    func testOIDCEnabledWithNullProvidersYieldsNoButtons() throws {
        // Not hypothetical: a misconfigured provider block leaves Vikunja
        // reporting enabled: true with providers: null, which is what the dev
        // stack did until the config was fixed. The screen must degrade to "no
        // SSO buttons" rather than crash or show an empty row.
        let info = try decode("""
        {
          "auth": {
            "local": { "enabled": true },
            "ldap": { "enabled": false },
            "openid_connect": { "enabled": true, "providers": null }
          }
        }
        """)
        let options = AuthOptions(info: info)
        XCTAssertTrue(options.providers.isEmpty)
        XCTAssertTrue(options.showsCredentials)
        XCTAssertFalse(options.isAPITokenOnly)
    }

    func testMissingLocalKeyDefaultsToEnabled() throws {
        // Fail open on the password form: locking a user out of their own
        // server is worse than showing a field the server will reject.
        let info = try decode(#"{ "auth": { "ldap": { "enabled": false } } }"#)
        XCTAssertTrue(info.auth.local.enabled)
        XCTAssertTrue(AuthOptions(info: info).showsCredentials)
    }

    func testMissingOpenIDKeyDefaultsToDisabled() throws {
        let info = try decode(#"{ "auth": { "local": { "enabled": true } } }"#)
        XCTAssertFalse(info.auth.openidConnect.enabled)
        XCTAssertTrue(AuthOptions(info: info).providers.isEmpty)
    }

    func testRulesHoldForValuesBuiltInCode() {
        // Same rules, without going through JSON, so a decoding change cannot
        // quietly mask a rules change.
        let provider = OIDCProvider(name: "Authelia", key: "authelia", authUrl: "https://auth.example.com/authorize")
        let info = ServerInfo(
            version: "v2.4.0",
            auth: .init(
                local: .init(enabled: false),
                ldap: .init(enabled: false),
                openidConnect: .init(enabled: true, providers: [provider])
            )
        )
        let options = AuthOptions(info: info)
        XCTAssertFalse(options.showsCredentials)
        XCTAssertEqual(options.providers, [provider])
        XCTAssertEqual(provider.authorizationURL?.absoluteString, "https://auth.example.com/authorize")
    }

    func testUnknownServerDefaultMatchesPreIssueBehaviour() {
        let options = AuthOptions.unknownServer
        XCTAssertTrue(options.showsCredentials)
        XCTAssertTrue(options.showsAPIToken)
        XCTAssertTrue(options.providers.isEmpty)
    }
}
