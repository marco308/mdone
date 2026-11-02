#if os(iOS)
import ActivityKit
import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class FocusManager {
    // MARK: - State

    var currentSession: FocusSession?
    var showFocusView: Bool = false

    var focusedTaskId: Int64? {
        currentSession?.taskId
    }

    var isActive: Bool {
        guard let session = currentSession else { return false }
        return !session.isPaused
    }

    var isPaused: Bool {
        guard let session = currentSession else { return false }
        return session.isPaused
    }

    /// The Focus Run in progress, if the current session is part of one.
    /// Plain Focus leaves this nil and ends when its task is done.
    private(set) var run: FocusRun?

    /// Set once when a run reaches the end of its list, so the focus screen
    /// can say how it went. Cleared by `dismissRunSummary()` or a new start.
    private(set) var finishedRun: FocusRunSummary?

    /// Looks a task id up in the live task list, returning it with its
    /// project's name. The app wires this to `AppState`; a run needs it to
    /// turn the next queued id into something it can focus.
    var taskLookup: ((Int64) -> (task: VTask, projectName: String)?)?

    var isRunActive: Bool {
        run != nil
    }

    /// The task a run will move to next, if any.
    var runUpNext: VTask? {
        guard let run else { return nil }
        return run.peekNext(where: isEligibleForRun).flatMap { taskLookup?($0)?.task }
    }

    /// Eligible tasks left in the run after the focused one.
    var runRemainingCount: Int {
        run?.remainingCount(where: isEligibleForRun) ?? 0
    }

    // MARK: - Private

    static let focusRunKey = "com.mdone.focusRun"

    private var activity: Activity<FocusTaskAttributes>?
    private let modelContainer: ModelContainer?
    private let outbox: FocusOutboxService?
    /// Off in unit tests so a run can advance without asking ActivityKit for
    /// a real Live Activity on the test host.
    private let liveActivitiesEnabled: Bool

    private var sharedDefaults: UserDefaults {
        FocusConstants.sharedDefaults
    }

    // MARK: - Init

    init(
        modelContainer: ModelContainer? = nil,
        outbox: FocusOutboxService? = nil,
        liveActivitiesEnabled: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.outbox = outbox
        self.liveActivitiesEnabled = liveActivitiesEnabled
        restoreSession()
        restoreRun()
    }

    // MARK: - Public Methods

    func startFocus(task: VTask, projectName: String) {
        // End any existing focus first
        if currentSession != nil {
            endFocus()
        }
        finishedRun = nil

        let now = Date()
        var session = FocusSession(
            taskId: task.id,
            taskTitle: task.title,
            projectName: projectName,
            priorityLevel: Int(task.priority),
            sessionStartDate: now,
            focusIntervalStartDate: now,
            elapsedBeforePause: 0,
            isPaused: false
        )

        // Start Live Activity — first end any lingering activities to avoid stale display
        if liveActivitiesEnabled, ActivityAuthorizationInfo().areActivitiesEnabled {
            for existingActivity in Activity<FocusTaskAttributes>.activities {
                Task { await existingActivity.end(nil, dismissalPolicy: .immediate) }
            }

            let attributes = FocusTaskAttributes(
                taskId: task.id,
                taskTitle: task.title,
                projectName: projectName,
                priorityLevel: Int(task.priority)
            )

            let contentState = makeContentState(from: session)

            do {
                let newActivity = try Activity<FocusTaskAttributes>.request(
                    attributes: attributes,
                    content: .init(state: contentState, staleDate: nil),
                    pushType: nil
                )
                activity = newActivity
                session.activityId = newActivity.id
                #if DEBUG
                print("[FocusManager] Live Activity started: \(newActivity.id)")
                #endif
            } catch {
                #if DEBUG
                print("[FocusManager] Failed to start Live Activity: \(error)")
                #endif
            }
        }

        currentSession = session
        persistSession()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #if DEBUG
        print("[FocusManager] Focus started on task: \(task.title)")
        #endif
    }

    func pauseFocus() {
        guard var session = currentSession, !session.isPaused else { return }

        let now = Date()
        let currentInterval = now.timeIntervalSince(session.focusIntervalStartDate)
        session.elapsedBeforePause += currentInterval
        session.isPaused = true

        currentSession = session

        let contentState = makeContentState(from: session)
        Task {
            await activity?.update(.init(state: contentState, staleDate: nil))
        }

        persistSession()
        #if DEBUG
        print("[FocusManager] Focus paused. Elapsed: \(session.elapsedBeforePause)s")
        #endif
    }

    func resumeFocus() {
        guard var session = currentSession, session.isPaused else { return }

        session.isPaused = false
        session.focusIntervalStartDate = Date()

        currentSession = session

        let contentState = makeContentState(from: session)
        Task {
            await activity?.update(.init(state: contentState, staleDate: nil))
        }

        persistSession()
        #if DEBUG
        print("[FocusManager] Focus resumed")
        #endif
    }

    func endFocus() {
        let activityToEnd = activity
        let endedAt = Date()
        var elapsed: TimeInterval = 0
        if let session = currentSession {
            elapsed = session.totalElapsed(at: endedAt)
            persistCompletedSession(session, endedAt: endedAt, focusedSeconds: elapsed)
        }

        activity = nil
        currentSession = nil
        clearPersistedSession()
        clearRun()

        Task {
            // End the specific activity
            await activityToEnd?.end(
                .init(
                    state: FocusTaskAttributes.ContentState(
                        focusStartDate: Date(),
                        isPaused: true,
                        elapsedBeforePause: elapsed
                    ),
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
            // Also end any other lingering activities
            for existingActivity in Activity<FocusTaskAttributes>.activities {
                await existingActivity.end(nil, dismissalPolicy: .immediate)
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #if DEBUG
        print("[FocusManager] Focus ended")
        #endif
    }

    func switchFocus(task: VTask, projectName: String) {
        let activityToEnd = activity
        let endedAt = Date()
        var elapsed: TimeInterval = 0
        if let session = currentSession {
            elapsed = session.totalElapsed(at: endedAt)
            persistCompletedSession(session, endedAt: endedAt, focusedSeconds: elapsed)
        }

        // Clear state immediately. Switching by hand leaves any run behind.
        activity = nil
        currentSession = nil
        clearPersistedSession()
        clearRun()

        // End old activity and start new focus sequentially
        Task {
            await activityToEnd?.end(
                .init(
                    state: FocusTaskAttributes.ContentState(
                        focusStartDate: Date(),
                        isPaused: true,
                        elapsedBeforePause: elapsed
                    ),
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
            // End any other lingering activities
            for existingActivity in Activity<FocusTaskAttributes>.activities {
                await existingActivity.end(nil, dismissalPolicy: .immediate)
            }
            // Now start the new focus on the main actor
            startFocus(task: task, projectName: projectName)
        }
    }

    func handleTaskCompleted(taskId: Int64) {
        guard focusedTaskId == taskId else { return }
        if run != nil {
            advanceRun(completedCurrent: true)
            return
        }
        endFocus()
        #if DEBUG
        print("[FocusManager] Focused task completed, ending focus")
        #endif
    }

    func handleTaskDeleted(taskId: Int64) {
        guard focusedTaskId == taskId else { return }
        if run != nil {
            advanceRun(completedCurrent: false)
            return
        }
        endFocus()
        #if DEBUG
        print("[FocusManager] Focused task deleted, ending focus")
        #endif
    }

    // MARK: - Focus Run

    /// Focuses `task` and queues the tasks listed after it in `order`, so
    /// finishing one brings up the next. `order` is the list as the user sees
    /// it, top to bottom.
    func startFocusRun(task: VTask, projectName: String, order: [Int64]) {
        let newRun = FocusRun(startingAt: task.id, in: order)
        // Both paths clear any previous run; the new one is set after them.
        // With nothing focused there is no old Live Activity to wait out, so
        // start straight away rather than on switchFocus's follow-up task.
        if currentSession == nil {
            clearRun()
            startFocus(task: task, projectName: projectName)
        } else {
            switchFocus(task: task, projectName: projectName)
        }
        finishedRun = nil
        run = newRun
        persistRun()
    }

    /// Moves on to the next task without completing the focused one.
    func skipToNextInRun() {
        guard run != nil, currentSession != nil else { return }
        advanceRun(completedCurrent: false)
    }

    func dismissRunSummary() {
        finishedRun = nil
    }

    /// Records the focused task's session and starts the next one in the run,
    /// or ends focus with a summary when the list has run out.
    private func advanceRun(completedCurrent: Bool) {
        guard var advancing = run else { return }
        let nextId = advancing.advance(completedCurrent: completedCurrent, where: isEligibleForRun)
        guard let nextId, let next = taskLookup?(nextId) else {
            let summary = FocusRunSummary(
                completedCount: advancing.completedCount,
                skippedCount: advancing.skippedCount
            )
            endFocus()
            finishedRun = summary
            #if DEBUG
            print("[FocusManager] Focus run finished: \(summary.completedCount) done")
            #endif
            return
        }

        // Close out the current session without the lingering-activity sweep
        // in endFocus: that sweep runs later and would take the next task's
        // new Live Activity down with it.
        let activityToEnd = activity
        let endedAt = Date()
        if let session = currentSession {
            let elapsed = session.totalElapsed(at: endedAt)
            persistCompletedSession(session, endedAt: endedAt, focusedSeconds: elapsed)
            Task {
                await activityToEnd?.end(
                    .init(
                        state: FocusTaskAttributes.ContentState(
                            focusStartDate: endedAt,
                            isPaused: true,
                            elapsedBeforePause: elapsed
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }
        activity = nil
        currentSession = nil
        clearPersistedSession()

        startFocus(task: next.task, projectName: next.projectName)
        run = advancing
        persistRun()
        #if DEBUG
        print("[FocusManager] Focus run moved on to: \(next.task.title)")
        #endif
    }

    /// A queued task is worth focusing while it is still in the live list
    /// and not done.
    private func isEligibleForRun(_ taskId: Int64) -> Bool {
        guard let task = taskLookup?(taskId)?.task else { return false }
        return !task.done
    }

    // MARK: - Private Methods

    private func restoreSession() {
        guard let data = sharedDefaults.data(forKey: FocusConstants.focusSessionKey) else {
            return
        }

        do {
            let session = try JSONDecoder().decode(FocusSession.self, from: data)

            // Clean up stale sessions (> 24 hours)
            let staleThreshold: TimeInterval = 24 * 60 * 60
            if Date().timeIntervalSince(session.sessionStartDate) > staleThreshold {
                #if DEBUG
                print("[FocusManager] Stale session found (> 24h), cleaning up")
                #endif
                // Persist whatever time was accumulated before the session went stale.
                // Only count elapsedBeforePause (bounded, observed) — never the in-flight
                // current interval, which could span the entire 24h+ stale window if the
                // app was killed mid-session.
                let elapsed = session.elapsedBeforePause
                let endedAt = session.sessionStartDate.addingTimeInterval(elapsed)
                persistCompletedSession(session, endedAt: endedAt, focusedSeconds: elapsed)
                clearPersistedSession()
                // Also end any lingering Live Activity
                for existingActivity in Activity<FocusTaskAttributes>.activities {
                    Task {
                        await existingActivity.end(nil, dismissalPolicy: .immediate)
                    }
                }
                return
            }

            currentSession = session

            // Try to reconnect to existing Live Activity
            if let activityId = session.activityId {
                let matchingActivity = Activity<FocusTaskAttributes>.activities.first {
                    $0.id == activityId
                }

                if let matchingActivity {
                    activity = matchingActivity
                    #if DEBUG
                    print("[FocusManager] Reconnected to Live Activity: \(activityId)")
                    #endif
                } else {
                    // Activity was dismissed but session persists — try to restart
                    #if DEBUG
                    print("[FocusManager] Live Activity not found, attempting restart")
                    #endif
                    restartLiveActivity(for: session)
                }
            }

            #if DEBUG
            print("[FocusManager] Session restored for task: \(session.taskTitle)")
            #endif
        } catch {
            #if DEBUG
            print("[FocusManager] Failed to decode persisted session: \(error)")
            #endif
            clearPersistedSession()
        }
    }

    private func restartLiveActivity(for session: FocusSession) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = FocusTaskAttributes(
            taskId: session.taskId,
            taskTitle: session.taskTitle,
            projectName: session.projectName,
            priorityLevel: session.priorityLevel
        )

        let contentState = makeContentState(from: session)

        do {
            let newActivity = try Activity<FocusTaskAttributes>.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )
            activity = newActivity

            var updatedSession = session
            updatedSession.activityId = newActivity.id
            currentSession = updatedSession
            persistSession()

            #if DEBUG
            print("[FocusManager] Live Activity restarted: \(newActivity.id)")
            #endif
        } catch {
            #if DEBUG
            print("[FocusManager] Failed to restart Live Activity: \(error)")
            #endif
        }
    }

    private func persistSession() {
        guard let session = currentSession else { return }
        do {
            let data = try JSONEncoder().encode(session)
            sharedDefaults.set(data, forKey: FocusConstants.focusSessionKey)
        } catch {
            #if DEBUG
            print("[FocusManager] Failed to persist session: \(error)")
            #endif
        }
    }

    private func clearPersistedSession() {
        sharedDefaults.removeObject(forKey: FocusConstants.focusSessionKey)
    }

    private func persistRun() {
        guard let run, let data = try? JSONEncoder().encode(run) else {
            sharedDefaults.removeObject(forKey: Self.focusRunKey)
            return
        }
        sharedDefaults.set(data, forKey: Self.focusRunKey)
    }

    private func clearRun() {
        run = nil
        sharedDefaults.removeObject(forKey: Self.focusRunKey)
    }

    /// A run only means something alongside the session it belongs to, so it
    /// is restored only when a session was.
    private func restoreRun() {
        guard currentSession != nil,
              let data = sharedDefaults.data(forKey: Self.focusRunKey),
              let saved = try? JSONDecoder().decode(FocusRun.self, from: data)
        else {
            sharedDefaults.removeObject(forKey: Self.focusRunKey)
            return
        }
        run = saved
    }

    // Internal (not private) so unit tests can drive it without going through ActivityKit.
    func persistCompletedSession(
        _ session: FocusSession,
        endedAt: Date,
        focusedSeconds: TimeInterval
    ) {
        // Drop zero-duration sessions — start-and-immediately-end is noise.
        guard focusedSeconds >= 1.0 else { return }
        guard let modelContainer else { return }

        let record = FocusRecord(
            taskId: session.taskId,
            taskTitle: session.taskTitle,
            projectName: session.projectName,
            priorityLevel: session.priorityLevel,
            startedAt: session.sessionStartDate,
            endedAt: endedAt,
            focusedSeconds: focusedSeconds,
            device: Self.deviceIdentifier(),
            clientId: UUID().uuidString
        )

        let context = modelContainer.mainContext
        context.insert(record)
        do {
            try context.save()
            outbox?.enqueue(record)
        } catch {
            #if DEBUG
            print("[FocusManager] Failed to persist FocusRecord: \(error)")
            #endif
        }
    }

    /// Stable per-device identifier for the FocusRecord — derived from
    /// `identifierForVendor` but SHA-256 hashed so the persisted value isn't
    /// the raw vendor UUID. Stable across launches as long as the user keeps
    /// at least one app from this vendor installed; resets if they uninstall
    /// every mDone-vendor app and reinstall. Good enough to distinguish
    /// "iPhone vs Mac" in #62's analysis without doubling as a tracking handle.
    private static func deviceIdentifier() -> String {
        guard let uuid = UIDevice.current.identifierForVendor?.uuidString else {
            return "unknown"
        }
        let digest = SHA256.hash(data: Data(uuid.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeContentState(from session: FocusSession) -> FocusTaskAttributes.ContentState {
        if session.isPaused {
            FocusTaskAttributes.ContentState(
                focusStartDate: session.focusIntervalStartDate,
                isPaused: true,
                elapsedBeforePause: session.elapsedBeforePause
            )
        } else {
            // Use syntheticStartDate so the Live Activity timer shows total elapsed time
            FocusTaskAttributes.ContentState(
                focusStartDate: session.syntheticStartDate,
                isPaused: false,
                elapsedBeforePause: session.elapsedBeforePause
            )
        }
    }
}
#endif
