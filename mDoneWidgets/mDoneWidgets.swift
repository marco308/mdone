import SwiftUI
import WidgetKit

@main
struct mDoneWidgets: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        UpcomingWidget()
        QuickAddWidget()
        LockScreenCircularWidget()
        LockScreenRectangularWidget()
        LockScreenInlineWidget()
        FocusTaskLiveActivity()
    }
}
