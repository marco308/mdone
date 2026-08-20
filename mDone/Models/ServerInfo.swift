import Foundation

/// The parts of `GET /api/v1/info` the login screen cares about.
///
/// Decoded with `APIClient`'s `convertFromSnakeCase` strategy, so `openid_connect`
/// arrives as `openidConnect` and `auth_url` as `authUrl`.
///
/// Everything here is lenient on purpose. This is the one endpoint the app hits
/// before it knows anything about the server, including how old it is, and a
/// decode failure here means the user cannot get to a login screen at all.
struct ServerInfo: Decodable, Equatable {
    var version: String?
    var auth: AuthInfo

    enum CodingKeys: String, CodingKey {
        case version, auth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        // A server old enough to have no `auth` block predates both OIDC and
        // LDAP, so username and password is the only way in.
        auth = try container.decodeIfPresent(AuthInfo.self, forKey: .auth) ?? .localOnly
    }

    init(version: String? = nil, auth: AuthInfo) {
        self.version = version
        self.auth = auth
    }

    struct AuthInfo: Decodable, Equatable {
        var local: Method
        var ldap: Method
        var openidConnect: OpenIDConnect

        static let localOnly = AuthInfo(
            local: Method(enabled: true),
            ldap: Method(enabled: false),
            openidConnect: OpenIDConnect(enabled: false, providers: nil)
        )

        enum CodingKeys: String, CodingKey {
            case local, ldap, openidConnect
        }

        init(local: Method, ldap: Method, openidConnect: OpenIDConnect) {
            self.local = local
            self.ldap = ldap
            self.openidConnect = openidConnect
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            local = try container.decodeIfPresent(Method.self, forKey: .local) ?? Method(enabled: true)
            ldap = try container.decodeIfPresent(Method.self, forKey: .ldap) ?? Method(enabled: false)
            openidConnect = try container.decodeIfPresent(OpenIDConnect.self, forKey: .openidConnect)
                ?? OpenIDConnect(enabled: false, providers: nil)
        }

        struct Method: Decodable, Equatable {
            var enabled: Bool
            var registrationEnabled: Bool?
        }

        struct OpenIDConnect: Decodable, Equatable {
            var enabled: Bool
            /// Vikunja sends `null`, not `[]`, when no provider is configured,
            /// which is the common case. Verified against v2.4.0.
            var providers: [OIDCProvider]?
        }
    }
}

/// One configured OIDC provider, as advertised by `/api/v1/info`.
struct OIDCProvider: Decodable, Equatable, Identifiable {
    /// Display name, e.g. "Authelia".
    var name: String
    /// Provider key, e.g. "authelia". This is the last path segment of both the
    /// redirect URI and the `/auth/openid/{key}/callback` endpoint.
    var key: String
    /// The fully resolved authorization endpoint. Vikunja reads this from the
    /// provider's discovery document, so the app never builds it.
    var authUrl: String
    var logoutUrl: String?
    var clientId: String?
    var scope: String?

    var id: String {
        key
    }

    var authorizationURL: URL? {
        URL(string: authUrl)
    }

    init(
        name: String,
        key: String,
        authUrl: String,
        logoutUrl: String? = nil,
        clientId: String? = nil,
        scope: String? = nil
    ) {
        self.name = name
        self.key = key
        self.authUrl = authUrl
        self.logoutUrl = logoutUrl
        self.clientId = clientId
        self.scope = scope
    }
}
