import SwiftData
import SwiftUI

/// Inline row showing accumulated focus time for a task. Renders nothing if
/// there are no recorded sessions — callers should also hide their wrapping
/// section using `hasFocusHistory(for:)` so an empty header doesn't appear.
struct FocusHistoryRow: View {
    let taskId: Int64

    @Query private var records: [FocusRecord]

    init(taskId: Int64) {
        self.taskId = taskId
        _records = Query(filter: #Predicate<FocusRecord> { $0.taskId == taskId })
    }

    var body: some View {
        if !records.isEmpty {
            HStack {
                Label("Focus", systemImage: "scope")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Focused \(accessibleDuration), \(records.count) \(records.count == 1 ? "session" : "sessions")")
            }
        }
    }

    private var total: TimeInterval {
        records.reduce(0) { $0 + $1.focusedSeconds }
    }

    private var summary: String {
        let session = records.count == 1 ? "session" : "sessions"
        return "\(FocusDurationFormatter.string(from: total)) · \(records.count) \(session)"
    }

    private var accessibleDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: total) ?? "0 seconds"
    }
}

/// Used by callers to decide whether to render a section header at all.
struct FocusHistoryGate<Content: View>: View {
    let taskId: Int64
    @ViewBuilder var content: () -> Content

    @Query private var records: [FocusRecord]

    init(taskId: Int64, @ViewBuilder content: @escaping () -> Content) {
        self.taskId = taskId
        self.content = content
        _records = Query(filter: #Predicate<FocusRecord> { $0.taskId == taskId })
    }

    var body: some View {
        if !records.isEmpty {
            content()
        }
    }
}
