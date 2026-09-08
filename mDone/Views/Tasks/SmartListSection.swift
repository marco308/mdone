import SwiftUI

/// One dated section of the Inbox (Overdue, Today, Tomorrow, ...). These
/// sections are defined by date and span every project, so they cannot be
/// reordered by hand: a task's position lives in its own project's list
/// view, and nothing dropped here could ever be shown here. Manual order is
/// a project list feature (`TaskListScreen`, `MacTaskListView`).
struct SmartListSection: View {
    let title: String
    let tasks: [VTask]
    let accentColor: Color
    /// Forwarded to each `TaskRow` so the Current section can show progress bars.
    var showsProgress: Bool = false

    var body: some View {
        let rows = TaskNesting.rows(for: tasks)
        Section {
            // One ForEach for both flat and nested display, so a row's
            // identity survives the list gaining/losing nesting; otherwise a
            // detail sheet presented from a row gets torn down the moment its
            // task's first subtask is linked.
            ForEach(rows) { row in
                TaskRow(task: row.task, showsProgress: showsProgress, indentLevel: row.depth)
                    .tag(row.task)
            }
        } header: {
            HStack {
                Text(title)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(accentColor)

                Spacer()

                Text("\(tasks.count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "\(title), \(tasks.count) tasks"))
            .accessibilityAddTraits(.isHeader)
        }
    }
}
