import Foundation
import SwiftData

struct AppDependencies {
    let modelContainer: ModelContainer
    let networkMonitor: NetworkMonitor

    init() {
        let schema = Schema([
            CachedTask.self,
            CachedProject.self,
            CachedLabel.self,
            PendingOperation.self,
        ])

        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        networkMonitor = NetworkMonitor()
    }
}
