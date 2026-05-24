import Foundation

actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var serverURL: String?
    private var apiToken: String?
    private var refreshToken: String?
    private var isJWTSession: Bool = false

    /// Whether a request is currently being retried after a transient failure.
    /// Callers can observe this to show retry state in the UI.
    private(set) var isRetrying: Bool = false

    private let maxRetries = 3
    private let baseRetryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds
    private static let refreshCookieName = "vikunja_refresh_token"

    /// Fired when the access token (and optionally its refresh cookie) change
    /// because of a `/login` response or a refresh-on-401. Callers should
    /// persist both to the keychain so the new credentials survive relaunch.
    private var onTokensUpdated: (@Sendable (_ token: String, _ refreshToken: String?) -> Void)?

    /// Fired when a 401 cannot be recovered via refresh (no refresh token,
    /// API-token session, or refresh itself returned 401). Callers should
    /// clear the session and present the login screen.
    private var onSessionExpired: (@Sendable () -> Void)?

    /// Deduplicates concurrent refresh attempts. The first 401-handler kicks
    /// off the refresh; subsequent handlers `await` the same task instead of
    /// racing each other with the now-invalidated cookie.
    private var inFlightRefresh: Task<Void, Error>?

    static let shared = APIClient()

    init(session: URLSession = .shared) {
        self.session = session

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if dateString == "0001-01-01T00:00:00Z" {
                return Date.distantPast
            }
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    func configure(serverURL: String, token: String, refreshToken: String? = nil) {
        self.serverURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        apiToken = token
        self.refreshToken = refreshToken
        isJWTSession = JWTHelpers.isJWT(token)
    }

    func clearCredentials() {
        serverURL = nil
        apiToken = nil
        refreshToken = nil
        isJWTSession = false
    }

    func setOnTokensUpdated(_ handler: @Sendable @escaping (_ token: String, _ refreshToken: String?) -> Void) {
        onTokensUpdated = handler
    }

    func setOnSessionExpired(_ handler: @Sendable @escaping () -> Void) {
        onSessionExpired = handler
    }

    /// Test/inspection hook for the currently stored refresh token.
    func currentRefreshToken() -> String? { refreshToken }

    /// Test/inspection hook for the currently stored access token.
    func currentToken() -> String? { apiToken }

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard let serverURL else { throw NetworkError.invalidURL }

        var urlString = serverURL + endpoint.path
        if let queryItems = endpoint.queryItems {
            var components = URLComponents(string: urlString)
            components?.queryItems = queryItems
            urlString = components?.url?.absoluteString ?? urlString
        }

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiToken {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Retry Logic

    /// Determines whether a given error is transient and eligible for retry.
    private func isRetryableError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Determines whether an HTTP status code is retryable (429 or 5xx).
    private func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 429 || (500 ... 599).contains(statusCode)
    }

    /// Extracts the Retry-After delay from an HTTP response, if present.
    /// Returns the delay in nanoseconds, or nil if the header is not present.
    private func retryAfterDelay(from response: HTTPURLResponse) -> UInt64? {
        guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        // Retry-After can be seconds (integer) or an HTTP-date; we handle seconds only.
        if let seconds = Double(retryAfter), seconds > 0 {
            return UInt64(seconds * 1_000_000_000)
        }
        return nil
    }

    /// Performs an HTTP request with exponential backoff retry for transient failures.
    /// Returns the raw `(Data, HTTPURLResponse)` from the successful attempt.
    private func performRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?

        for attempt in 0 ... maxRetries {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.unknown(URLError(.badServerResponse))
                }

                // Auto-capture the refresh cookie whenever the server sets it
                // (login + refresh both emit it; the old value is invalidated).
                captureRefreshCookie(from: httpResponse, requestURL: request.url)

                // If the status code is retryable and we have retries left, back off and retry.
                if isRetryableStatusCode(httpResponse.statusCode), attempt < maxRetries {
                    let delay: UInt64 = if httpResponse.statusCode == 429,
                                           let retryDelay = retryAfterDelay(from: httpResponse)
                    {
                        retryDelay
                    } else {
                        // Exponential backoff: 1s, 2s, 4s
                        baseRetryDelay * (1 << UInt64(attempt))
                    }

                    isRetrying = true
                    #if DEBUG
                    print(
                        "[mDone] Retrying request (attempt \(attempt + 1)/\(maxRetries)) after \(delay / 1_000_000_000)s — HTTP \(httpResponse.statusCode)"
                    )
                    #endif
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }

                isRetrying = false
                return (data, httpResponse)

            } catch let error as NetworkError {
                // NetworkError thrown by our own guard (e.g. bad server response) — do not retry
                isRetrying = false
                throw error
            } catch {
                if isRetryableError(error), attempt < maxRetries {
                    let delay = baseRetryDelay * (1 << UInt64(attempt))
                    isRetrying = true
                    #if DEBUG
                    print(
                        "[mDone] Retrying request (attempt \(attempt + 1)/\(maxRetries)) after \(delay / 1_000_000_000)s — \(error.localizedDescription)"
                    )
                    #endif
                    try await Task.sleep(nanoseconds: delay)
                    lastError = error
                    continue
                }

                isRetrying = false

                // Map URLError to NetworkError for non-retryable or exhausted network errors
                if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
                    throw NetworkError.networkUnavailable
                }
                throw NetworkError.unknown(error)
            }
        }

        isRetrying = false

        // All retries exhausted — surface the appropriate error
        if let lastError {
            if let urlError = lastError as? URLError, urlError.code == .notConnectedToInternet {
                throw NetworkError.networkUnavailable
            }
            throw NetworkError.unknown(lastError)
        }
        // Should not reach here, but guard against it
        throw NetworkError.unknown(URLError(.unknown))
    }

    /// Handles the HTTP response status codes and returns the data for successful responses.
    /// Throws appropriate NetworkError for error status codes.
    private func handleResponse(data: Data, httpResponse: HTTPURLResponse) throws -> Data {
        switch httpResponse.statusCode {
        case 200 ... 299:
            return data
        case 401:
            throw NetworkError.unauthorized
        case 429:
            throw NetworkError.rateLimited
        default:
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: apiError?.message)
        }
    }

    // MARK: - Refresh

    /// Runs the request once, and if it returns 401 attempts a single token
    /// refresh + retry. Falls back to surfacing `.unauthorized` and notifying
    /// `onSessionExpired` if recovery isn't possible.
    private func executeWithRefresh(
        _ build: () throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try build()
        let (data, httpResponse) = try await performRequest(request)

        // Fast path: not unauthorized, return as-is.
        if httpResponse.statusCode != 401 {
            return (data, httpResponse)
        }

        // 401 with no refresh capability — let the caller see it.
        guard isJWTSession, refreshToken != nil else {
            notifySessionExpired()
            return (data, httpResponse)
        }

        // Try to refresh the JWT once. If that fails, surface the original 401.
        // Snapshot the token we used so we can tell whether someone else
        // already refreshed for us while we were awaiting elsewhere.
        let tokenBeforeRefresh = apiToken
        do {
            try await sharedRefresh()
        } catch {
            notifySessionExpired()
            return (data, httpResponse)
        }

        // If neither our refresh nor a concurrent one updated the token, the
        // session is unrecoverable.
        guard apiToken != tokenBeforeRefresh else {
            notifySessionExpired()
            return (data, httpResponse)
        }

        // Rebuild the request so the new bearer token is attached, then retry.
        let retryRequest = try build()
        return try await performRequest(retryRequest)
    }

    /// Single-flight wrapper around `performRefresh()`. Concurrent callers
    /// `await` the same in-flight task so they don't each try to spend the
    /// already-rotated refresh cookie.
    private func sharedRefresh() async throws {
        if let inFlightRefresh {
            try await inFlightRefresh.value
            return
        }
        let task = Task<Void, Error> { [weak self] in
            guard let self else { return }
            try await self.performRefresh()
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        try await task.value
    }

    /// Calls Vikunja's refresh endpoint with the stored refresh-token cookie.
    /// Updates the stored access token (and the rotated refresh cookie) on
    /// success; throws `NetworkError.unauthorized` on failure.
    private func performRefresh() async throws {
        guard let serverURL,
              let refreshToken,
              let url = URL(string: serverURL + Endpoint.refreshToken.path)
        else {
            throw NetworkError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = Endpoint.refreshToken.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(Self.refreshCookieName)=\(refreshToken)", forHTTPHeaderField: "Cookie")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.unauthorized
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unauthorized
        }

        // Capture the rotated cookie even on non-2xx so a future attempt with
        // a valid cookie can still recover; the server invalidates the old one
        // either way.
        captureRefreshCookie(from: httpResponse, requestURL: url)

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw NetworkError.unauthorized
        }

        let loginResponse: LoginResponse
        do {
            loginResponse = try decoder.decode(LoginResponse.self, from: data)
        } catch {
            throw NetworkError.unauthorized
        }

        apiToken = loginResponse.token
        isJWTSession = JWTHelpers.isJWT(loginResponse.token)
        onTokensUpdated?(loginResponse.token, self.refreshToken)
    }

    /// Reads the `vikunja_refresh_token` cookie from a response and stores it.
    /// Callers that pair the cookie with a new access token (login, refresh)
    /// are responsible for firing `onTokensUpdated` so both get persisted.
    private func captureRefreshCookie(from response: HTTPURLResponse, requestURL: URL?) {
        guard let requestURL,
              let headers = response.allHeaderFields as? [String: String]
        else { return }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: requestURL)
        guard let cookie = cookies.first(where: { $0.name == Self.refreshCookieName }),
              !cookie.value.isEmpty,
              cookie.value != refreshToken
        else { return }
        refreshToken = cookie.value
    }

    private func notifySessionExpired() {
        guard let handler = onSessionExpired else { return }
        // Drop the refresh token so we don't loop forever on the same 401.
        refreshToken = nil
        handler()
    }

    // MARK: - Public API

    func fetch<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let (data, httpResponse) = try await executeWithRefresh { try self.buildRequest(for: endpoint) }
        let responseData = try handleResponse(data: data, httpResponse: httpResponse)

        do {
            return try decoder.decode(T.self, from: responseData)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    /// Fetches all pages of a paginated endpoint and returns the combined results.
    func fetchAllPages<T: Decodable>(
        _ endpointBuilder: (Int, Int) -> Endpoint,
        perPage: Int = 100
    ) async throws -> [T] {
        var allItems: [T] = []
        var page = 1

        while true {
            let endpoint = endpointBuilder(page, perPage)
            let (data, httpResponse) = try await executeWithRefresh { try self.buildRequest(for: endpoint) }
            let responseData = try handleResponse(data: data, httpResponse: httpResponse)

            let items: [T]
            do {
                items = try decoder.decode([T].self, from: responseData)
            } catch {
                throw NetworkError.decodingError(error)
            }
            allItems.append(contentsOf: items)

            let totalPages = Int(httpResponse.value(forHTTPHeaderField: "x-pagination-total-pages") ?? "1") ?? 1
            if page >= totalPages || items.isEmpty {
                return allItems
            }
            page += 1
        }
    }

    func send<R: Decodable>(_ endpoint: Endpoint, body: some Encodable) async throws -> R {
        let bodyData = try encoder.encode(body)
        let (data, httpResponse) = try await executeWithRefresh {
            var request = try self.buildRequest(for: endpoint)
            request.httpBody = bodyData
            return request
        }
        let responseData = try handleResponse(data: data, httpResponse: httpResponse)

        do {
            return try decoder.decode(R.self, from: responseData)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    func sendExpectingEmpty(_ endpoint: Endpoint, body: some Encodable) async throws {
        let bodyData = try encoder.encode(body)
        let (data, httpResponse) = try await executeWithRefresh {
            var request = try self.buildRequest(for: endpoint)
            request.httpBody = bodyData
            return request
        }
        _ = try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Sends a request with pre-encoded JSON body data. Used for replaying pending offline operations.
    func sendRawData(_ endpoint: Endpoint, bodyData: Data?) async throws {
        let (data, httpResponse) = try await executeWithRefresh {
            var request = try self.buildRequest(for: endpoint)
            request.httpBody = bodyData
            return request
        }
        _ = try handleResponse(data: data, httpResponse: httpResponse)
    }

    func delete(_ endpoint: Endpoint) async throws {
        let (data, httpResponse) = try await executeWithRefresh { try self.buildRequest(for: endpoint) }
        _ = try handleResponse(data: data, httpResponse: httpResponse)
    }
}
