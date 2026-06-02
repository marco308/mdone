#if os(iOS)
import SwiftUI
import UIKit
import WidgetKit
import XCTest

/// Marketing-screenshot generator for the home-screen widgets.
///
/// Renders the real widget views (`TodayTasksWidgetView`, `UpcomingWidgetView`)
/// to PNGs via `ImageRenderer` with mock data — no server, no home-screen
/// automation. This target compiles the widget views + shared models directly
/// (the same source set the extension builds from) and has no dependency on the
/// app, so there is no module/type clash.
///
/// Self-disables outside the dev worktree, so a normal checkout and CI skip it.
@MainActor
final class WidgetShotRenderTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// A time today at the given hour/minute, for realistic due-time labels.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func daysOut(_ days: Int, _ hour: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: at(hour))
    }

    /// Wrap a widget view in a rounded white tile at the family's point size.
    /// `.containerBackground` is a no-op outside a real widget host, so we supply
    /// the background and content margins ourselves.
    private func tile(_ content: some View, family: WidgetFamily, width: CGFloat, height: CGFloat) -> some View {
        // `\.widgetFamily` is read-only; WidgetPreviewContext is the supported way
        // to evaluate a widget view for a specific family.
        content
            .previewContext(WidgetPreviewContext(family: family))
            .padding(14)
            .frame(width: width, height: height)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .environment(\.colorScheme, .light)
    }

    private func write(_ tile: some View, to name: String) throws {
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 3
        renderer.isOpaque = false
        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("ImageRenderer produced no image for \(name)")
            return
        }
        let url = repoRoot.appendingPathComponent("website/assets/\(name)")
        try data.write(to: url)
        print("[render] \(Int(image.size.width))x\(Int(image.size.height)) -> \(url.lastPathComponent)")
    }

    func testRenderWidgets() throws {
        try XCTSkipUnless(
            #file.contains("/.claude/worktrees/"),
            "Screenshot generator — only runs from the dev worktree."
        )

        let work = "Work"
        let home = "Home"

        // Today's Tasks — medium: one overdue (red) + two due today.
        let todayMedium = TodayTasksEntry(
            date: Date(),
            tasks: [
                WidgetTask(
                    id: 1,
                    title: "Finalize Q1 report",
                    done: false,
                    dueDate: at(17),
                    priority: 3,
                    projectId: 1,
                    projectTitle: work,
                    isOverdue: false
                ),
                WidgetTask(
                    id: 2,
                    title: "Prepare slide deck",
                    done: false,
                    dueDate: at(14),
                    priority: 2,
                    projectId: 1,
                    projectTitle: work,
                    isOverdue: false
                ),
            ],
            overdueTasks: [
                WidgetTask(
                    id: 5,
                    title: "Reply to landlord",
                    done: false,
                    dueDate: at(9),
                    priority: 4,
                    projectId: 2,
                    projectTitle: home,
                    isOverdue: true
                ),
            ],
            isAuthenticated: true,
            configuration: TodayWidgetSettingsIntent()
        )
        try write(
            tile(TodayTasksWidgetView(entry: todayMedium), family: .systemMedium, width: 360, height: 170),
            to: "shot-widget-today-medium.png"
        )

        // Upcoming — medium.
        let upcoming = UpcomingTasksEntry(
            date: Date(),
            tasks: [
                WidgetTask(
                    id: 11,
                    title: "Dentist appointment",
                    done: false,
                    dueDate: daysOut(1, 10),
                    priority: 2,
                    projectId: 2,
                    projectTitle: home,
                    isOverdue: false
                ),
                WidgetTask(
                    id: 12,
                    title: "Renew passport",
                    done: false,
                    dueDate: daysOut(3, 9),
                    priority: 4,
                    projectId: 2,
                    projectTitle: home,
                    isOverdue: false
                ),
                WidgetTask(
                    id: 13,
                    title: "Team offsite prep",
                    done: false,
                    dueDate: daysOut(4, 15),
                    priority: 3,
                    projectId: 1,
                    projectTitle: work,
                    isOverdue: false
                ),
            ],
            isAuthenticated: true,
            configuration: UpcomingWidgetSettingsIntent()
        )
        try write(
            tile(UpcomingWidgetView(entry: upcoming), family: .systemMedium, width: 360, height: 170),
            to: "shot-widget-upcoming.png"
        )
    }
}
#endif
