import Foundation

actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var serverURL: String?
    private var apiToken: String?

    /// Whether a request is currently being retried after a transient failure.
    /// Callers can observe this to show retry state in the UI.
    private(set) var isRetrying: Bool = false

    private let maxRetries = 3
    private let baseRetryDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

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

    func configure(serverURL: String, token: String) {
        self.serverURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        apiToken = token
    }

    func clearCredentials() {
        serverURL = nil
        apiToken = nil
    }

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

    // MARK: - Public API

    func fetch<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = try buildRequest(for: endpoint)
        let (data, httpResponse) = try await performRequest(request)
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
            let request = try buildRequest(for: endpoint)
            let (data, httpResponse) = try await performRequest(request)
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
        var request = try buildRequest(for: endpoint)
        request.httpBody = try encoder.encode(body)

        let (data, httpResponse) = try await performRequest(request)
        let responseData = try handleResponse(data: data, httpResponse: httpResponse)

        do {
            return try decoder.decode(R.self, from: responseData)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }

    func sendExpectingEmpty(_ endpoint: Endpoint, body: some Encodable) async throws {
        var request = try buildRequest(for: endpoint)
        request.httpBody = try encoder.encode(body)

        let (data, httpResponse) = try await performRequest(request)
        _ = try handleResponse(data: data, httpResponse: httpResponse)
    }

    /// Sends a request with pre-encoded JSON body data. Used for replaying pending offline operations.
    func sendRawData(_ endpoint: Endpoint, bodyData: Data?) async throws {
        var request = try buildRequest(for: endpoint)
        request.httpBody = bodyData

        let (data, httpResponse) = try await performRequest(request)
        _ = try handleResponse(data: data, httpResponse: httpResponse)
    }

    func delete(_ endpoint: Endpoint) async throws {
        let request = try buildRequest(for: endpoint)
        let (data, httpResponse) = try await performRequest(request)
        _ = try handleResponse(data: data, httpResponse: httpResponse)
    }
}
