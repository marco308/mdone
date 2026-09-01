import Foundation

struct LoginRequest: Encodable {
    var username: String
    var password: String
}

struct LoginResponse: Codable {
    var token: String
}

/// Body of `POST /api/v1/auth/openid/{key}/callback`.
///
/// `redirectUrl` becomes `redirect_url` through the client's
/// `convertToSnakeCase` strategy, so do not add `CodingKeys` here without
/// matching it. Vikunja forwards the value as the `redirect_uri` of the token
/// exchange, so it must equal the one used on the authorization request or the
/// provider rejects the grant.
struct OIDCCallbackRequest: Encodable {
    var code: String
    var redirectUrl: String
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
    case timeout
    case serverUnreachable
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "The server URL doesn't look right. Please check it in Settings.")
        case .unauthorized:
            String(localized: "Your session has expired. Please log in again.")
        case let .serverError(code, _):
            if code >= 500 {
                String(localized: "The server is having trouble. Please try again in a moment.")
            } else {
                String(localized: "Something went wrong with that request. Please try again.")
            }
        case .decodingError:
            String(localized: "We received an unexpected response from the server. Please try again.")
        case .networkUnavailable:
            String(localized: "You're offline. Your changes will sync when you're back online.")
        case .rateLimited:
            String(localized: "Server is busy. Please try again later.")
        case .timeout:
            String(localized: "The request timed out. Please check your connection and try again.")
        case .serverUnreachable:
            String(localized: "Can't reach the server. Please check your connection and server URL.")
        case .unknown:
            String(localized: "Something went wrong. Please check your connection and try again.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            String(localized: "Open Settings and verify your server URL starts with https:// or http://.")
        case .unauthorized:
            String(localized: "Go to Settings and sign in with your credentials or a new API token.")
        case let .serverError(code, _):
            if code >= 500 {
                String(localized: "The server may be temporarily unavailable. Wait a moment and try again.")
            } else {
                String(localized: "If this keeps happening, try logging out and back in.")
            }
        case .decodingError:
            String(localized: "Make sure your server is running a compatible version of Vikunja.")
        case .networkUnavailable:
            String(localized: "Check that Wi-Fi or cellular data is turned on.")
        case .rateLimited:
            String(localized: "The server is rate limiting requests. Wait a moment and try again.")
        case .timeout:
            String(localized: "Try moving closer to your router or switching to a different network.")
        case .serverUnreachable:
            String(localized: "Verify the server is running and the URL in Settings is correct.")
        case .unknown:
            String(localized: "Try again. If the problem persists, check your internet connection or restart the app.")
        }
    }

    /// The SF Symbol icon name appropriate for this error type.
    var iconName: String {
        switch self {
        case .invalidURL:
            "link.badge.plus"
        case .unauthorized:
            "lock.slash"
        case .serverError:
            "exclamationmark.icloud"
        case .decodingError:
            "doc.questionmark"
        case .networkUnavailable:
            "wifi.slash"
        case .rateLimited:
            "hourglass"
        case .timeout:
            "clock.badge.exclamationmark"
        case .serverUnreachable:
            "server.rack"
        case .unknown:
            "exclamationmark.triangle"
        }
    }

    /// Whether this error is critical and requires user action (should not auto-dismiss).
    var isCritical: Bool {
        switch self {
        case .unauthorized, .invalidURL:
            true
        default:
            false
        }
    }

    /// Creates a `NetworkError` from a `URLError`, mapping common codes to friendly variants.
    static func from(_ urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            .networkUnavailable
        case .timedOut:
            .timeout
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            .serverUnreachable
        default:
            .unknown(urlError)
        }
    }

    /// Creates a user-friendly `NetworkError` from any `Error`.
    static func friendly(from error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            networkError
        } else if let urlError = error as? URLError {
            NetworkError.from(urlError)
        } else {
            .unknown(error)
        }
    }
}

struct PaginationInfo {
    var totalPages: Int
    var resultCount: Int
}
