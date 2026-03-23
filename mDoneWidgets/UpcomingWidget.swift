import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct UpcomingTasksProvider: TimelineProvider {
    func placeholder(in _: Context) -> UpcomingTasksEntry {
        UpcomingTasksEntry(
            date: Date(),
            tasks: WidgetTask.placeholders(count: 3),
            isAuthenticated: true
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (UpcomingTasksEntry) -> Void) {
        if let cached = WidgetDataProvider.shared.cachedWidgetData() {
            completion(UpcomingTasksEntry(
                date: cached.lastUpdated,
                tasks: cached.upcomingTasks,
                isAuthenticated: true
            ))
        } else {
            completion(UpcomingTasksEntry(
                date: Date(),
                tasks: WidgetTask.placeholders(count: 3),
                isAuthenticated: true
            ))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<UpcomingTasksEntry>) -> Void) {
        guard WidgetDataProvider.shared.isAuthenticated else {
            let entry = UpcomingTasksEntry(
                date: Date(),
                tasks: [],
                isAuthenticated: false
            )
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
            completion(timeline)
            return
        }

        Task {
            do {
                let data = try await WidgetDataProvider.shared.fetchWidgetData()
                let entry = UpcomingTasksEntry(
                    date: data.lastUpdated,
                    tasks: data.upcomingTasks,
                    isAuthenticated: true
                )
                let nextRefresh = Date().addingTimeInterval(30 * 60)
                let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
                completion(timeline)
            } catch {
                let cached = WidgetDataProvider.shared.cachedWidgetData()
                let entry = UpcomingTasksEntry(
                    date: Date(),
                    tasks: cached?.upcomingTasks ?? [],
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

struct UpcomingTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let isAuthenticated: Bool
}

// MARK: - Widget View

struct UpcomingWidgetView: View {
    let entry: UpcomingTasksEntry
    @Environment(\.widgetFamily) var family

    private var maxTasks: Int {
        switch family {
        case .systemLarge: 8
        default: 4
        }
    }

    var body: some View {
        Group {
            if !entry.isAuthenticated {
                unauthenticatedView
            } else if entry.tasks.isEmpty {
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
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No upcoming tasks")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task List

    private var taskListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.bottom, 6)

            let visibleTasks = Array(entry.tasks.prefix(maxTasks))
            ForEach(visibleTasks) { task in
                taskRow(task: task)
            }

            if entry.tasks.count > maxTasks {
                Spacer(minLength: 4)
                Text("+\(entry.tasks.count - maxTasks) more")
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
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(.blue)
            Text("Upcoming")
                .font(.headline)
            if !entry.tasks.isEmpty {
                Text("\(entry.tasks.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.blue)
                    )
            }
            Spacer()
        }
    }

    // MARK: - Task Row

    private func taskRow(task: WidgetTask) -> some View {
        HStack(spacing: 8) {
            // Priority color bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.priorityColor)
                .frame(width: 3, height: 32)

            // Task info
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)

                if let dueDate = task.dueDate {
                    Text(formattedDueDate(dueDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    // MARK: - Date Formatting

    private func formattedDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInTomorrow(date) {
            return formatWithTime("Tomorrow", date: date)
        }

        if calendar.isDateInToday(date) {
            return formatWithTime("Today", date: date)
        }

        // Within the next 7 days: show day name
        if let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now),
           date < weekFromNow
        {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            return formatWithTime(dayFormatter.string(from: date), date: date)
        }

        // Beyond a week: show date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return formatWithTime(dateFormatter.string(from: date), date: date)
    }

    private func formatWithTime(_ prefix: String, date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        // If the time is midnight (00:00), it likely means no specific time was set
        if hour == 0, minute == 0 {
            return prefix
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return "\(prefix), \(timeFormatter.string(from: date))"
    }
}

// MARK: - Widget Configuration

struct UpcomingWidget: Widget {
    let kind: String = "UpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingTasksProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming Deadlines")
        .description("Shows tasks with upcoming due dates.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
