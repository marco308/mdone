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
        let elapsed = currentSession?.totalElapsed() ?? 0

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
        let elapsed = currentSession?.totalElapsed() ?? 0

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
