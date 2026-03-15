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

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
