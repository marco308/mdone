import Foundation
import SwiftData

/// Why the app is running on a rebuilt or temporary store, so the launch can
/// tell the user instead of recovering silently (issue #155).
enum StoreRecovery: Equatable {
    /// The store opened normally.
    case none

    /// The store could not be opened, so the re-fetchable cache was rebuilt.
    /// The counts are the local-only work that was carried across.
    case cacheRebuilt(pendingOperations: Int, focusRecords: Int)

    /// No store could be opened at all, so this session runs in memory and
    /// nothing written during it survives a relaunch.
    case inMemory(pendingOperations: Int, focusRecords: Int)

    /// Alert body for this outcome, or nil when there is nothing to say.
    var userMessage: String? {
        switch self {
        case .none:
            return nil
        case let .cacheRebuilt(pendingOperations, focusRecords):
            var message = String(
                localized: "mDone could not open its offline database, so the cached copy of your tasks was rebuilt. Everything reloads from the server."
            )
            if let carried = Self
                .carriedOverSentence(pendingOperations: pendingOperations, focusRecords: focusRecords)
            {
                message += "\n\n\(carried)"
            }
            return message
        case let .inMemory(pendingOperations, focusRecords):
            var message = String(
                localized: "mDone could not open or recreate its offline database, so it is running without one. Your tasks still load from the server, but anything you change offline will be lost when you quit the app."
            )
            if let carried = Self
                .carriedOverSentence(pendingOperations: pendingOperations, focusRecords: focusRecords)
            {
                message += "\n\n\(carried) " + String(localized: "They will be lost if you quit before they are sent.")
            }
            return message
        }
    }

    /// One whole key per combination rather than fragments joined with "and",
    /// so a translator controls the word order. The plural forms live in the
    /// catalog; the two-count key carries one plural variation per argument.
    private static func carriedOverSentence(pendingOperations: Int, focusRecords: Int) -> String? {
        switch (pendingOperations > 0, focusRecords > 0) {
        case (false, false):
            return nil
        case (true, false):
            return String(localized: "\(pendingOperations) unsynced changes were recovered.")
        case (false, true):
            return String(localized: "\(focusRecords) focus sessions were recovered.")
        case (true, true):
            return String(
                localized: "\(pendingOperations) unsynced changes and \(focusRecords) focus sessions were recovered."
            )
        }
    }
}

/// Opens the SwiftData store, and recovers rather than crashing when it cannot.
///
/// The store holds two very different kinds of row. `CachedTask`, `CachedProject`
/// and `CachedLabel` are copies of server state and cost nothing to rebuild.
/// `PendingOperation` and `FocusRecord` are local-only: the first is the queue of
/// edits made offline that have not reached Vikunja yet, the second is focus
/// history that exists nowhere else. So a failed open salvages the local-only
/// rows first, and only then rebuilds the store around them (issue #155).
enum ModelStoreBootstrap {
    struct Outcome {
        let container: ModelContainer
        let recovery: StoreRecovery
    }

    static var schema: Schema {
        Schema([
            CachedTask.self,
            CachedProject.self,
            CachedLabel.self,
            PendingOperation.self,
            FocusRecord.self,
        ])
    }

    /// The local-only entities, opened on their own when the full schema fails.
    /// A schema mismatch or corruption usually only affects some entities, so
    /// this often succeeds where the full open did not.
    private static var salvageSchema: Schema {
        Schema([PendingOperation.self, FocusRecord.self])
    }

    static func makeContainer() -> Outcome {
        makeContainer(at: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url)
    }

    /// A store that touches no disk, for the last-resort recovery below and for
    /// the launch that only exists to host the unit tests.
    static func makeInMemoryContainer() -> ModelContainer {
        let schema = schema
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            // An in-memory container can only fail on a malformed schema, which
            // is a programming error rather than anything the user can recover
            // from.
            fatalError("Failed to create an in-memory ModelContainer")
        }
        return container
    }

    static func makeContainer(at url: URL) -> Outcome {
        let schema = schema

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            return Outcome(container: container, recovery: .none)
        } catch {
            #if DEBUG
            print("[store] failed to open \(url.lastPathComponent): \(error)")
            #endif
        }

        let salvaged = salvage(at: url)
        #if DEBUG
        print(
            "[store] salvaged \(salvaged.pendingOperations.count) pending operations, \(salvaged.focusRecords.count) focus records"
        )
        #endif

        // Move the unreadable store aside rather than deleting it. If the open
        // failed for an environmental reason (no disk space, data still
        // protected before first unlock) the rows are still on disk, and the
        // quarantine is undone below so the next launch finds them again.
        let quarantined = quarantine(at: url)

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            restore(salvaged, into: container)
            return Outcome(
                container: container,
                recovery: .cacheRebuilt(
                    pendingOperations: salvaged.pendingOperations.count,
                    focusRecords: salvaged.focusRecords.count
                )
            )
        } catch {
            #if DEBUG
            print("[store] failed to recreate \(url.lastPathComponent): \(error)")
            #endif
        }

        if quarantined {
            unquarantine(at: url)
        }

        // Last resort: launch on a throwaway store so the app still opens. The
        // salvaged work rides along so a reconnect during this session can still
        // flush it.
        let container = makeInMemoryContainer()
        restore(salvaged, into: container)
        return Outcome(
            container: container,
            recovery: .inMemory(
                pendingOperations: salvaged.pendingOperations.count,
                focusRecords: salvaged.focusRecords.count
            )
        )
    }

    // MARK: - Salvage

    struct SalvagedWork: Equatable {
        var pendingOperations: [PendingOperationSnapshot] = []
        var focusRecords: [FocusRecordSnapshot] = []

        var isEmpty: Bool {
            pendingOperations.isEmpty && focusRecords.isEmpty
        }
    }

    struct PendingOperationSnapshot: Equatable {
        var id: UUID
        var endpointPath: String
        var method: String
        var bodyData: Data?
        var timestamp: Date
        var retryCount: Int
        var failed: Bool
        var kind: String?
        var taskId: Int64?
        var failureReason: String?
    }

    struct FocusRecordSnapshot: Equatable {
        var taskId: Int64
        var taskTitle: String
        var projectName: String
        var priorityLevel: Int
        var startedAt: Date
        var endedAt: Date
        var focusedSeconds: Double
        var device: String
        var clientId: String?
        var deliveredAt: Date?
        var discardedAt: Date?
    }

    /// Reads the local-only rows out of a store that the full schema rejected.
    /// Everything is copied into value types so nothing keeps the failing store
    /// alive once this returns.
    static func salvage(at url: URL) -> SalvagedWork {
        guard FileManager.default.fileExists(atPath: url.path) else { return SalvagedWork() }

        let schema = salvageSchema
        guard let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ) else {
            #if DEBUG
            print("[store] nothing could be salvaged from \(url.lastPathComponent)")
            #endif
            return SalvagedWork()
        }

        let context = ModelContext(container)
        let operations = (try? context.fetch(FetchDescriptor<PendingOperation>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<FocusRecord>())) ?? []

        return SalvagedWork(
            pendingOperations: operations.map {
                PendingOperationSnapshot(
                    id: $0.id,
                    endpointPath: $0.endpointPath,
                    method: $0.method,
                    bodyData: $0.bodyData,
                    timestamp: $0.timestamp,
                    retryCount: $0.retryCount,
                    failed: $0.failed,
                    kind: $0.kind,
                    taskId: $0.taskId,
                    failureReason: $0.failureReason
                )
            },
            focusRecords: records.map {
                FocusRecordSnapshot(
                    taskId: $0.taskId,
                    taskTitle: $0.taskTitle,
                    projectName: $0.projectName,
                    priorityLevel: $0.priorityLevel,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    focusedSeconds: $0.focusedSeconds,
                    device: $0.device,
                    clientId: $0.clientId,
                    deliveredAt: $0.deliveredAt,
                    discardedAt: $0.discardedAt
                )
            }
        )
    }

    /// Writes salvaged rows back into a freshly opened store.
    @discardableResult
    static func restore(_ salvaged: SalvagedWork, into container: ModelContainer) -> Bool {
        guard !salvaged.isEmpty else { return true }

        let context = ModelContext(container)

        for snapshot in salvaged.pendingOperations {
            let operation = PendingOperation(
                endpointPath: snapshot.endpointPath,
                method: snapshot.method,
                bodyData: snapshot.bodyData,
                kind: snapshot.kind.flatMap(PendingOperation.Kind.init(rawValue:)),
                taskId: snapshot.taskId
            )
            // The initialiser stamps a fresh id and timestamp; the queue replays
            // in timestamp order and coalesces by id, so both have to survive.
            operation.id = snapshot.id
            operation.timestamp = snapshot.timestamp
            operation.retryCount = snapshot.retryCount
            operation.failed = snapshot.failed
            operation.failureReason = snapshot.failureReason
            context.insert(operation)
        }

        for snapshot in salvaged.focusRecords {
            context.insert(FocusRecord(
                taskId: snapshot.taskId,
                taskTitle: snapshot.taskTitle,
                projectName: snapshot.projectName,
                priorityLevel: snapshot.priorityLevel,
                startedAt: snapshot.startedAt,
                endedAt: snapshot.endedAt,
                focusedSeconds: snapshot.focusedSeconds,
                device: snapshot.device,
                clientId: snapshot.clientId,
                deliveredAt: snapshot.deliveredAt,
                discardedAt: snapshot.discardedAt
            ))
        }

        do {
            try context.save()
            return true
        } catch {
            #if DEBUG
            print("[store] failed to restore salvaged work: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Store files

    /// SQLite keeps its write-ahead log and shared memory alongside the store,
    /// and all three have to move together.
    private static func storeFiles(for url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    private static func quarantineURL(for url: URL) -> URL {
        URL(fileURLWithPath: url.path + ".quarantined")
    }

    /// Moves the unreadable store to a single fixed backup location, replacing
    /// any earlier backup so these cannot pile up.
    @discardableResult
    private static func quarantine(at url: URL) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return false }

        var moved = false
        for file in storeFiles(for: url) {
            let destination = quarantineURL(for: file)
            try? manager.removeItem(at: destination)
            guard manager.fileExists(atPath: file.path) else { continue }
            do {
                try manager.moveItem(at: file, to: destination)
                moved = true
            } catch {
                #if DEBUG
                print("[store] could not quarantine \(file.lastPathComponent): \(error)")
                #endif
                try? manager.removeItem(at: file)
            }
        }
        return moved
    }

    /// Puts a quarantined store back, for when recreating the store failed too.
    /// The failure was environmental rather than the store's fault, so the next
    /// launch should get the original rows.
    private static func unquarantine(at url: URL) {
        let manager = FileManager.default
        for file in storeFiles(for: url) {
            let source = quarantineURL(for: file)
            guard manager.fileExists(atPath: source.path) else { continue }
            try? manager.removeItem(at: file)
            try? manager.moveItem(at: source, to: file)
        }
    }
}
