import Foundation
import Security

actor AuthService {
    static let shared = AuthService()

    private let serverURLKey = "com.mdone.serverURL"
    private let tokenKeychainKey = "com.mdone.apiToken"

    // MARK: - Server URL (UserDefaults)

    nonisolated func getServerURL() -> String? {
        UserDefaults.standard.string(forKey: serverURLKey)
    }

    nonisolated func saveServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: serverURLKey)
        SharedKeys.sharedDefaults.set(url, forKey: SharedKeys.serverURLKey)
    }

    nonisolated func clearServerURL() {
        UserDefaults.standard.removeObject(forKey: serverURLKey)
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.serverURLKey)
    }

    // MARK: - API Token (Keychain)

    nonisolated func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
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

    nonisolated func saveToken(_ token: String) {
        deleteToken()

        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)

        // Also persist to shared App Group UserDefaults so widgets can access it
        SharedKeys.sharedDefaults.set(token, forKey: SharedKeys.apiTokenKey)
    }

    nonisolated func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
        ]

        SecItemDelete(query as CFDictionary)

        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.apiTokenKey)
    }

    // MARK: - Auth State

    nonisolated func isAuthenticated() -> Bool {
        getServerURL() != nil && getToken() != nil
    }

    nonisolated func clearAll() {
        clearServerURL()
        deleteToken()
    }
}
