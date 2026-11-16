import Foundation

/// What one live refresh tick found, which sets how long until the next one.
enum LiveRefreshOutcome: Equatable {
    /// The server had something new, so ticks go back to the fastest pace.
    case changed
    /// Nothing new, so the next tick can wait longer.
    case unchanged
    /// The tick did not run or its answer was dropped: busy, offline, failed
    /// or overtaken by a local change. It says nothing about the server.
    case skipped
}

/// How often a visible list checks the server: from `minimum` while things
/// are changing, stretching to `maximum` while they are not (#241).
struct LivePollPace: Equatable {
    let minimum: Duration
    let maximum: Duration

    /// mDone is in front and nothing asks it to go easy.
    static let foreground = LivePollPace(minimum: .seconds(15), maximum: .seconds(120))
    /// In front, but in Low Power Mode or on an expensive or constrained
    /// network (cellular, a hotspot, Low Data Mode).
    static let foregroundConstrained = LivePollPace(minimum: .seconds(60), maximum: .seconds(300))
    /// A Mac window left visible behind other apps.
    static let behind = LivePollPace(minimum: .seconds(180), maximum: .seconds(600))
    static let behindConstrained = LivePollPace(minimum: .seconds(300), maximum: .seconds(900))

    static func current(inFront: Bool, constrained: Bool) -> LivePollPace {
        switch (inFront, constrained) {
        case (true, false): .foreground
        case (true, true): .foregroundConstrained
        case (false, false): .behind
        case (false, true): .behindConstrained
        }
    }

    /// Whether the device or the network asks for fewer requests right now.
    static func isConstrained(network: NetworkMonitor) -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || network.isExpensive || network.isConstrained
    }
}

/// The wait before each tick. It doubles after every tick that finds nothing,
/// up to the pace's maximum, and drops back to the minimum as soon as one
/// finds a change. Pure, so the backoff is unit-tested without a clock.
struct LivePollSchedule: Equatable {
    private(set) var interval: Duration

    init(pace: LivePollPace) {
        interval = pace.minimum
    }

    /// Takes a tick's outcome and the pace in force now, which may differ
    /// from the last one if Low Power Mode or the network changed.
    mutating func record(_ outcome: LiveRefreshOutcome, pace: LivePollPace) {
        switch outcome {
        case .changed: interval = pace.minimum
        case .unchanged: interval *= 2
        case .skipped: break
        }
        interval = min(max(interval, pace.minimum), pace.maximum)
    }
}

/// Keeps a visible task list in step with changes made by another client
/// while it stays on screen (issue #241). The list owns the polling task, so
/// SwiftUI cancels it on navigation or when the scene goes inactive. Every
/// list shares one coordinator, so a slow read can never overlap the next
/// tick, or another screen's.
@MainActor
final class LiveListRefresh {
    private var isFetching = false

    nonisolated init() {}

    /// Runs one quiet read. `fetch` returns `nil` when a cheap check says
    /// there is nothing new to download. `apply` returns whether it changed
    /// anything. `revision` must change whenever local state that the
    /// snapshot would overwrite changes, so a response that raced a local
    /// edit, a full refresh or a logout is dropped rather than applied.
    @discardableResult
    func refresh<Snapshot>(
        isEnabled: () -> Bool,
        revision: () -> UInt64,
        fetch: () async throws -> Snapshot?,
        apply: (Snapshot) -> Bool
    ) async -> LiveRefreshOutcome {
        guard !isFetching, !Task.isCancelled, isEnabled() else { return .skipped }
        isFetching = true
        defer { isFetching = false }
        let startedAt = revision()
        do {
            guard let snapshot = try await fetch() else { return .unchanged }
            guard !Task.isCancelled, isEnabled(), revision() == startedAt else { return .skipped }
            return apply(snapshot) ? .changed : .unchanged
        } catch {
            // Keep the last rows. The next tick retries, and pull to refresh
            // still reports errors the usual way.
            return .skipped
        }
    }

    /// Calls `refresh` on a backing-off schedule until the surrounding task
    /// is cancelled. `pace` is asked again after every tick, so a change of
    /// power or network state takes effect without restarting the loop.
    static func poll(
        pace: () -> LivePollPace,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        refresh: () async -> LiveRefreshOutcome
    ) async {
        var schedule = LivePollSchedule(pace: pace())
        while !Task.isCancelled {
            do { try await sleep(schedule.interval) } catch { return }
            guard !Task.isCancelled else { return }
            let outcome = await refresh()
            schedule.record(outcome, pace: pace())
        }
    }
}
