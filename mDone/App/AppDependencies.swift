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
            FocusRecord.self,
        ])

        // Ensure App Group directory exists for SwiftData
        var storeURL: URL?
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mdone.app") {
            let supportURL = appGroupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            storeURL = supportURL.appendingPathComponent("default.store")
        }

        let config: ModelConfiguration
        if let url = storeURL {
            config = ModelConfiguration(schema: schema, url: url)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        networkMonitor = NetworkMonitor()
    }
}
