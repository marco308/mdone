import Foundation
import Security

/// Storage for the focus-service URL + token. Kept strictly separate from
/// `AuthService` (Vikunja credentials) per the upstream CLAUDE.md — a
/// focus-service token leak must not touch Vikunja data, and vice versa.
///
/// URL lives in UserDefaults (non-sensitive), token in Keychain
/// (sensitive). Blank URL means the feature is off; no toggle needed.
enum FocusSyncConfig {
    private static let urlKey = "com.mdone.focusSync.serverURL"
    private static let tokenAccount = "com.mdone.focusSync.token"

    // MARK: - Server URL

    static func getServerURL() -> String? {
        let trimmed = UserDefaults.standard.string(forKey: urlKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func saveServerURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearServerURL()
        } else {
            UserDefaults.standard.set(trimmed, forKey: urlKey)
        }
    }

    static func clearServerURL() {
        UserDefaults.standard.removeObject(forKey: urlKey)
    }

    // MARK: - Token (Keychain)

    static func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteToken()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Convenience

    /// True when both URL and token are present *and* the URL is well-formed
    /// (http/https scheme + non-empty host). Settings UI uses this to decide
    /// whether to show "Configured" — a bare hostname like `focus.example.com`
    /// parses as a URL but URLSession can't deliver to it, so we treat that
    /// as unconfigured rather than letting the user think sync is on.
    static func isConfigured() -> Bool {
        focusEventsURL() != nil && getToken() != nil
    }

    /// Returns a URL pointing at `/focus-events` on the configured server, or
    /// nil if the feature is unconfigured / the URL is malformed.
    static func focusEventsURL() -> URL? {
        guard let base = getServerURL(),
              let baseURL = URL(string: base),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = baseURL.host, !host.isEmpty
        else {
            return nil
        }
        return baseURL.appendingPathComponent("focus-events")
    }
}
