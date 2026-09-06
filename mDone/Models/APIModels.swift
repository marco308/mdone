import Foundation

/// Body of `POST /api/v1/login`.
///
/// `totpPasscode` becomes `totp_passcode` through the client's
/// `convertToSnakeCase` strategy. It is optional and omitted when nil: Vikunja
/// ignores the field for an account without two-factor turned on (verified on
/// v2.4.0), and answers 412 with error code 1017 when the account has it on and
/// the passcode is missing, empty or wrong (issue #179).
struct LoginRequest: Encodable {
    var username: String
    var password: String
    var totpPasscode: String?

    init(username: String, password: String, totpPasscode: String? = nil) {
        self.username = username
        self.password = password
        self.totpPasscode = totpPasscode
    }
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

    /// Vikunja error codes the app reacts to by name. The full list lives in
    /// `pkg/models/error.go` and `pkg/user/error.go` upstream.
    enum Code {
        /// `ErrCodeWrongUsernameOrPassword`, sent as HTTP 403.
        static let wrongUsernameOrPassword = 1011
        /// `ErrCodeInvalidTOTPPasscode`, sent as HTTP 412. Vikunja uses the
        /// same code whether the passcode was wrong or never sent.
        static let invalidTOTPPasscode = 1017
    }
}

enum NetworkError: LocalizedError {
    case invalidURL
    case unauthorized
    /// `POST /login` refused the username or password.
    case invalidCredentials
    /// `POST /login` wanted a two-factor passcode and none was sent. Vikunja
    /// reports this with the same error code as a wrong passcode; the split is
    /// made by the caller, which knows whether it sent one (issue #179).
    case totpRequired
    /// `POST /login` rejected the two-factor passcode that was sent.
    case invalidTOTPPasscode
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
        case .invalidCredentials:
            String(localized: "Wrong username or password.")
        case .totpRequired:
            String(
                localized: "This account has two-factor authentication turned on. Enter the code from your authenticator app to sign in."
            )
        case .invalidTOTPPasscode:
            String(
                localized: "That two-factor code wasn't accepted. Codes change every 30 seconds, so check your authenticator app and try again."
            )
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
        case .invalidCredentials:
            String(localized: "Check your username and password and try again.")
        case .totpRequired:
            String(localized: "Open your authenticator app and enter the current six-digit code.")
        case .invalidTOTPPasscode:
            String(localized: "Make sure your device's clock is correct, then enter a fresh code.")
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
        case .invalidCredentials:
            "person.badge.key"
        case .totpRequired, .invalidTOTPPasscode:
            "lock.shield"
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

    /// Failures that mean the server could not be reached at all, as opposed
    /// to reaching it and being refused. A change that hits one of these is
    /// safe to queue and replay later.
    var isConnectivityFailure: Bool {
        switch self {
        case .networkUnavailable, .timeout, .serverUnreachable:
            true
        default:
            false
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

    /// Turns a non-2xx response into the error the caller should see.
    ///
    /// Most responses become `.serverError`, which carries the status and the
    /// server's message. The two Vikunja login refusals get their own cases so
    /// the setup screen can react to them (issue #179): a 403 with code 1011 is
    /// a wrong username or password, a 412 with code 1017 is a two-factor
    /// passcode problem. Both come only from `POST /login`.
    static func fromResponse(statusCode: Int, apiError: APIError?) -> NetworkError {
        switch apiError?.code {
        case APIError.Code.wrongUsernameOrPassword:
            .invalidCredentials
        case APIError.Code.invalidTOTPPasscode:
            .invalidTOTPPasscode
        default:
            .serverError(statusCode: statusCode, message: apiError?.message)
        }
    }

    /// Reinterprets a login failure knowing whether a passcode was sent.
    ///
    /// Vikunja answers a missing passcode and a wrong one with the same error,
    /// but the user needs different things from each: the first reveals the
    /// two-factor field, the second asks for a fresh code.
    func forCredentialLogin(sentPasscode: Bool) -> NetworkError {
        if case .invalidTOTPPasscode = self, !sentPasscode {
            return .totpRequired
        }
        return self
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
