import Foundation
import Security

/// The outcome of an OIDC redirect coming back to the app.
///
/// `code` is deliberately not part of any description. See `debugDescription`.
enum OIDCCallbackResult: Equatable {
    /// A usable authorization code, with a `state` that matched.
    case success(code: String)
    /// The provider reported a failure, e.g. `error=access_denied` when the
    /// user pressed Cancel on the consent screen. PR #103 ignored this case
    /// entirely, which left the user staring at a stuck web view.
    case providerError(error: String, description: String?)
    /// `state` was missing, or did not match the value we generated. Treated as
    /// hostile: this is the CSRF check, and #103 generated the token and then
    /// never compared it.
    case stateMismatch
    case malformed(Reason)

    enum Reason: Equatable {
        case notAURL
        case noQueryParameters
        case missingCode
        case duplicateParameter(String)
        case unexpectedCallbackScheme
    }
}

extension OIDCCallbackResult: CustomDebugStringConvertible {
    /// Never includes the authorization code. A code in a log or a crash report
    /// is a credential in a log or a crash report, and `print("\(result)")` is
    /// exactly the kind of line that slips through review.
    var debugDescription: String {
        switch self {
        case .success:
            "OIDCCallbackResult.success(code: <redacted>)"
        case let .providerError(error, description):
            "OIDCCallbackResult.providerError(\(error), \(description ?? "no description"))"
        case .stateMismatch:
            "OIDCCallbackResult.stateMismatch"
        case let .malformed(reason):
            "OIDCCallbackResult.malformed(\(reason))"
        }
    }
}

/// Reasons the app cannot start an OIDC login with a given provider.
///
/// These are all "this server is configured in a way we cannot use", not
/// transient failures, so they are worth distinguishing from `NetworkError`.
enum OIDCLoginError: LocalizedError, Equatable {
    case invalidAuthorizationEndpoint
    case insecureAuthorizationEndpoint
    case missingClientID

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationEndpoint:
            String(
                localized: "This server's single sign-on address doesn't look right. Check the provider setup on your server."
            )
        case .insecureAuthorizationEndpoint:
            String(
                localized: "Single sign-on needs an https address. Your server is offering an insecure one, which iOS will not open."
            )
        case .missingClientID:
            String(
                localized: "This server's single sign-on provider is missing a client ID. Check the provider setup on your server."
            )
        }
    }
}

enum OIDCLogin {
    /// Generates a CSRF token for the `state` parameter.
    ///
    /// Compared against the value on the callback. This is the check PR #103
    /// generated a token for and then never performed.
    static func generateState() -> String {
        randomToken()
    }

    /// Generates a `nonce` for the authorization request.
    ///
    /// Distinct from `state` and solving a different problem: `state` protects
    /// the callback against CSRF, `nonce` binds the resulting ID token to this
    /// one request so a captured token cannot be replayed into a later one.
    ///
    /// Providers enforce a floor on this. Authelia rejects a short value with
    /// `insufficient_entropy`, which surfaces only at the token exchange, well
    /// after the user has finished logging in and looks like a server fault.
    /// 32 bytes is far above any provider's threshold.
    ///
    /// Never pass the same value for both: reusing one token for two
    /// independent protections means a leak of either defeats both.
    static func generateNonce() -> String {
        randomToken()
    }

    /// 32 bytes from the system CSPRNG, base64url encoded so it survives a
    /// round trip through a query string untouched.
    private static func randomToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // SecRandomCopyBytes does not fail in practice. If it ever does,
            // falling back to a weaker source would silently downgrade both the
            // CSRF and replay protections to nothing, so refuse instead.
            fatalError("SecRandomCopyBytes failed with status \(status)")
        }
        return Data(bytes).base64URLEncodedString()
    }

    /// Builds the authorization URL to hand to `ASWebAuthenticationSession`.
    ///
    /// Vikunja supplies only the resolved authorization endpoint in
    /// `provider.authUrl`, taken from the provider's discovery document, so the
    /// app supplies everything else.
    ///
    /// - Parameters:
    ///   - provider: as advertised by `GET /api/v1/info`.
    ///   - redirectURI: must match the value later sent to Vikunja's callback
    ///     byte for byte, or the token exchange fails with `invalid_grant`.
    ///   - state: from `generateState()`, compared on the way back.
    ///   - nonce: from `generateNonce()`, and a different value from `state`.
    static func authorizationURL(
        for provider: OIDCProvider,
        redirectURI: String,
        state: String,
        nonce: String
    ) throws -> URL {
        // `host` is non-nil but empty for input like "https://", so checking
        // for nil alone would let a hostless URL through.
        guard var components = URLComponents(string: provider.authUrl),
              let host = components.host, !host.isEmpty
        else {
            throw OIDCLoginError.invalidAuthorizationEndpoint
        }

        // Sending an authorization request in clear text would expose the code
        // in transit. iOS App Transport Security would refuse to load it anyway,
        // so failing here gives a better message than a generic network error.
        guard components.scheme?.lowercased() == "https" else {
            throw OIDCLoginError.insecureAuthorizationEndpoint
        }

        guard let clientID = provider.clientId, !clientID.isEmpty else {
            throw OIDCLoginError.missingClientID
        }

        // Some providers publish an authorization endpoint that already carries
        // query parameters. Append rather than replace, so they survive.
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: provider.scope ?? defaultScope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
        ])
        components.queryItems = items

        guard let url = components.url else {
            throw OIDCLoginError.invalidAuthorizationEndpoint
        }
        return url
    }

    /// The URL scheme the app claims, already registered in `mDone/Info.plist`
    /// for the widget deep links `mdone://focus` and `mdone://create`.
    static let callbackScheme = "mdone"

    /// The one callback URI, threaded through the authorization request, the
    /// callback check and Vikunja's token exchange. All three have to agree
    /// byte for byte or the exchange fails with `invalid_grant`, so this is a
    /// constant rather than something rebuilt at each call site.
    ///
    /// A single fixed URI rather than one per provider keeps the instruction to
    /// self-hosters the same however many providers they run: add
    /// `mdone://oidc-callback` to the Vikunja client at your identity provider.
    static let redirectURI = "mdone://oidc-callback"

    /// Used when the server does not advertise a scope. Vikunja normally does.
    static let defaultScope = "openid profile email"

    /// Parses the redirect the provider sends back to the app.
    ///
    /// Order matters. `state` is checked before anything else is trusted, so a
    /// forged callback cannot get as far as being reported as a provider error
    /// or having its code read. RFC 6749 requires the provider to echo `state`
    /// on error responses too, so this is safe for real providers and strict
    /// for everyone else.
    ///
    /// - Parameters:
    ///   - url: the redirect URL handed back by the auth session.
    ///   - expectedState: the value from `generateState()` for this attempt.
    ///   - expectedScheme: the registered callback scheme, when there is one.
    static func parseCallback(
        _ url: URL,
        expectedState: String,
        expectedScheme: String? = nil
    ) -> OIDCCallbackResult {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .malformed(.notAURL)
        }

        if let expectedScheme, components.scheme?.lowercased() != expectedScheme.lowercased() {
            return .malformed(.unexpectedCallbackScheme)
        }

        guard let items = components.queryItems, !items.isEmpty else {
            return .malformed(.noQueryParameters)
        }

        // A repeated parameter is ambiguous, and which copy wins is a parser
        // detail an attacker can aim at. Refuse rather than pick.
        for key in ["code", "state", "error"] where items.filter({ $0.name == key }).count > 1 {
            return .malformed(.duplicateParameter(key))
        }

        let value = { (name: String) -> String? in
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let state = value("state"), state == expectedState else {
            return .stateMismatch
        }

        // Checked before `code`, so a response carrying both is treated as the
        // failure it is rather than the success it pretends to be.
        if let error = value("error") {
            return .providerError(error: error, description: value("error_description"))
        }

        guard let code = value("code") else {
            return .malformed(.missingCode)
        }

        return .success(code: code)
    }
}

extension Data {
    /// base64url per RFC 4648 section 5, unpadded.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
