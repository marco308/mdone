import AuthenticationServices
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum WebAuthenticationError: LocalizedError, Equatable {
    /// The user dismissed the browser or declined the system consent alert.
    /// Not worth showing: the UI should simply go quiet.
    case cancelled
    /// `start()` refused, which in practice means a missing or dead
    /// presentation anchor.
    case cannotStart
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            nil
        case .cannotStart:
            String(localized: "Couldn't open the sign-in window. Please try again.")
        case let .failed(message):
            message
        }
    }
}

/// The seam that keeps the login flow testable.
///
/// `ASWebAuthenticationSession` presents system UI and cannot run in a unit
/// test, so everything above this protocol can be exercised with a fake that
/// returns a canned callback URL.
///
/// `@MainActor` because `ASWebAuthenticationPresentationContextProviding` is
/// main-actor isolated, and so fakes need no `Sendable` gymnastics.
@MainActor
protocol WebAuthenticating: AnyObject {
    func authenticate(url: URL, callbackScheme: String, prefersEphemeralSession: Bool) async throws -> URL
}

/// The slice of `ASWebAuthenticationSession` that `WebAuthenticator` drives.
///
/// A real session opens the browser on `start()`, so a unit test substitutes a
/// stand-in that opens nothing and invokes the completion handler from
/// whatever thread the test chooses.
protocol WebAuthenticationSession: AnyObject {
    var prefersEphemeralWebBrowserSession: Bool { get set }
    var presentationContextProvider: (any ASWebAuthenticationPresentationContextProviding)? { get set }
    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: WebAuthenticationSession {}

/// Runs the OIDC authorization request in the system's own browser.
///
/// Chosen over an embedded `WKWebView` because it shows a real URL bar, which is
/// the user's only defence against a spoofed identity provider, and because the
/// app cannot read what the user types into it. See
/// `docs/oidc-callback-decision.md`.
@MainActor
final class WebAuthenticator: NSObject, WebAuthenticating {
    typealias SessionFactory = (
        _ url: URL,
        _ callbackScheme: String,
        _ completion: @escaping ASWebAuthenticationSession.CompletionHandler
    ) -> any WebAuthenticationSession

    private let makeSession: SessionFactory
    private var session: (any WebAuthenticationSession)?
    private var continuation: CheckedContinuation<URL, Error>?

    /// `makeSession` exists for tests. The default builds the real thing.
    init(makeSession: @escaping SessionFactory = { url, scheme, completion in
        ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: completion)
    }) {
        self.makeSession = makeSession
        super.init()
    }

    func authenticate(
        url: URL,
        callbackScheme: String,
        prefersEphemeralSession: Bool = true
    ) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.continuation = continuation

                // AuthenticationServices promises no thread for this handler.
                // On macOS it arrives on the browser agent's XPC reply queue,
                // so it must not assume the main actor: doing so trapped on
                // every SSO sign-in there (#182). @Sendable keeps the closure
                // out of this class's main-actor isolation, so the runtime
                // does not assert on entry either; the hop happens inside.
                let session = makeSession(url, callbackScheme) { @Sendable [weak self] callbackURL, error in
                    Task { @MainActor in
                        self?.sessionDidComplete(callbackURL: callbackURL, error: error)
                    }
                }

                // Both have to be set before start(). The ephemeral flag is
                // ignored afterwards, and a nil provider fails start() with
                // .presentationContextNotProvided. The property is weak, so
                // this object must outlive the session, which it does because
                // the caller holds it.
                session.prefersEphemeralWebBrowserSession = prefersEphemeralSession
                session.presentationContextProvider = self
                self.session = session

                // A false return does not invoke the completion handler, so
                // resume here or the continuation hangs forever.
                guard session.start() else {
                    self.session = nil
                    finish(.failure(WebAuthenticationError.cannotStart))
                    return
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        session?.cancel()
        session = nil
        finish(.failure(WebAuthenticationError.cancelled))
    }

    private func sessionDidComplete(callbackURL: URL?, error: (any Error)?) {
        session = nil
        if let error {
            finish(.failure(Self.mapped(error)))
        } else if let callbackURL {
            finish(.success(callbackURL))
        } else {
            finish(.failure(WebAuthenticationError.failed("No callback URL")))
        }
    }

    /// Resume-once. `cancel()` may or may not also run the completion handler,
    /// and resuming a `CheckedContinuation` twice traps.
    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func mapped(_ error: Error) -> Error {
        guard let authError = error as? ASWebAuthenticationSessionError else {
            return WebAuthenticationError.failed(error.localizedDescription)
        }
        return switch authError.code {
        case .canceledLogin: WebAuthenticationError.cancelled
        case .presentationContextNotProvided, .presentationContextInvalid: WebAuthenticationError.cannotStart
        default: WebAuthenticationError.failed(authError.localizedDescription)
        }
    }
}

extension WebAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        // Must be a window in a foreground-active scene, or start() fails with
        // .presentationContextInvalid.
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        return window ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #endif
    }
}
