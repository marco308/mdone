import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Configuration

struct FocusTaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusTaskAttributes.self) { context in
            // Lock Screen / Banner presentation
            lockScreenView(context: context)
                .widgetURL(URL(string: "mdone://focus"))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded presentation
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.taskTitle)
                            .font(.headline)
                            .lineLimit(2)
                        Text(context.attributes.projectName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        timerView(context: context, font: .title3)
                        statusIcon(isPaused: context.state.isPaused)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Tap to return to mDone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                timerView(context: context, font: .caption2)
                    .frame(width: 50)
            } minimal: {
                Image(systemName: "scope")
                    .foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "mdone://focus"))
        }
    }
}

// MARK: - Lock Screen View

private func lockScreenView(context: ActivityViewContext<FocusTaskAttributes>) -> some View {
    HStack(spacing: 12) {
        // Left: priority dot + task info
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(priorityColor(context.attributes.priorityLevel))
                    .frame(width: 8, height: 8)
                Text(context.attributes.taskTitle)
                    .font(.headline)
                    .lineLimit(2)
            }
            Text(context.attributes.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        // Right: timer + status
        VStack(alignment: .trailing, spacing: 4) {
            timerView(context: context, font: .title2)
            statusIcon(isPaused: context.state.isPaused)
        }
    }
    .padding()
}

// MARK: - Shared Subviews

@ViewBuilder
private func timerView(
    context: ActivityViewContext<FocusTaskAttributes>,
    font: Font
) -> some View {
    if context.state.isPaused {
        Text(formatWidgetElapsed(context.state.elapsedBeforePause))
            .font(font.monospacedDigit())
            .foregroundStyle(.secondary)
    } else {
        Text(
            timerInterval: context.state.focusStartDate ... .distantFuture,
            countsDown: false
        )
        .font(font.monospacedDigit())
        .multilineTextAlignment(.trailing)
    }
}

@ViewBuilder
private func statusIcon(isPaused: Bool) -> some View {
    if isPaused {
        Image(systemName: "pause.circle.fill")
            .font(.caption)
            .foregroundStyle(.yellow)
    } else {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Helpers

private func priorityColor(_ level: Int) -> Color {
    switch level {
    case 5, 4: .red
    case 3: .orange
    case 2: .yellow
    case 1: .blue
    default: .gray
    }
}

private func formatWidgetElapsed(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(interval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
