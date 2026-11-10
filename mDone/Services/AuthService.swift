import Foundation
import Security

actor AuthService {
    static let shared = AuthService()

    private let serverURLKey = "com.mdone.serverURL"
    private let tokenKeychainKey = StorageScope.keychainAccount("com.mdone.apiToken")
    private let refreshTokenKeychainKey = StorageScope.keychainAccount("com.mdone.refreshToken")

    /// The server URL lives here rather than in `UserDefaults.standard`
    /// directly so that unit tests get a scratch copy (see `StorageScope`).
    nonisolated private var defaults: UserDefaults {
        StorageScope.appDefaults
    }

    init() {
        // The keychain outlives a test process, unlike the scratch defaults,
        // so a test run starts by clearing what the last one left.
        if StorageScope.isHostingUnitTests {
            clearSession()
        }
    }

    // MARK: - Server URL (UserDefaults)

    nonisolated func getServerURL() -> String? {
        defaults.string(forKey: serverURLKey)
    }

    nonisolated func saveServerURL(_ url: String) {
        defaults.set(url, forKey: serverURLKey)
        SharedKeys.sharedDefaults.set(url, forKey: SharedKeys.serverURLKey)
    }

    nonisolated func clearServerURL() {
        defaults.removeObject(forKey: serverURLKey)
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.serverURLKey)
    }

    // MARK: - API Token (Keychain)

    nonisolated func getToken() -> String? {
        readKeychain(account: tokenKeychainKey)
    }

    nonisolated func saveToken(_ token: String) {
        writeKeychain(account: tokenKeychainKey, value: token)
        SharedTokenStore.save(token)
    }

    nonisolated func deleteToken() {
        deleteKeychain(account: tokenKeychainKey)
        SharedTokenStore.delete()
    }

    // MARK: - Refresh Token (Keychain)

    nonisolated func getRefreshToken() -> String? {
        readKeychain(account: refreshTokenKeychainKey)
    }

    nonisolated func saveRefreshToken(_ token: String) {
        writeKeychain(account: refreshTokenKeychainKey, value: token)
    }

    nonisolated func deleteRefreshToken() {
        deleteKeychain(account: refreshTokenKeychainKey)
    }

    // MARK: - Auth State

    nonisolated func isAuthenticated() -> Bool {
        getServerURL() != nil && getToken() != nil
    }

    /// Clears the session credentials (JWT + refresh token) but keeps the
    /// server URL so the user only has to re-enter their password. Use this
    /// when the session expires unexpectedly; use `clearAll()` for a deliberate
    /// user-initiated logout.
    nonisolated func clearSession() {
        deleteToken()
        deleteRefreshToken()
    }

    nonisolated func clearAll() {
        clearServerURL()
        clearSession()
    }

    // MARK: - Keychain helpers

    nonisolated private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    nonisolated private func writeKeychain(account: String, value: String) {
        deleteKeychain(account: account)

        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    nonisolated private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
