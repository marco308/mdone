import SwiftUI

struct QuickAddBar: View {
    @Environment(AppState.self) private var appState
    let projectId: Int64
    var defaultDueDate: Date?
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .task(id: appState.quickAddTrigger) {
            // Consume the trigger so a later-mounted QuickAddBar (e.g. switching
            // to a project's task list) doesn't see a stale value and steal focus.
            guard appState.quickAddTrigger != nil else { return }
            isFocused = true
            appState.quickAddTrigger = nil
        }
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await appState.createTask(title: trimmed, projectId: projectId, dueDate: defaultDueDate)
            title = ""
        }
    }
}
