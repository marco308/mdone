import SwiftUI
import WidgetKit

@main
struct mDoneWidgets: WidgetBundle {
    var body: some Widget {
        TodayTasksWidget()
        UpcomingWidget()
        QuickAddWidget()
        #if os(iOS)
        LockScreenCircularWidget()
        LockScreenRectangularWidget()
        LockScreenInlineWidget()
        FocusTaskLiveActivity()
        #endif
    }
}
