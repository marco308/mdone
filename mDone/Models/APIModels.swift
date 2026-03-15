import Foundation

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
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .unauthorized:
            return "Authentication failed. Please check your API token."
        case .serverError(let code, let message):
            return message ?? "Server error (\(code))"
        case .decodingError:
            return "Failed to parse server response"
        case .networkUnavailable:
            return "No internet connection"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

struct PaginationInfo {
    var totalPages: Int
    var resultCount: Int
}
