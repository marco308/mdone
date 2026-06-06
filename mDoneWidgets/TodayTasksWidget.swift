import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct TodayTasksProvider: AppIntentTimelineProvider {
    typealias Intent = TodayWidgetSettingsIntent
    typealias Entry = TodayTasksEntry

    func placeholder(in _: Context) -> TodayTasksEntry {
        TodayTasksEntry(
            date: Date(),
            tasks: WidgetTask.placeholders(count: 3),
            overdueTasks: [],
            isAuthenticated: true,
            configuration: TodayWidgetSettingsIntent()
        )
    }

    func snapshot(for configuration: TodayWidgetSettingsIntent, in _: Context) async -> TodayTasksEntry {
        if let cached = WidgetDataProvider.shared.cachedWidgetData() {
            return TodayTasksEntry(
                date: cached.lastUpdated,
                tasks: cached.todayTasks,
                overdueTasks: cached.overdueTasks,
                isAuthenticated: true,
                configuration: configuration
            )
        }
        return TodayTasksEntry(
            date: Date(),
            tasks: WidgetTask.placeholders(count: 3),
            overdueTasks: [],
            isAuthenticated: true,
            configuration: configuration
        )
    }

    func timeline(for configuration: TodayWidgetSettingsIntent, in _: Context) async -> Timeline<TodayTasksEntry> {
        guard WidgetDataProvider.shared.isAuthenticated else {
            let entry = TodayTasksEntry(
                date: Date(),
                tasks: [],
                overdueTasks: [],
                isAuthenticated: false,
                configuration: configuration
            )
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        }

        do {
            let data = try await WidgetDataProvider.shared.fetchWidgetData()
            let entry = TodayTasksEntry(
                date: data.lastUpdated,
                tasks: data.todayTasks,
                overdueTasks: data.overdueTasks,
                isAuthenticated: true,
                configuration: configuration
            )
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
        } catch {
            let cached = WidgetDataProvider.shared.cachedWidgetData()
            let entry = TodayTasksEntry(
                date: Date(),
                tasks: cached?.todayTasks ?? [],
                overdueTasks: cached?.overdueTasks ?? [],
                isAuthenticated: true,
                configuration: configuration
            )
            return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        }
    }
}

// MARK: - Timeline Entry

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTask]
    let overdueTasks: [WidgetTask]
    let isAuthenticated: Bool
    let configuration: TodayWidgetSettingsIntent
}

// MARK: - Widget View

struct TodayTasksWidgetView: View {
    let entry: TodayTasksEntry
    @Environment(\.widgetFamily) var family

    private var fontSize: WidgetFontSize { entry.configuration.fontSize }
    private var filterMode: TodayTaskFilterMode { entry.configuration.filterMode }

    /// Calm Mode (set in the app, mirrored to the App Group): when on, overdue
    /// tasks are shown without any red highlight or separate grouping.
    private var calmMode: Bool { SharedKeys.sharedDefaults.bool(forKey: SharedKeys.calmModeKey) }

    private var visibleTodayTasks: [WidgetTask] {
        filterMode == .overdueOnly ? [] : entry.tasks
    }

    private var visibleOverdueTasks: [WidgetTask] {
        filterMode == .todayOnly ? [] : entry.overdueTasks
    }

    /// Total rows the widget can fit, by family and font size.
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

    /// Maximum overdue rows to surface (rest become "+N more").
    private var maxOverdueRows: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        case .systemLarge, .systemExtraLarge: 4
        default: 1
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
                    if visibleTodayTasks.isEmpty, visibleOverdueTasks.isEmpty {
                        emptyStateView
                    } else {
                        taskListView
                    }
                }
                // Pin to the top so that if the rows ever exceed the canvas the
                // overflow spills off the bottom (where the "+N more" hint lives)
                // instead of centering and pushing the header off the top (#99).
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("All caught up!")
                .font(.headline)
            if family != .systemSmall {
                Text(emptyStateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateSubtitle: String {
        switch filterMode {
        case .todayAndOverdue: "No tasks due today"
        case .todayOnly: "No tasks due today"
        case .overdueOnly: "Nothing overdue"
        }
    }

    // MARK: - Task List

    private var taskListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            let totalAvailable = visibleOverdueTasks.count + visibleTodayTasks.count
            // Reserve one line for the "+N more" footer when not everything fits,
            // so the footer never pushes the list one row past maxRows and over
            // the edge of the widget (#99).
            let rowBudget = totalAvailable > maxRows ? max(maxRows - 1, 1) : maxRows
            // When only one bucket is shown (overdue-only or today-only), let it
            // claim all available rows instead of capping at maxOverdueRows.
            let overdueCap = visibleTodayTasks.isEmpty ? rowBudget : maxOverdueRows
            let overdueLimit = min(visibleOverdueTasks.count, overdueCap)
            let todayLimit = max(rowBudget - overdueLimit, 0)
            let visibleOverdue = Array(visibleOverdueTasks.prefix(overdueLimit))
            let visibleToday = Array(visibleTodayTasks.prefix(todayLimit))

            if !visibleOverdue.isEmpty {
                if calmMode {
                    // Calm Mode: overdue rows look like any other task — no red box.
                    ForEach(visibleOverdue) { task in
                        taskRow(task: task)
                    }
                } else {
                    overdueSection(tasks: visibleOverdue)
                }
            }

            ForEach(visibleToday) { task in
                taskRow(task: task)
            }

            let totalShown = visibleOverdue.count + visibleToday.count
            if totalAvailable > totalShown {
                Text("+\(totalAvailable - totalShown) more")
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
            Text(headerTitle)
                .font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            let totalCount = visibleTodayTasks.count + visibleOverdueTasks.count
            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(visibleOverdueTasks.isEmpty || calmMode ? Color.blue : Color.red)
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

    private var headerTitle: String {
        switch filterMode {
        case .todayAndOverdue, .todayOnly: "Today"
        case .overdueOnly: "Overdue"
        }
    }

    // MARK: - Overdue Section

    private func overdueSection(tasks: [WidgetTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tasks) { task in
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
        rowContent(task: task, isOverdue: isOverdue)
            .padding(.vertical, rowVerticalPadding)
            .padding(.horizontal, 4)
    }

    private func rowContent(task: WidgetTask, isOverdue: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(task.priorityColor)
                .frame(width: 3, height: rowAccentHeight)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(titleFont)
                    .lineLimit(1)
                    .foregroundStyle(isOverdue ? .red : .primary)

                if let dueDate = task.dueDate, family != .systemSmall || fontSize == .compact {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: clockGlyphSize))
                        Text(dueDate, format: .dateTime.hour().minute())
                            .font(subtitleFont)
                    }
                    .foregroundStyle(isOverdue ? .red : .secondary)
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
        case .compact: 20
        case .standard: 28
        case .large: 34
        }
    }

    private var clockGlyphSize: CGFloat {
        switch fontSize {
        case .compact: 7
        case .standard: 8
        case .large: 10
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

struct TodayTasksWidget: Widget {
    let kind: String = "TodayTasksWidget"

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
            intent: TodayWidgetSettingsIntent.self,
            provider: TodayTasksProvider()
        ) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Tasks")
        .description("Tasks due today and overdue. Long-press to customise.")
        .supportedFamilies(supportedFamilies)
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
