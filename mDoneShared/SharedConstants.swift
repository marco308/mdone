import Foundation

/// Which stores this process reads and writes.
///
/// Two things are kept away from the copy of mDone a person actually uses:
///
/// - **Debug builds** are a separate app, "mDone Dev" (`com.mdone.app.dev`),
///   with their own app group. A build run from Xcode or `xcodebuild` gets its
///   own container, keychain items and widgets, and can sit next to the
///   App Store or TestFlight copy without either seeing the other's login.
/// - **Unit tests** get scratch stores that are emptied when the test process
///   starts. A test that signs out, or saves a fake token, used to do it to
///   whichever app hosted the tests, and found whatever that app had left
///   behind.
enum StorageScope {
    /// True when the process has been launched only to host the unit-test
    /// bundle. `XCTestConfigurationFilePath` is set in that host process and
    /// not for a UI-test run, where the app is launched normally by a separate
    /// runner, so UI tests and the widget extension stay on the real stores.
    static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// The app group shared by the app and its widget extension. Must match
    /// `MDONE_APP_GROUP` in `project.yml`, which is what the entitlements use.
    #if DEBUG
    static let appGroupID = "group.com.mdone.app.dev"
    #else
    static let appGroupID = "group.com.mdone.app"
    #endif

    /// Defaults shared between the app and its widgets.
    static let sharedDefaults: UserDefaults = isHostingUnitTests
        ? scratchDefaults("com.mdone.unit-tests.shared")
        : UserDefaults(suiteName: appGroupID) ?? .standard

    /// The app's own defaults, for the things that identify a login. Other
    /// preferences still go through `UserDefaults.standard`.
    static let appDefaults: UserDefaults = isHostingUnitTests
        ? scratchDefaults("com.mdone.unit-tests")
        : .standard

    /// The keychain account to store `name` under. Unit tests get their own
    /// items, so they can never read or delete a real credential.
    static func keychainAccount(_ name: String) -> String {
        isHostingUnitTests ? "unit-tests." + name : name
    }

    /// A defaults suite that starts every test process empty.
    private static func scratchDefaults(_ name: String) -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }
}

enum FocusConstants {
    static let appGroupID = StorageScope.appGroupID
    static let focusSessionKey = "com.mdone.focusSession"

    static var sharedDefaults: UserDefaults {
        StorageScope.sharedDefaults
    }
}

enum SharedKeys {
    static let appGroupID = StorageScope.appGroupID
    static let apiTokenKey = "com.mdone.shared.apiToken"
    static let serverURLKey = "com.mdone.shared.serverURL"
    static let widgetDataKey = "com.mdone.shared.widgetData"
    /// Calm Mode: when true, overdue tasks are shown without any special
    /// highlighting (no red, no separate "Overdue" grouping or counts).
    /// Mirrored from the app's `@AppStorage("calmMode")` so widgets can read it.
    static let calmModeKey = "com.mdone.shared.calmMode"

    static var sharedDefaults: UserDefaults {
        StorageScope.sharedDefaults
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
