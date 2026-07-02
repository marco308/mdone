import Foundation
import Security

/// Keychain-backed store for the Vikunja API token shared between the main
/// app and the widget extension. Replaces the old copy in the app group
/// UserDefaults — preferences are written to disk in cleartext, so the token
/// now lives in a keychain item instead.
///
/// On iOS the app group ID (`group.com.mdone.app`) doubles as a keychain
/// access group, so both the app and the widget extension can read the item
/// without extra entitlements. On macOS there is no widget extension, so the
/// item stays in the app's own keychain (no access group).
enum SharedTokenStore {
    private static let account = "com.mdone.shared.apiToken"

    private static var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        #if os(iOS)
        query[kSecAttrAccessGroup as String] = SharedKeys.appGroupID
        #endif
        return query
    }

    static func get() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return migrateLegacyToken()
    }

    static func save(_ token: String) {
        delete()
        guard let data = token.data(using: .utf8) else { return }
        var query = baseQuery
        // AfterFirstUnlock so widget refreshes keep working after a reboot
        // once the device has been unlocked; same policy as AuthService.
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        // Scrub the pre-1.6.3 cleartext copy wherever it might still linger.
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.apiTokenKey)
    }

    /// Releases before 1.6.3 kept the token in the app group UserDefaults.
    /// Move it into the keychain the first time the app or the widget looks
    /// for it; `save` also removes the cleartext copy.
    private static func migrateLegacyToken() -> String? {
        guard let legacy = SharedKeys.sharedDefaults.string(forKey: SharedKeys.apiTokenKey) else {
            return nil
        }
        save(legacy)
        return legacy
    }
}
