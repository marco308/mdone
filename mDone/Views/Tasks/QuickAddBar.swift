import SwiftData
import SwiftUI

struct QuickAddBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    let projectId: Int64
    var defaultDueDate: Date?
    @State private var title = ""
    @FocusState private var isFocused: Bool

    /// User-chosen estimate for the task being created (`nil` == none).
    @State private var estimateSeconds: TimeInterval?
    /// Most recent suggestion from the offline matcher, if any.
    @State private var suggestion: EstimateSuggestion?
    /// Set true once the user dismisses the hint for the current title so we
    /// don't nag them again until they change the title materially.
    @State private var hintDismissed = false
    /// Debounce token — only the latest keystroke's task computes a suggestion.
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            if let suggestion, !hintDismissed, estimateSeconds == nil {
                suggestionHint(suggestion)
            }

            if estimateSeconds != nil {
                EstimatePicker(estimateSeconds: $estimateSeconds)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                TextField("Add a task...", text: $title)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit {
                        addTask()
                    }
                    .onChange(of: title) { _, newValue in
                        scheduleSuggestion(for: newValue)
                    }

                if estimateSeconds == nil {
                    Button {
                        // Let the user open the estimate picker manually even
                        // without a suggestion. Defaults to 30m, fully editable.
                        estimateSeconds = 30 * 60
                    } label: {
                        Image(systemName: "timer")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Add time estimate")
                }

                if !title.isEmpty {
                    Button {
                        addTask()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Add task")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.2), value: suggestion)
        .animation(.snappy(duration: 0.2), value: estimateSeconds == nil)
        .task(id: appState.quickAddTrigger) {
            // Consume the trigger so a later-mounted QuickAddBar (e.g. switching
            // to a project's task list) doesn't see a stale value and steal focus.
            guard appState.quickAddTrigger != nil else { return }
            isFocused = true
            appState.quickAddTrigger = nil
        }
    }

    /// Subtle, dismissible hint. Tapping the body fills the estimate field;
    /// tapping the X dismisses for this title. Never auto-fills, never blocks.
    @ViewBuilder
    private func suggestionHint(_ s: EstimateSuggestion) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                estimateSeconds = s.suggestedSeconds
            } label: {
                Text("Similar tasks took ~\(EstimateFormatter.string(from: s.suggestedSeconds)) — tap to use")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                hintDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss estimate suggestion")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 4)
    }

    /// Debounce keystrokes (250ms) so the matcher doesn't run on every
    /// character. The matcher itself is sub-millisecond, but debouncing keeps
    /// the hint from flickering as a word is typed.
    private func scheduleSuggestion(for rawTitle: String) {
        debounceTask?.cancel()
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Re-typing resets the dismissal so a meaningfully different title can
        // surface a fresh hint.
        hintDismissed = false

        guard trimmed.count >= 3 else {
            suggestion = nil
            return
        }

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let history = FocusHistoryQuery.historicalTasks(in: modelContext)
            let result = EstimateSuggester.suggestion(
                for: trimmed,
                history: history,
                projectId: projectId
            )
            if Task.isCancelled { return }
            suggestion = result
        }
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let chosenEstimate = estimateSeconds
        Task {
            let created = await appState.createTask(
                title: trimmed,
                projectId: projectId,
                dueDate: defaultDueDate
            )
            // Persist the local estimate against the real task id once we have it.
            if let created, let chosenEstimate {
                EstimateStore.set(chosenEstimate, for: created.id, in: modelContext)
            }
            title = ""
            estimateSeconds = nil
            suggestion = nil
            hintDismissed = false
        }
    }
}
