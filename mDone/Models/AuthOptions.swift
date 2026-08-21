import Foundation

/// What the setup screen should offer, derived from `GET /api/v1/info`.
///
/// Kept as a plain value computed by a pure function so the rules can be tested
/// without standing up a view. See `AuthOptionsTests`.
struct AuthOptions: Equatable {
    /// Whether to show the username and password fields.
    var showsCredentials: Bool
    /// Whether to offer the API-token field. Always true: personal API tokens
    /// are issued in Vikunja's own settings and validate independently of how
    /// the instance authenticates people.
    var showsAPIToken: Bool
    /// SSO buttons to render, in server order. Empty when OIDC is off.
    var providers: [OIDCProvider]

    /// True when the server offers neither password nor SSO login, leaving an
    /// API token as the only way in. Worth saying out loud in the UI rather
    /// than presenting a form that cannot work.
    var isAPITokenOnly: Bool {
        !showsCredentials && providers.isEmpty
    }

    /// Conservative default for before `/api/v1/info` has been fetched, or when
    /// fetching it failed. Matches how the app behaved before issue #153: show
    /// the credentials form and no SSO.
    static let unknownServer = AuthOptions(showsCredentials: true, showsAPIToken: true, providers: [])

    init(showsCredentials: Bool, showsAPIToken: Bool, providers: [OIDCProvider]) {
        self.showsCredentials = showsCredentials
        self.showsAPIToken = showsAPIToken
        self.providers = providers
    }

    init(info: ServerInfo) {
        let auth = info.auth

        // Deliberately `||`, not just `local.enabled`. LDAP binds go through
        // the same POST /api/v1/login with a username and password, so an
        // LDAP-only server still needs these fields even though mDone has no
        // LDAP-specific support yet (issue #156). Hiding them there would
        // leave the user with no way to sign in at all.
        showsCredentials = auth.local.enabled || auth.ldap.enabled

        showsAPIToken = true

        // `enabled: false` with a populated `providers` array is not something
        // Vikunja is expected to send, but trust the flag over the list.
        providers = auth.openidConnect.enabled ? (auth.openidConnect.providers ?? []) : []
    }
}
