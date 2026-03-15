#if os(iOS)
import ActivityKit
import Foundation
import SwiftUI

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

    private var sharedDefaults: UserDefaults {
        FocusConstants.sharedDefaults
    }

    // MARK: - Init

    init() {
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

        // Start Live Activity
        if ActivityAuthorizationInfo().areActivitiesEnabled {
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
                print("[FocusManager] Live Activity started: \(newActivity.id)")
            } catch {
                print("[FocusManager] Failed to start Live Activity: \(error)")
            }
        }

        currentSession = session
        persistSession()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        print("[FocusManager] Focus started on task: \(task.title)")
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
        print("[FocusManager] Focus paused. Elapsed: \(session.elapsedBeforePause)s")
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
        print("[FocusManager] Focus resumed")
    }

    func endFocus() {
        Task {
            await activity?.end(
                .init(
                    state: FocusTaskAttributes.ContentState(
                        focusStartDate: Date(),
                        isPaused: true,
                        elapsedBeforePause: currentSession?.totalElapsed() ?? 0
                    ),
                    staleDate: nil
                ),
                dismissalPolicy: .immediate
            )
        }

        activity = nil
        currentSession = nil
        clearPersistedSession()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        print("[FocusManager] Focus ended")
    }

    func switchFocus(task: VTask, projectName: String) {
        endFocus()
        startFocus(task: task, projectName: projectName)
    }

    func handleTaskCompleted(taskId: Int64) {
        guard focusedTaskId == taskId else { return }
        endFocus()
        print("[FocusManager] Focused task completed, ending focus")
    }

    func handleTaskDeleted(taskId: Int64) {
        guard focusedTaskId == taskId else { return }
        endFocus()
        print("[FocusManager] Focused task deleted, ending focus")
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
                print("[FocusManager] Stale session found (> 24h), cleaning up")
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
                    print("[FocusManager] Reconnected to Live Activity: \(activityId)")
                } else {
                    // Activity was dismissed but session persists — try to restart
                    print("[FocusManager] Live Activity not found, attempting restart")
                    restartLiveActivity(for: session)
                }
            }

            print("[FocusManager] Session restored for task: \(session.taskTitle)")
        } catch {
            print("[FocusManager] Failed to decode persisted session: \(error)")
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

            print("[FocusManager] Live Activity restarted: \(newActivity.id)")
        } catch {
            print("[FocusManager] Failed to restart Live Activity: \(error)")
        }
    }

    private func persistSession() {
        guard let session = currentSession else { return }
        do {
            let data = try JSONEncoder().encode(session)
            sharedDefaults.set(data, forKey: FocusConstants.focusSessionKey)
        } catch {
            print("[FocusManager] Failed to persist session: \(error)")
        }
    }

    private func clearPersistedSession() {
        sharedDefaults.removeObject(forKey: FocusConstants.focusSessionKey)
    }

    private func makeContentState(from session: FocusSession) -> FocusTaskAttributes.ContentState {
        if session.isPaused {
            return FocusTaskAttributes.ContentState(
                focusStartDate: session.focusIntervalStartDate,
                isPaused: true,
                elapsedBeforePause: session.elapsedBeforePause
            )
        } else {
            // Use syntheticStartDate so the Live Activity timer shows total elapsed time
            return FocusTaskAttributes.ContentState(
                focusStartDate: session.syntheticStartDate,
                isPaused: false,
                elapsedBeforePause: session.elapsedBeforePause
            )
        }
    }
}
#endif
