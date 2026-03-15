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
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading) {
                    Text("Focusing")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
#endif
