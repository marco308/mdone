import SwiftUI

#if os(iOS)
struct FocusSessionView: View {
    @Environment(FocusManager.self) private var focusManager
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let session = focusManager.currentSession {
            VStack(spacing: 0) {
                header

                Spacer()

                VStack(spacing: 16) {
                    Text(session.taskTitle)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Text(session.projectName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                        Text(formatElapsed(session.totalElapsed(at: timeline.date)))
                            .font(.system(size: 56, weight: .light, design: .monospaced))
                            .monospacedDigit()
                    }
                    .padding(.top, 24)

                    if session.isPaused {
                        Text("Paused")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                controls(session: session)
                    .padding(.bottom, 48)
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color.orange.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Text("Focus Mode")
                .font(.headline)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func controls(session: FocusSession) -> some View {
        HStack(spacing: 40) {
            Button {
                Task {
                    if let task = appState.tasks.first(where: { $0.id == session.taskId }) {
                        await appState.toggleTaskDone(task)
                    }
                    dismiss()
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                    Text("Done")
                        .font(.caption)
                }
                .foregroundStyle(.green)
            }

            Button {
                if session.isPaused {
                    focusManager.resumeFocus()
                } else {
                    focusManager.pauseFocus()
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: session.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 52))
                    Text(session.isPaused ? "Resume" : "Pause")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }

            Button {
                focusManager.endFocus()
                dismiss()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                    Text("End")
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
        }
    }
}
#endif
