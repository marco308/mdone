import Foundation
import Security

/// Keychain-backed store for the Vikunja API token shared between the main
/// app and the widget extension. Replaces the old copy in the app group
/// UserDefaults — preferences are written to disk in cleartext, so the token
/// now lives in a keychain item instead.
///
/// On iOS the app group ID (`group.com.mdone.app`) doubles as a keychain
/// access group — Apple includes `com.apple.security.application-groups`
/// entries in an app's keychain access group list, so both the app and the
/// widget extension can read the item without a keychain-sharing entitlement
/// (see "Sharing access to keychain items among a collection of apps").
/// On macOS app groups don't work that way, but there is no widget extension
/// either, so the item stays in the app's own keychain (no access group).
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
        // Migrate only when the item is genuinely absent. Any other status
        // (entitlement or configuration problems) must not touch the legacy
        // copy — it may be the only working credential source.
        guard status == errSecItemNotFound else { return nil }
        return migrateLegacyToken()
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        // Update-or-add so a failed write can never leave us with no token at
        // all; the old item stays in place unless the new value lands.
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            // AfterFirstUnlock so widget refreshes keep working after a reboot
            // once the device has been unlocked; same policy as AuthService.
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else { return false }
        // Scrub the pre-1.6.3 cleartext copy only once the keychain write
        // actually succeeded, so the token is never lost from both places.
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.apiTokenKey)
        return true
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        // Deliberate credential removal (logout/session expiry): scrub the
        // pre-1.6.3 cleartext copy too, wherever it might still linger.
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.apiTokenKey)
    }

    /// Releases before 1.6.3 kept the token in the app group UserDefaults.
    /// Move it into the keychain the first time the app or the widget looks
    /// for it; `save` removes the cleartext copy once the keychain write
    /// succeeds, and leaves it in place otherwise so the credential survives.
    private static func migrateLegacyToken() -> String? {
        guard let legacy = SharedKeys.sharedDefaults.string(forKey: SharedKeys.apiTokenKey) else {
            return nil
        }
        save(legacy)
        return legacy
    }
}
