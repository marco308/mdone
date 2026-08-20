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
