import Foundation

/// Keeps a visible task list in step with changes made by another client
/// while it stays on screen (issue #241). The list owns the polling task, so
/// SwiftUI cancels it on navigation or when the scene goes inactive. Every
/// list shares one coordinator, so a slow read can never overlap the next
/// tick, or another screen's.
@MainActor
final class LiveListRefresh {
    static let interval: Duration = .seconds(15)

    private var isFetching = false

    nonisolated init() {}

    /// Runs one quiet read. `revision` must change whenever local state that
    /// the snapshot would overwrite changes, so a response that raced a local
    /// edit, a full refresh or a logout is dropped rather than applied.
    func refresh<Snapshot>(
        isEnabled: () -> Bool,
        revision: () -> UInt64,
        fetch: () async throws -> Snapshot,
        apply: (Snapshot) -> Void
    ) async {
        guard !isFetching, !Task.isCancelled, isEnabled() else { return }
        isFetching = true
        defer { isFetching = false }
        let startedAt = revision()
        do {
            let snapshot = try await fetch()
            guard !Task.isCancelled, isEnabled(), revision() == startedAt else { return }
            apply(snapshot)
        } catch {
            // Keep the last rows. The next tick retries, and pull to refresh
            // still reports errors the usual way.
        }
    }

    /// Calls `refresh` once per `wait` until the surrounding task is cancelled.
    static func poll(
        wait: () async throws -> Void = { try await Task.sleep(for: interval) },
        refresh: () async -> Void
    ) async {
        while !Task.isCancelled {
            do { try await wait() } catch { return }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}
