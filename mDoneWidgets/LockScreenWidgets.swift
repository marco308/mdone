import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct LockScreenProvider: TimelineProvider {
    func placeholder(in _: Context) -> LockScreenEntry {
        LockScreenEntry(
            date: Date(),
            todayCount: 3,
            overdueCount: 1,
            nextTask: WidgetTask.placeholders(count: 1).first,
            isAuthenticated: true
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (LockScreenEntry) -> Void) {
        if let cached = WidgetDataProvider.shared.cachedWidgetData() {
            let allTasks = cached.todayTasks + cached.overdueTasks
            completion(LockScreenEntry(
                date: cached.lastUpdated,
                todayCount: cached.todayTasks.count,
                overdueCount: cached.overdueTasks.count,
                nextTask: allTasks.first,
                isAuthenticated: true
            ))
        } else {
            completion(LockScreenEntry(
                date: Date(),
                todayCount: 3,
                overdueCount: 1,
                nextTask: WidgetTask.placeholders(count: 1).first,
                isAuthenticated: true
            ))
        }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        guard WidgetDataProvider.shared.isAuthenticated else {
            let entry = LockScreenEntry(
                date: Date(),
                todayCount: 0,
                overdueCount: 0,
                nextTask: nil,
                isAuthenticated: false
            )
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
            completion(timeline)
            return
        }

        Task {
            do {
                let data = try await WidgetDataProvider.shared.fetchWidgetData()
                let allTasks = data.todayTasks + data.overdueTasks
                let entry = LockScreenEntry(
                    date: data.lastUpdated,
                    todayCount: data.todayTasks.count,
                    overdueCount: data.overdueTasks.count,
                    nextTask: allTasks.first,
                    isAuthenticated: true
                )
                let nextRefresh = Date().addingTimeInterval(30 * 60)
                let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
                completion(timeline)
            } catch {
                let cached = WidgetDataProvider.shared.cachedWidgetData()
                let allTasks = (cached?.todayTasks ?? []) + (cached?.overdueTasks ?? [])
                let entry = LockScreenEntry(
                    date: Date(),
                    todayCount: cached?.todayTasks.count ?? 0,
                    overdueCount: cached?.overdueTasks.count ?? 0,
                    nextTask: allTasks.first,
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

struct LockScreenEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
    let overdueCount: Int
    let nextTask: WidgetTask?
    let isAuthenticated: Bool

    var totalDueCount: Int {
        todayCount + overdueCount
    }
}

// MARK: - Accessory Circular Widget View

struct LockScreenCircularView: View {
    let entry: LockScreenEntry

    var body: some View {
        if !entry.isAuthenticated {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title3)
        } else {
            Gauge(
                value: min(Double(entry.totalDueCount), 10.0),
                in: 0 ... 10.0
            ) {
                Text("Tasks")
            } currentValueLabel: {
                Text("\(entry.totalDueCount)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(entry.overdueCount > 0 ? .red : .blue)
        }
    }
}

// MARK: - Accessory Rectangular Widget View

struct LockScreenRectangularView: View {
    let entry: LockScreenEntry

    var body: some View {
        if !entry.isAuthenticated {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("Sign in to mDone")
                    .font(.caption)
            }
        } else if let task = entry.nextTask {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(task.priorityColor)
                        .frame(width: 6, height: 6)
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let dueDate = task.dueDate {
                    Text(dueDate, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("mDone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("No tasks due")
                    .font(.headline)
                Text("mDone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Accessory Inline Widget View

struct LockScreenInlineView: View {
    let entry: LockScreenEntry

    var body: some View {
        if !entry.isAuthenticated {
            Text("Sign in to mDone")
        } else if entry.totalDueCount == 0 {
            Text("No tasks due today")
        } else if entry.totalDueCount == 1, let task = entry.nextTask {
            Text(task.title)
                .lineLimit(1)
        } else {
            Text("\(entry.totalDueCount) tasks due today")
        }
    }
}

// MARK: - Circular Widget

struct LockScreenCircularWidget: Widget {
    let kind: String = "LockScreenCircularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            LockScreenCircularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Task Count")
        .description("Shows the number of tasks due today.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Rectangular Widget

struct LockScreenRectangularWidget: Widget {
    let kind: String = "LockScreenRectangularWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            LockScreenRectangularView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Task")
        .description("Shows your next upcoming task.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Inline Widget

struct LockScreenInlineWidget: Widget {
    let kind: String = "LockScreenInlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            LockScreenInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tasks Due")
        .description("Shows tasks due today in a single line.")
        .supportedFamilies([.accessoryInline])
    }
}
