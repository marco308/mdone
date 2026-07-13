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

    // MARK: - Private

    private var activity: Activity<FocusTaskAttributes>?
    private let modelContainer: ModelContainer?
    private let outbox: FocusOutboxService?

    private var sharedDefaults: UserDefaults {
        FocusConstants.sharedDefaults
    }

    // MARK: - Init

    init(modelContainer: ModelContainer? = nil, outbox: FocusOutboxService? = nil) {
        self.modelContainer = modelContainer
        self.outbox = outbox
        restoreSession()
    }

    // MARK: - Public Methods

    func startFocus(task: VTask, projectName: String) {
        // End any existing focus first
        if currentSession != nil {
            endFocus()
        }

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
        if ActivityAuthorizationInfo().areActivitiesEnabled {
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

        // Clear state immediately
        activity = nil
        currentSession = nil
        clearPersistedSession()

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
        endFocus()
        #if DEBUG
        print("[FocusManager] Focused task completed, ending focus")
        #endif
    }

    func handleTaskDeleted(taskId: Int64) {
        guard focusedTaskId == taskId else { return }
        endFocus()
        #if DEBUG
        print("[FocusManager] Focused task deleted, ending focus")
        #endif
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

    /// Internal (not private) so unit tests can drive it without going through ActivityKit.
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
