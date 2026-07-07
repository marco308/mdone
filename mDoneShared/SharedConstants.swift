import Foundation

enum FocusConstants {
    static let appGroupID = "group.com.ncastillo.mdone.app"
    static let focusSessionKey = "com.mdone.focusSession"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

enum SharedKeys {
    static let appGroupID = "group.com.ncastillo.mdone.app"
    static let apiTokenKey = "com.mdone.shared.apiToken"
    static let serverURLKey = "com.mdone.shared.serverURL"
    static let widgetDataKey = "com.mdone.shared.widgetData"
    /// Calm Mode: when true, overdue tasks are shown without any special
    /// highlighting (no red, no separate "Overdue" grouping or counts).
    /// Mirrored from the app's `@AppStorage("calmMode")` so widgets can read it.
    static let calmModeKey = "com.mdone.shared.calmMode"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
