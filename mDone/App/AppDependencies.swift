import Foundation
import SwiftData

struct AppDependencies {
    let modelContainer: ModelContainer
    let networkMonitor: NetworkMonitor

    /// Whether the store had to be rebuilt at launch, so the UI can say so
    /// rather than the app quietly coming back empty (issue #155).
    let storeRecovery: StoreRecovery

    init() {
        // A store that fails to open used to be a `fatalError`, which crashed
        // the app on every launch and left reinstalling as the only fix. That
        // threw away the offline edit queue with it, so recover instead.
        let outcome = ModelStoreBootstrap.makeContainer()
        modelContainer = outcome.container
        storeRecovery = outcome.recovery

        networkMonitor = NetworkMonitor()
    }
}
