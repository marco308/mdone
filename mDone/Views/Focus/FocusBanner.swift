import SwiftUI

#if os(iOS)
func formatElapsed(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}

struct FocusBanner: View {
    let session: FocusSession
    /// Tasks left after this one when the session is part of a Focus Run.
    var runRemaining: Int?
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)

                VStack(alignment: .leading) {
                    if let runRemaining {
                        Text("Focus Run · \(runRemaining) left")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Text("Focusing")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Text(session.taskTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    Text(formatElapsed(session.totalElapsed(at: timeline.date)))
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focusing on \(session.taskTitle). Tap to open focus session.")
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// Shown in the list when a Focus Run ended while the focus screen was
/// closed, e.g. the last task was ticked off from the list itself.
struct FocusRunFinishedBanner: View {
    let summary: FocusRunSummary
    var onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text("Focus Run Complete")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("You finished \(summary.completedCount) tasks.")
                    .font(.subheadline)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
#endif
