import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct TodayTasksProvider: TimelineProvider {
    func placeholder(in _: Context) -> TodayTasksEntry {
        TodayTasksEntry(
            date: Date(),
            tasks: WidgetTask.placeholders(count: 3),
            overdueTasks: [],
            isAuthenticated: true
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (TodayTasksEntry) -> Void) {
        if let cached = WidgetDataProvider.shared.cachedWidgetData() {
            completion(TodayTasksEntry(
                date: cached.lastUpdated,
                tasks: cached.todayTasks,
                overdueTasks: cached.overdueTasks,
                isAuthenticated: true
            ))
        } else {
            completion(TodayTasksEntry(
                date: Date(),
                tasks: WidgetTask.placeholders(count: 3),
                overdueTasks: [],
                isAuthenticated: true
            ))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TodayTasksEntry>) -> Void) {
        guard WidgetDataProvider.shared.isAuthenticated else {
            let entry = TodayTasksEntry(
                date: Date(),
                tasks: [],
                overdueTasks: [],
                isAuthenticated: false
            )
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
            completion(timeline)
            return
        }

        Task {
            do {
                let data = try await WidgetDataProvider.shared.fetchWidgetData()
                let entry = TodayTasksEntry(
                    date: data.lastUpdated,
                    tasks: data.todayTasks,
                    overdueTasks: data.overdueTasks,
                    isAuthenticated: true
                )
                let nextRefresh = Date().addingTimeInterval(30 * 60)
                let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
                completion(timeline)
            } catch {
                // Fall back to cached data
                let cached = WidgetDataProvider.shared.cachedWidgetData()
                let entry = TodayTasksEntry(
                    date: Date(),
                    tasks: cached?.todayTasks ?? [],
                    overdueTasks: cached?.overdueTasks ?? [],
                    isAuthenticated: true
                )
                let nextRefresh = Date().addingTimeInterval(15 * 60)
                let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
                completion(timeline)
            }
        }
    }
}

// MARK: - Timeline Entry

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let overdueTasks: [WidgetTask]
    let isAuthenticated: Bool
}

// MARK: - Widget View

struct TodayTasksWidgetView: View {
    let entry: TodayTasksEntry
    @Environment(\.widgetFamily) var family

    private var maxTasks: Int {
        switch family {
        case .systemLarge: 8
        default: 4
        }
    }

    private var maxOverdue: Int {
        switch family {
        case .systemLarge: 3
        default: 1
        }
    }

    var body: some View {
        Group {
            if !entry.isAuthenticated {
                unauthenticatedView
            } else if entry.tasks.isEmpty, entry.overdueTasks.isEmpty {
                emptyStateView
            } else {
                taskListView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Unauthenticated

    private var unauthenticatedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Open mDone to sign in")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("All caught up!")
                .font(.headline)
            Text("No tasks due today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task List

    private var taskListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.bottom, 6)

            // Overdue section
            if !entry.overdueTasks.isEmpty {
                overdueSection
            }

            // Today tasks
            let todayLimit = maxTasks - min(entry.overdueTasks.count, maxOverdue)
            let visibleTasks = Array(entry.tasks.prefix(todayLimit))
            ForEach(visibleTasks) { task in
                taskRow(task: task)
            }

            let totalShown = min(entry.overdueTasks.count, maxOverdue) + visibleTasks.count
            let totalAvailable = entry.overdueTasks.count + entry.tasks.count
            if totalAvailable > totalShown {
                Spacer(minLength: 4)
                Text("+\(totalAvailable - totalShown) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Today")
                .font(.headline)
            let totalCount = entry.tasks.count + entry.overdueTasks.count
            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(entry.overdueTasks.isEmpty ? .blue : .red)
                    )
            }
            Spacer()
        }
    }

    // MARK: - Overdue Section

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let visibleOverdue = Array(entry.overdueTasks.prefix(maxOverdue))
            ForEach(visibleOverdue) { task in
                taskRow(task: task, isOverdue: true)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.red.opacity(0.08))
        )
        .padding(.bottom, 2)
    }

    // MARK: - Task Row

    private func taskRow(task: WidgetTask, isOverdue: Bool = false) -> some View {
        HStack(spacing: 8) {
            // Priority color bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.priorityColor)
                .frame(width: 3, height: 28)

            // Task title
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isOverdue ? .red : .primary)

                if let dueDate = task.dueDate {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text(dueDate, format: .dateTime.hour().minute())
                            .font(.caption2)
                    }
                    .foregroundStyle(isOverdue ? .red : .secondary)
                }
            }

            Spacer(minLength: 4)

            // Complete button
            Button(intent: CompleteTaskIntent(taskID: task.id)) {
                Image(systemName: "circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }
}

// MARK: - Widget Configuration

struct TodayTasksWidget: Widget {
    let kind: String = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Tasks")
        .description("Shows tasks due today and overdue tasks.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Placeholder Helpers

extension WidgetTask {
    static func placeholders(count: Int) -> [WidgetTask] {
        (0 ..< count).map { index in
            WidgetTask(
                id: Int64(index),
                title: "Sample Task \(index + 1)",
                done: false,
                dueDate: Calendar.current.date(byAdding: .hour, value: index + 1, to: Date()),
                priority: [0, 1, 2, 3][index % 4],
                projectId: 1,
                projectTitle: "Project",
                isOverdue: false
            )
        }
    }
}
