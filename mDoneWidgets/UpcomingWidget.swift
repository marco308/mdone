import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct UpcomingTasksProvider: AppIntentTimelineProvider {
    typealias Intent = UpcomingWidgetSettingsIntent
    typealias Entry = UpcomingTasksEntry

    func placeholder(in _: Context) -> UpcomingTasksEntry {
        UpcomingTasksEntry(
            date: Date(),
            tasks: WidgetTask.placeholders(count: 3),
            isAuthenticated: true,
            configuration: UpcomingWidgetSettingsIntent()
        )
    }

    func snapshot(for configuration: UpcomingWidgetSettingsIntent, in _: Context) async -> UpcomingTasksEntry {
        if let cached = WidgetDataProvider.shared.cachedWidgetData() {
            return UpcomingTasksEntry(
                date: cached.lastUpdated,
                tasks: cached.upcomingTasks,
                isAuthenticated: true,
                configuration: configuration
            )
        }
        return UpcomingTasksEntry(
            date: Date(),
            tasks: WidgetTask.placeholders(count: 3),
            isAuthenticated: true,
            configuration: configuration
        )
    }

    func timeline(
        for configuration: UpcomingWidgetSettingsIntent,
        in _: Context
    ) async -> Timeline<UpcomingTasksEntry> {
        guard WidgetDataProvider.shared.isAuthenticated else {
            let entry = UpcomingTasksEntry(
                date: Date(),
                tasks: [],
                isAuthenticated: false,
                configuration: configuration
            )
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        }

        do {
            let data = try await WidgetDataProvider.shared.fetchWidgetData()
            let entry = UpcomingTasksEntry(
                date: data.lastUpdated,
                tasks: data.upcomingTasks,
                isAuthenticated: true,
                configuration: configuration
            )
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
        } catch {
            let cached = WidgetDataProvider.shared.cachedWidgetData()
            let entry = UpcomingTasksEntry(
                date: Date(),
                tasks: cached?.upcomingTasks ?? [],
                isAuthenticated: true,
                configuration: configuration
            )
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        }
    }
}

// MARK: - Timeline Entry

struct UpcomingTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let isAuthenticated: Bool
    let configuration: UpcomingWidgetSettingsIntent
}

// MARK: - Widget View

struct UpcomingWidgetView: View {
    let entry: UpcomingTasksEntry
    @Environment(\.widgetFamily) var family

    private var fontSize: WidgetFontSize { entry.configuration.fontSize }

    private var maxRows: Int {
        switch (family, fontSize) {
        case (.systemSmall, .compact): 3
        case (.systemSmall, .standard): 2
        case (.systemSmall, .large): 2
        case (.systemMedium, .compact): 4
        case (.systemMedium, .standard): 3
        case (.systemMedium, .large): 2
        case (.systemLarge, .compact): 9
        case (.systemLarge, .standard): 7
        case (.systemLarge, .large): 5
        case (.systemExtraLarge, .compact): 9
        case (.systemExtraLarge, .standard): 7
        case (.systemExtraLarge, .large): 5
        default: 3
        }
    }

    var body: some View {
        Group {
            if !entry.isAuthenticated {
                unauthenticatedView
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    headerView
                        .padding(.bottom, 4)
                    if entry.tasks.isEmpty {
                        emptyStateView
                    } else {
                        taskListView
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
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
                .multilineTextAlignment(.center)
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task List

    private var taskListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            let visibleTasks = Array(entry.tasks.prefix(maxRows))
            ForEach(visibleTasks) { task in
                taskRow(task: task)
            }

            if entry.tasks.count > visibleTasks.count {
                Text("+\(entry.tasks.count - visibleTasks.count) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(family == .systemSmall ? .caption : .subheadline)
                .foregroundStyle(.blue)
            Text("Upcoming")
                .font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !entry.tasks.isEmpty {
                Text("\(entry.tasks.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                    )
                    .layoutPriority(1)
            }

            Spacer(minLength: 0)

            if entry.configuration.showAddTaskButton {
                Link(destination: URL(string: "mdone://create")!) {
                    Image(systemName: "plus.circle.fill")
                        .font(family == .systemSmall ? .subheadline : .body)
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Add Task")
                }
            }
        }
    }

    // MARK: - Task Row

    private func taskRow(task: WidgetTask) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.priorityColor)
                .frame(width: 3, height: rowAccentHeight)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(titleFont)
                    .lineLimit(1)

                if let dueDate = task.dueDate, family != .systemSmall || fontSize == .compact {
                    Text(formattedDueDate(dueDate))
                        .font(subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if entry.configuration.showCompleteButton {
                Button(intent: CompleteTaskIntent(taskID: task.id)) {
                    Image(systemName: "circle")
                        .font(completeButtonFont)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(task.title)")
            }
        }
        .padding(.vertical, rowVerticalPadding)
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

        if let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now),
           date < weekFromNow
        {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            return formatWithTime(dayFormatter.string(from: date), date: date)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return formatWithTime(dateFormatter.string(from: date), date: date)
    }

    private func formatWithTime(_ prefix: String, date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        if hour == 0, minute == 0 {
            return prefix
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        return "\(prefix), \(timeFormatter.string(from: date))"
    }

    // MARK: - Sizing helpers

    private var titleFont: Font {
        switch fontSize {
        case .compact: .caption
        case .standard: .subheadline
        case .large: .body
        }
    }

    private var subtitleFont: Font {
        switch fontSize {
        case .compact: .caption2
        case .standard: .caption2
        case .large: .caption
        }
    }

    private var rowVerticalPadding: CGFloat {
        switch fontSize {
        case .compact: 2
        case .standard: 3
        case .large: 5
        }
    }

    private var rowAccentHeight: CGFloat {
        switch fontSize {
        case .compact: 22
        case .standard: 32
        case .large: 38
        }
    }

    private var completeButtonFont: Font {
        switch fontSize {
        case .compact: .subheadline
        case .standard: .body
        case .large: .title3
        }
    }
}

// MARK: - Widget Configuration

struct UpcomingWidget: Widget {
    let kind: String = "UpcomingWidget"

    var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        } else {
            return [.systemSmall, .systemMedium, .systemLarge]
        }
        #else
        return [.systemSmall, .systemMedium, .systemLarge]
        #endif
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: UpcomingWidgetSettingsIntent.self,
            provider: UpcomingTasksProvider()
        ) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming Deadlines")
        .description("Tasks with upcoming due dates. Long-press to customise.")
        .supportedFamilies(supportedFamilies)
    }
}
