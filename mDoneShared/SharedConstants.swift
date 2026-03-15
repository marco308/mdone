import Foundation

enum FocusConstants {
    static let appGroupID = "group.com.mdone.app"
    static let focusSessionKey = "com.mdone.focusSession"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
