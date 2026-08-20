import Foundation

/// Normalization and validation for the server URL the user types on the setup
/// screen.
///
/// This used to live inline in `ServerSetupView.connect()`. It is pure and
/// branchy, which makes it both a common source of "why won't it connect" and a
/// cheap thing to test.
enum ServerURL {
    /// Cleans up what the user typed and returns a URL the API client can use,
    /// or nil if it cannot be made sense of.
    ///
    /// Trims whitespace, defaults a missing scheme to https, and drops trailing
    /// slashes so callers can append paths without doubling up.
    static func normalized(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // A bare "vikunja.example.com" is the common case, and the safe default
        // for a missing scheme is https, never http.
        if !text.contains("://") {
            text = "https://" + text
        }

        // Trailing slashes would produce "//api/v1/..." once a path is appended.
        while text.hasSuffix("/") {
            text.removeLast()
        }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              isValidHost(host)
        else {
            return nil
        }

        return components.url
    }

    /// Whether the text can be turned into a usable server URL.
    static func isValid(_ raw: String) -> Bool {
        normalized(raw) != nil
    }

    /// Self-hosted servers legitimately live on `localhost`, raw IP addresses
    /// and single-label intranet names, so those are all allowed. The point of
    /// this check is to catch typos and non-hostnames, not to enforce public DNS.
    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty, !host.contains(" ") else { return false }

        // IPv6 literals arrive from URLComponents already stripped of brackets.
        if host.contains(":") {
            return true
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty }) else { return false }

        // "localhost", "vikunja", or an IPv4 literal.
        if labels.count == 1 {
            return labels[0].allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }

        if isIPv4(host) {
            return true
        }

        // A dotted name needs a plausible TLD. A single character is always a
        // typo, most often a missing character rather than a real suffix.
        guard let tld = labels.last, tld.count >= 2 else { return false }
        return tld.allSatisfy(\.isLetter)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), part.count <= 3, !part.isEmpty else { return false }
            return (0 ... 255).contains(value)
        }
    }
}
