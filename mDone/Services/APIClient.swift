import Foundation

actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var serverURL: String?
    private var apiToken: String?

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

    func fetch<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = try buildRequest(for: endpoint)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NetworkError.decodingError(error)
            }
        case 401:
            throw NetworkError.unauthorized
        default:
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: apiError?.message)
        }
    }

    func send<R: Decodable>(_ endpoint: Endpoint, body: some Encodable) async throws -> R {
        var request = try buildRequest(for: endpoint)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            do {
                return try decoder.decode(R.self, from: data)
            } catch {
                throw NetworkError.decodingError(error)
            }
        case 401:
            throw NetworkError.unauthorized
        default:
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: apiError?.message)
        }
    }

    func sendExpectingEmpty(_ endpoint: Endpoint, body: some Encodable) async throws {
        var request = try buildRequest(for: endpoint)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return
        case 401:
            throw NetworkError.unauthorized
        default:
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: apiError?.message)
        }
    }

    /// Sends a request with pre-encoded JSON body data. Used for replaying pending offline operations.
    func sendRawData(_ endpoint: Endpoint, bodyData: Data?) async throws {
        var request = try buildRequest(for: endpoint)
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return
        case 401:
            throw NetworkError.unauthorized
        default:
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: apiError?.message)
        }
    }

    func delete(_ endpoint: Endpoint) async throws {
        let request = try buildRequest(for: endpoint)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            return
        case 401:
            throw NetworkError.unauthorized
        default:
            let apiError = try? decoder.decode(APIError.self, from: data)
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, message: apiError?.message)
        }
    }
}
