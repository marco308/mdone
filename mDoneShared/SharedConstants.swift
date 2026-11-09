import Foundation

enum FocusConstants {
    static let appGroupID = "group.com.mdone.app"
    static let focusSessionKey = "com.mdone.focusSession"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

enum SharedKeys {
    static let appGroupID = "group.com.mdone.app"
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

/// The Vikunja REST API the app and its widgets talk to. The version lives
/// here and nowhere else, so moving to `/api/v2` (#289) is one edit plus
/// whatever really differs between the two.
enum VikunjaAPI {
    static let basePath = "/api/v1"

    /// The full path of an API route: `path("/tasks/1")` is `/api/v1/tasks/1`.
    static func path(_ route: String) -> String {
        basePath + route
    }
}
