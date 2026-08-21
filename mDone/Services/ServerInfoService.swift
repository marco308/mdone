import Foundation

/// Reads `GET /api/v1/info` from a server the app has no credentials for, so
/// the setup screen can adapt to the auth methods that server actually offers.
///
/// Deliberately does **not** default to `APIClient.shared` the way the other
/// services do. Probing through the shared client would overwrite the signed-in
/// user's server URL and token with a half-typed hostname and an empty token on
/// every keystroke, and a 401 from the probe would run through
/// `executeWithRefresh` and could fire `onSessionExpired`, tearing down a
/// perfectly good session.
actor ServerInfoService {
    private let apiClient: APIClient

    init(apiClient: APIClient? = nil) {
        self.apiClient = apiClient ?? APIClient(session: ServerInfoService.probeSession())
    }

    /// Fetches the instance info. Throws like any other API call; callers on the
    /// setup screen should treat a failure as "we do not know" and fall back to
    /// `AuthOptions.unknownServer` rather than blocking the user.
    func fetch(from serverURL: URL) async throws -> ServerInfo {
        await apiClient.configure(serverURL: serverURL.absoluteString, token: "")
        return try await apiClient.fetch(Endpoint.info)
    }

    /// `APIClient` stamps its own 20s timeout on every request and retries
    /// connection failures three times with 1s, 2s and 4s backoff. Against a
    /// host that silently drops packets that is well over a minute before the
    /// setup screen hears anything. `timeoutIntervalForResource` is the only
    /// knob that bounds the whole ladder from outside.
    private static func probeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }
}
