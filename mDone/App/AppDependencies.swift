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
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ncastillo.mdone.app") {
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
            print("Failed to create ModelContainer, attempting to delete old store: \(error)")
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-shm"))
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("store-wal"))
            
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer after deleting store: \(error)")
            }
        }

        networkMonitor = NetworkMonitor()
    }
}
