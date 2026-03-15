import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct QuickAddProvider: TimelineProvider {
    func placeholder(in _: Context) -> QuickAddEntry {
        QuickAddEntry(date: Date())
    }

    func getSnapshot(in _: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: Date()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        let entry = QuickAddEntry(date: Date())
        // Static content, rarely needs refresh
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60)))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

// MARK: - Widget View

struct QuickAddWidgetView: View {
    let entry: QuickAddEntry

    var body: some View {
        Link(destination: URL(string: "mdone://create")!) {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text("Add Task")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Configuration

struct QuickAddWidget: Widget {
    let kind: String = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddProvider()) { entry in
            QuickAddWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Add")
        .description("Quickly add a new task to mDone.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
