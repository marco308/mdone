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
    /// Trimmed title the current `suggestion` was computed for — used to
    /// hide the hint as soon as the user keeps typing past it, so a stale
    /// suggestion can't briefly display against an unrelated title during
    /// the 250ms debounce window before the next lookup fires.
    @State private var suggestionForTitle: String?
    /// Trimmed title the user explicitly dismissed the hint for. The hint
    /// stays hidden whenever the current title matches it (we don't nag
    /// them about the same task again) and re-appears when they switch to a
    /// different title. If they later type the dismissed title verbatim
    /// the dismissal still applies; full reset happens on add.
    @State private var dismissedTitle: String?
    /// Debounce token — only the latest keystroke's task computes a suggestion.
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            if let suggestion, suggestionMatchesCurrentTitle, !isHintDismissed, estimateSeconds == nil {
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
    private func suggestionHint(_ s: EstimateSuggestion) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
                dismissedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// True when the user dismissed the hint for the exact title they're
    /// looking at — keeps the hint hidden while they continue typing the
    /// same task and surfaces again only once the title meaningfully changes.
    private var isHintDismissed: Bool {
        guard let dismissedTitle else { return false }
        return dismissedTitle == title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the cached suggestion was computed for what the user is
    /// currently typing, so the hint always reflects the present title and
    /// never a stale one from the just-finished keystroke.
    private var suggestionMatchesCurrentTitle: Bool {
        guard let suggestionForTitle else { return false }
        return suggestionForTitle == title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSuggestion(for rawTitle: String) {
        debounceTask?.cancel()
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 3 else {
            suggestion = nil
            suggestionForTitle = nil
            return
        }

        // Explicit `@MainActor`: `historicalTasks` and the `@State` mutations
        // below are all main-actor isolated, and inferred inheritance via
        // plain `Task {}` would not survive a future move to strict
        // concurrency. Cross-actor at the boundary, not inside the hot path.
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled {
                return
            }
            let history = FocusHistoryQuery.historicalTasks(in: modelContext)
            let result = EstimateSuggester.suggestion(
                for: trimmed,
                history: history,
                projectId: projectId
            )
            if Task.isCancelled {
                return
            }
            suggestion = result
            suggestionForTitle = result == nil ? nil : trimmed
        }
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let description = EstimateMarker.apply(estimateSeconds, to: nil)
        // Cancel any in-flight debounce so a suggestion that lands after
        // submission can't overwrite the now-empty `suggestion` / cause a
        // flicker against the next task the user starts typing.
        debounceTask?.cancel()
        debounceTask = nil
        // Same `@MainActor` pin as `scheduleSuggestion`: this body mutates
        // `@State` after the async create; without explicit isolation a
        // future strict-concurrency mode could move it off-main.
        Task { @MainActor in
            await appState.createTask(
                title: trimmed,
                projectId: projectId,
                description: description,
                dueDate: defaultDueDate
            )
            title = ""
            estimateSeconds = nil
            suggestion = nil
            suggestionForTitle = nil
            dismissedTitle = nil
        }
    }
}
