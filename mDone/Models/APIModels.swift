import Foundation

struct LoginRequest: Encodable {
    var username: String
    var password: String
}

struct LoginResponse: Codable {
    var token: String
}

struct APIError: Codable {
    var code: Int?
    var message: String?
}

enum NetworkError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkUnavailable
    case rateLimited
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid server URL"
        case .unauthorized:
            "Authentication failed. Please check your API token."
        case let .serverError(code, message):
            message ?? "Server error (\(code))"
        case .decodingError:
            "Failed to parse server response"
        case .networkUnavailable:
            "No internet connection"
        case .rateLimited:
            "Server is busy. Please try again later."
        case let .unknown(error):
            error.localizedDescription
        }
    }
}

struct PaginationInfo {
    var totalPages: Int
    var resultCount: Int
}
