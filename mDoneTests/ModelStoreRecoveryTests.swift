import Foundation
import SwiftData
import XCTest
@testable import mDone

/// Covers issue #155: a store that will not open used to `fatalError` on every
/// launch, and the only user-side fix (reinstalling) silently destroyed the
/// queue of edits made offline.
final class ModelStoreRecoveryTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("default.store")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    private func makeStore(pendingOperations: Int = 0, focusRecords: Int = 0) throws {
        let schema = ModelStoreBootstrap.schema
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        let context = ModelContext(container)

        for index in 0 ..< pendingOperations {
            let operation = PendingOperation(
                endpointPath: "/tasks/\(index)",
                method: "POST",
                bodyData: Data("edit-\(index)".utf8),
                kind: .taskEdit,
                taskId: Int64(index)
            )
            operation.retryCount = index
            context.insert(operation)
        }

        for index in 0 ..< focusRecords {
            context.insert(FocusRecord(
                taskId: Int64(index),
                taskTitle: "Focus \(index)",
                projectName: "Inbox",
                priorityLevel: 3,
                startedAt: Date(timeIntervalSince1970: 1000 + Double(index)),
                endedAt: Date(timeIntervalSince1970: 2000 + Double(index)),
                focusedSeconds: 1500,
                device: "iPhone"
            ))
        }

        try context.save()
    }

    private func corruptStore() throws {
        try Data(repeating: 0xAB, count: 4096).write(to: storeURL)
    }

    private func counts(in container: ModelContainer) throws -> (operations: Int, records: Int) {
        let context = ModelContext(container)
        return try (
            context.fetchCount(FetchDescriptor<PendingOperation>()),
            context.fetchCount(FetchDescriptor<FocusRecord>())
        )
    }

    // MARK: - Healthy store

    func testHealthyStoreOpensUntouched() throws {
        try makeStore(pendingOperations: 2, focusRecords: 1)

        let outcome = ModelStoreBootstrap.makeContainer(at: storeURL)

        XCTAssertEqual(outcome.recovery, StoreRecovery.none)
        let counts = try counts(in: outcome.container)
        XCTAssertEqual(counts.operations, 2)
        XCTAssertEqual(counts.records, 1)
    }

    // MARK: - Corrupted store

    func testCorruptedStoreStillLaunches() throws {
        try corruptStore()

        let outcome = ModelStoreBootstrap.makeContainer(at: storeURL)

        // The point of the fix: a container comes back rather than a crash.
        XCTAssertEqual(outcome.recovery, .cacheRebuilt(pendingOperations: 0, focusRecords: 0))
        let counts = try counts(in: outcome.container)
        XCTAssertEqual(counts.operations, 0)
        XCTAssertEqual(counts.records, 0)
    }

    func testCorruptedStoreIsQuarantinedNotDeleted() throws {
        try corruptStore()

        _ = ModelStoreBootstrap.makeContainer(at: storeURL)

        let quarantined = URL(fileURLWithPath: storeURL.path + ".quarantined")
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantined.path))
        XCTAssertEqual(try Data(contentsOf: quarantined), Data(repeating: 0xAB, count: 4096))
    }

    func testSalvageReturnsNothingForAnUnreadableStore() throws {
        try corruptStore()

        XCTAssertTrue(ModelStoreBootstrap.salvage(at: storeURL).isEmpty)
    }

    func testSalvageReturnsNothingWhenThereIsNoStore() {
        XCTAssertTrue(ModelStoreBootstrap.salvage(at: storeURL).isEmpty)
    }

    // MARK: - Salvaging offline work

    func testSalvageReadsPendingOperationsAndFocusRecords() throws {
        try makeStore(pendingOperations: 3, focusRecords: 2)

        let salvaged = ModelStoreBootstrap.salvage(at: storeURL)

        XCTAssertEqual(salvaged.pendingOperations.count, 3)
        XCTAssertEqual(salvaged.focusRecords.count, 2)
        let paths = Set(salvaged.pendingOperations.map(\.endpointPath))
        XCTAssertEqual(paths, ["/tasks/0", "/tasks/1", "/tasks/2"])
    }

    /// The real regression: a rebuilt store has to come back with the offline
    /// edit queue intact, including the fields the queue replays on.
    func testRebuildRestoresPendingOperationsIntact() throws {
        try makeStore(pendingOperations: 2, focusRecords: 1)
        let salvaged = ModelStoreBootstrap.salvage(at: storeURL)
        try FileManager.default.removeItem(at: storeURL)

        let outcome = ModelStoreBootstrap.makeContainer(at: storeURL)
        XCTAssertTrue(ModelStoreBootstrap.restore(salvaged, into: outcome.container))

        let context = ModelContext(outcome.container)
        let restored = try context.fetch(FetchDescriptor<PendingOperation>())
            .sorted { $0.endpointPath < $1.endpointPath }
        XCTAssertEqual(restored.count, 2)

        let expected = salvaged.pendingOperations.sorted { $0.endpointPath < $1.endpointPath }
        for (operation, snapshot) in zip(restored, expected) {
            XCTAssertEqual(operation.id, snapshot.id)
            XCTAssertEqual(operation.endpointPath, snapshot.endpointPath)
            XCTAssertEqual(operation.method, snapshot.method)
            XCTAssertEqual(operation.bodyData, snapshot.bodyData)
            XCTAssertEqual(operation.timestamp, snapshot.timestamp)
            XCTAssertEqual(operation.retryCount, snapshot.retryCount)
            XCTAssertEqual(operation.failed, snapshot.failed)
            XCTAssertEqual(operation.kind, snapshot.kind)
            XCTAssertEqual(operation.taskId, snapshot.taskId)
        }

        let records = try context.fetch(FetchDescriptor<FocusRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.deliveredAt, "an undelivered record must stay undelivered so the outbox retries it")
    }

    func testRestoreIsANoOpForEmptySalvage() throws {
        let outcome = ModelStoreBootstrap.makeContainer(at: storeURL)

        XCTAssertTrue(ModelStoreBootstrap.restore(ModelStoreBootstrap.SalvagedWork(), into: outcome.container))
        let counts = try counts(in: outcome.container)
        XCTAssertEqual(counts.operations, 0)
        XCTAssertEqual(counts.records, 0)
    }

    // MARK: - Schema mismatch

    /// A migration the store cannot perform is the other way this fails in the
    /// wild. The store here holds only the local-only entities, so opening it
    /// with the full schema has to add the cache entities.
    func testStoreWrittenWithAnOlderSchemaKeepsPendingWork() throws {
        let oldSchema = Schema([PendingOperation.self, FocusRecord.self])
        let container = try ModelContainer(
            for: oldSchema,
            configurations: [ModelConfiguration(schema: oldSchema, url: storeURL)]
        )
        let context = ModelContext(container)
        context.insert(PendingOperation(endpointPath: "/tasks/7", method: "POST", kind: .taskEdit, taskId: 7))
        try context.save()

        let outcome = ModelStoreBootstrap.makeContainer(at: storeURL)

        // Whether SwiftData migrates this in place or the recovery path rebuilds
        // it, the queued edit has to still be there afterwards.
        let restored = try ModelContext(outcome.container).fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.taskId, 7)
    }

    // MARK: - Messages

    func testNoRecoveryHasNoMessage() {
        XCTAssertNil(StoreRecovery.none.userMessage)
    }

    func testRebuiltMessageMentionsRecoveredWork() throws {
        let message = try XCTUnwrap(StoreRecovery.cacheRebuilt(pendingOperations: 2, focusRecords: 1).userMessage)

        // Exercises the per-argument plural substitutions in the string catalog.
        XCTAssertTrue(message.hasSuffix("2 unsynced changes and 1 focus session were recovered."), message)
        XCTAssertFalse(message.contains("\u{2014}"), "repo style: no em-dashes in user-facing copy")
    }

    func testRecoveredSentenceUsesSingularForOneItem() throws {
        let changes = try XCTUnwrap(StoreRecovery.cacheRebuilt(pendingOperations: 1, focusRecords: 0).userMessage)
        XCTAssertTrue(changes.hasSuffix("1 unsynced change was recovered."), changes)

        let sessions = try XCTUnwrap(StoreRecovery.cacheRebuilt(pendingOperations: 0, focusRecords: 3).userMessage)
        XCTAssertTrue(sessions.hasSuffix("3 focus sessions were recovered."), sessions)
    }

    func testRebuiltMessageOmitsCountsWhenNothingWasRecovered() throws {
        let message = try XCTUnwrap(StoreRecovery.cacheRebuilt(pendingOperations: 0, focusRecords: 0).userMessage)

        XCTAssertFalse(message.contains("recovered"))
    }

    func testInMemoryMessageWarnsChangesWillNotPersist() throws {
        let message = try XCTUnwrap(StoreRecovery.inMemory(pendingOperations: 0, focusRecords: 0).userMessage)

        XCTAssertTrue(message.lowercased().contains("lost"))
    }
}

extension ModelStoreRecoveryTests {
    /// The case the fix exists for: the store cannot be opened with the current
    /// schema, but the offline edit queue inside it is still readable and has to
    /// come back.
    func testSchemaMismatchRebuildsCacheAndKeepsPendingWork() throws {
        let legacySchema = Schema([LegacyStore.CachedTask.self, PendingOperation.self, FocusRecord.self])
        let legacy = try ModelContainer(
            for: legacySchema,
            configurations: [ModelConfiguration(schema: legacySchema, url: storeURL)]
        )
        let seeding = ModelContext(legacy)
        seeding.insert(LegacyStore.CachedTask(id: 1, title: 99))
        let queued = PendingOperation(
            endpointPath: "/tasks/42",
            method: "POST",
            bodyData: Data("offline edit".utf8),
            kind: .taskEdit,
            taskId: 42
        )
        seeding.insert(queued)
        seeding.insert(FocusRecord(
            taskId: 42,
            taskTitle: "Write the fix",
            projectName: "mDone",
            priorityLevel: 3,
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 2500),
            focusedSeconds: 1500,
            device: "iPhone"
        ))
        try seeding.save()

        let outcome = ModelStoreBootstrap.makeContainer(at: storeURL)

        XCTAssertEqual(outcome.recovery, .cacheRebuilt(pendingOperations: 1, focusRecords: 1))

        let context = ModelContext(outcome.container)
        let operations = try context.fetch(FetchDescriptor<PendingOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.id, queued.id)
        XCTAssertEqual(operations.first?.taskId, 42)
        XCTAssertEqual(operations.first?.bodyData, Data("offline edit".utf8))
        XCTAssertEqual(operations.first?.operationKind, .taskEdit)

        let records = try context.fetch(FetchDescriptor<FocusRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.deliveredAt)

        // The cache is the part that is safe to lose: it reloads from the server.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTask>()), 0)
    }
}
