import Foundation

/// Lightweight JWT inspection. Only used to decide whether a token is a JWT
/// (and therefore eligible for refresh-on-401) and to read its expiry. We
/// never verify the signature — the server is the only thing that can do that.
enum JWTHelpers {
    /// Vikunja API tokens (created in the user's settings UI) start with `tk_`
    /// and are non-expiring. Anything else returned by `/api/v1/login` is a JWT.
    static func isJWT(_ token: String) -> Bool {
        if token.hasPrefix("tk_") {
            return false
        }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }
        return decodePayload(segments[1]) != nil
    }

    /// Reads the `exp` claim and returns it as a `Date`. Returns nil if the
    /// token isn't a JWT, the payload isn't valid base64url JSON, or there's
    /// no `exp` claim.
    static func parseExpiry(_ token: String) -> Date? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let payload = decodePayload(segments[1]),
              let exp = payload["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - Internal

    private static func decodePayload(_ segment: Substring) -> [String: Any]? {
        guard let data = base64URLDecode(String(segment)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // JWT segments are unpadded base64url; restore the padding before decoding.
        let remainder = s.count % 4
        if remainder > 0 {
            s.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: s)
    }
}
