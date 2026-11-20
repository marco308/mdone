import Foundation
import Observation

/// One pending destination survives the sign-in screen. New links supersede old
/// requests; cancelled or late reads cannot present a different task afterward.
@MainActor @Observable
final class TaskLinkRouter {
    private(set) var revision = UUID()
    private(set) var request: TaskDeepLink?
    private(set) var task: VTask?
    private(set) var message: String?
    private(set) var isLoading = false
    private(set) var isPresented = false

    @discardableResult
    func receive(_ url: URL, scheme: String = TaskDeepLink.scheme) -> Bool {
        guard url.scheme?.lowercased() == scheme.lowercased(), url.host == "task" else { return false }
        dismiss()
        isPresented = true
        do {
            request = try TaskDeepLink(url: url, scheme: scheme)
        } catch {
            message = error.localizedDescription
        }
        return true
    }

    func dismiss() {
        revision = UUID()
        request = nil
        task = nil
        message = nil
        isLoading = false
        isPresented = false
    }

    func retry() {
        revision = UUID()
    }

    func resolve(
        authenticated: Bool,
        serverURL: String?,
        fetch: (TaskDeepLink) async throws -> VTask
    ) async {
        guard let request else { return }
        let current = revision
        task = nil
        guard authenticated else {
            isLoading = false
            message = TaskLinkFailure.signIn.localizedDescription
            return
        }
        guard request.matches(serverURL: serverURL) else {
            isLoading = false
            message = TaskLinkFailure.wrongServer.localizedDescription
            return
        }
        isLoading = true
        message = nil
        do {
            let loaded = try await fetch(request)
            guard !Task.isCancelled, revision == current else { return }
            guard loaded.id == request.taskID else { throw TaskLinkFailure.unavailable }
            task = loaded
        } catch {
            guard !Task.isCancelled, revision == current else { return }
            message = error.localizedDescription
        }
        if revision == current {
            isLoading = false
        }
    }
}
