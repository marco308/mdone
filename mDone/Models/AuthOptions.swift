import Foundation

/// What the setup screen should offer, derived from `GET /info`.
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
    /// Whether to offer a two-factor code field alongside the password. True
    /// when the instance has TOTP turned on. The field is optional either
    /// way, because the instance flag says nothing about whether this
    /// particular account has enrolled (issue #179).
    var showsTOTP: Bool
    /// Whose username and password the credentials form takes, so the hint
    /// under it can say so (issue #156).
    var credentialAccounts: CredentialAccounts

    /// Which accounts a username and password can belong to on this server.
    /// Vikunja does not name the directory in `/info`, so this is as specific
    /// as the hint can be.
    enum CredentialAccounts: Equatable {
        /// Local Vikunja accounts only, or a server that has not said.
        case vikunja
        /// Local accounts and an LDAP directory, both signed in through
        /// `POST /login`.
        case vikunjaOrDirectory
        /// An LDAP directory with local sign-in turned off.
        case directory
    }

    /// True when the server offers neither password nor SSO login, leaving an
    /// API token as the only way in. Worth saying out loud in the UI rather
    /// than presenting a form that cannot work.
    var isAPITokenOnly: Bool {
        !showsCredentials && providers.isEmpty
    }

    /// Conservative default for before `/info` has been fetched, or when
    /// fetching it failed. Matches how the app behaved before issue #153: show
    /// the credentials form and no SSO.
    static let unknownServer = AuthOptions(showsCredentials: true, showsAPIToken: true, providers: [])

    init(
        showsCredentials: Bool,
        showsAPIToken: Bool,
        providers: [OIDCProvider],
        showsTOTP: Bool = false,
        credentialAccounts: CredentialAccounts = .vikunja
    ) {
        self.showsCredentials = showsCredentials
        self.showsAPIToken = showsAPIToken
        self.providers = providers
        self.showsTOTP = showsTOTP
        self.credentialAccounts = credentialAccounts
    }

    init(info: ServerInfo) {
        let auth = info.auth

        // Deliberately `||`, not just `local.enabled`. LDAP binds go through
        // the same POST /login with a username and password (verified on
        // v2.8.0, issue #156), so an LDAP-only server still needs these
        // fields. Hiding them there would leave no way to sign in at all.
        showsCredentials = auth.local.enabled || auth.ldap.enabled

        credentialAccounts = switch (auth.local.enabled, auth.ldap.enabled) {
        case (_, false): .vikunja
        case (true, true): .vikunjaOrDirectory
        case (false, true): .directory
        }

        showsAPIToken = true

        // `enabled: false` with a populated `providers` array is not something
        // Vikunja is expected to send, but trust the flag over the list.
        providers = auth.openidConnect.enabled ? (auth.openidConnect.providers ?? []) : []

        showsTOTP = info.totpEnabled
    }

    /// The line under the username and password form. Written out in full
    /// for each case rather than assembled, so each reads naturally and
    /// translates as one sentence.
    var credentialsHint: String {
        switch credentialAccounts {
        case .vikunja:
            String(
                localized: "Sign in with your Vikunja username and password. If your account has two-factor authentication turned on, enter the code from your authenticator app as well."
            )
        case .vikunjaOrDirectory:
            String(
                localized: "Sign in with your Vikunja username and password, or with your directory account if your server uses LDAP or Active Directory. If your account has two-factor authentication turned on, enter the code from your authenticator app as well."
            )
        case .directory:
            String(
                localized: "This server signs you in through a directory such as LDAP or Active Directory. Use the username and password you have there. If your account has two-factor authentication turned on, enter the code from your authenticator app as well."
            )
        }
    }
}
