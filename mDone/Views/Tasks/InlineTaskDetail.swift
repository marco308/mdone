import SwiftUI

/// Where a tapped task opens on the screen that hosts the row.
///
/// On a phone a task opens in a sheet. On an iPad with room to spare the
/// screen shows a detail pane beside the list instead, and tapping a row
/// selects the task into that pane. `TaskListScreen` puts an instance in the
/// environment only while the pane is on screen, so a row that finds none
/// falls back to the sheet. The decision lives at the screen, not the row,
/// because a Split View or Stage Manager resize can take the pane away while
/// the list stays where it is (issue #34).
@Observable
final class InlineTaskSelection {
    /// The task shown in the pane. A snapshot: the pane prefers the live copy
    /// from `AppState` when there is one, and falls back to this for tasks
    /// that only exist in a board's buckets.
    var task: VTask?
}

/// Pure layout rules for the inline detail pane, kept free of views so they
/// can be unit tested.
enum InlineTaskDetailLayout {
    /// Below this width the list and the pane would both be cramped, so the
    /// task opens in a sheet even though the size class is regular. An iPad
    /// in a two-thirds Split View or a 10-inch iPad in portrait clears it.
    static let minimumContainerWidth: CGFloat = 700

    /// The pane takes this share of the container, within the clamp below.
    static let paneFraction: CGFloat = 0.42
    static let minimumPaneWidth: CGFloat = 340
    static let maximumPaneWidth: CGFloat = 460

    /// True when the screen should host the pane rather than present a sheet.
    static func showsPane(isRegularWidth: Bool, containerWidth: CGFloat) -> Bool {
        isRegularWidth && containerWidth >= minimumContainerWidth
    }

    /// The pane's width for a container of the given width.
    static func paneWidth(for containerWidth: CGFloat) -> CGFloat {
        min(max(containerWidth * paneFraction, minimumPaneWidth), maximumPaneWidth)
    }
}
