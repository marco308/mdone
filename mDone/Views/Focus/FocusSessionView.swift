import SwiftUI

#if os(iOS)
struct FocusSessionView: View {
    @Environment(FocusManager.self) private var focusManager
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var largeControlSize: CGFloat = 52
    @ScaledMetric(relativeTo: .title3) private var smallControlSize: CGFloat = 28

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
                            .font(.system(size: timerFontSize, weight: .light, design: .monospaced))
                            .monospacedDigit()
                            .accessibilityLabel(
                                "Elapsed time: \(formatElapsed(session.totalElapsed(at: timeline.date)))"
                            )
                    }
                    .padding(.top, 24)

                    if session.isPaused {
                        Text("Paused")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if focusManager.isRunActive {
                    upNext
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }

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
        } else if let summary = focusManager.finishedRun {
            runSummary(summary)
        } else {
            // Session was ended (e.g. task completed externally) — auto-dismiss
            Color(.systemBackground)
                .onAppear {
                    dismiss()
                }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Text(focusManager.isRunActive ? "Focus Run" : "Focus Mode")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
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
            .accessibilityLabel("Close")
        }
        .padding()
    }

    /// What the run brings up after this task, and how much is left.
    private var upNext: some View {
        HStack(spacing: 12) {
            Image(systemName: "forward.end.circle")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let next = focusManager.runUpNext {
                    Text("Up next")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("Last task in this run")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(focusManager.runRemainingCount) left")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func runSummary(_ summary: FocusRunSummary) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "flag.checkered")
                .font(.system(size: largeControlSize))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Focus Run Complete")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("You finished \(summary.completedCount) tasks.")
                .font(.body)
            if summary.skippedCount > 0 {
                Text("\(summary.skippedCount) skipped")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                focusManager.dismissRunSummary()
                dismiss()
            } label: {
                Text("Close")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
    }

    private func controls(session: FocusSession) -> some View {
        HStack(spacing: focusManager.isRunActive ? 28 : 40) {
            Button {
                // In a run, completing the task brings up the next one (or the
                // summary) on this same screen, so it stays open.
                let inRun = focusManager.isRunActive
                Task {
                    if let task = appState.tasks.first(where: { $0.id == session.taskId }) {
                        await appState.toggleTaskDone(task)
                    }
                    if !inRun {
                        dismiss()
                    }
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: smallControlSize))
                    Text("Done")
                        .font(.caption)
                }
                .foregroundStyle(.green)
            }
            .accessibilityLabel("Mark task done")

            Button {
                if session.isPaused {
                    focusManager.resumeFocus()
                } else {
                    focusManager.pauseFocus()
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: session.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: largeControlSize))
                    Text(session.isPaused ? "Resume" : "Pause")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
            .accessibilityLabel(session.isPaused ? "Resume focus timer" : "Pause focus timer")

            if focusManager.isRunActive {
                Button {
                    focusManager.skipToNextInRun()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "forward.end.circle.fill")
                            .font(.system(size: smallControlSize))
                        Text("Skip")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.secondary)
                }
                .accessibilityLabel("Skip to next task")
            }

            Button {
                focusManager.endFocus()
                dismiss()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: smallControlSize))
                    Text("End")
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }
            .accessibilityLabel("End focus session")
        }
    }
}
#endif
