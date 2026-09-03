import Foundation
import SwiftData

struct AppDependencies {
    let modelContainer: ModelContainer
    let networkMonitor: NetworkMonitor

    /// Whether the store had to be rebuilt at launch, so the UI can say so
    /// rather than the app quietly coming back empty (issue #155).
    let storeRecovery: StoreRecovery

    /// True when the app has been launched only to host the unit-test bundle.
    ///
    /// `XCTestConfigurationFilePath` is set in the host process for a unit-test
    /// run and not for a UI-test run, where the app is launched normally by a
    /// separate runner, so this leaves `mDoneUITests` on the real launch path.
    static let isHostingUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        // Hosting the unit tests means doing none of this. They build their own
        // containers, services and sessions, so the production launch buys them
        // nothing and costs them an on-disk SwiftData store that carries state
        // between runs, plus a started `NWPathMonitor` whose path updates drive
        // `refreshAll()` for the whole bundle. On a machine with a dev server
        // configured, those refreshes print connection failures and their retry
        // backoff into whichever test happens to be running at the time, which
        // is exactly the misattributed noise this was traced through once.
        if AppDependencies.isHostingUnitTests {
            modelContainer = ModelStoreBootstrap.makeInMemoryContainer()
            storeRecovery = .none
            networkMonitor = NetworkMonitor(stubbedConnection: false)
            return
        }

        // A store that fails to open used to be a `fatalError`, which crashed
        // the app on every launch and left reinstalling as the only fix. That
        // threw away the offline edit queue with it, so recover instead.
        let outcome = ModelStoreBootstrap.makeContainer()
        modelContainer = outcome.container
        storeRecovery = outcome.recovery

        networkMonitor = NetworkMonitor()
    }
}
