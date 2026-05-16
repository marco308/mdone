import SwiftData
import XCTest
@testable import mDone

@MainActor
final class EstimateStoreTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let schema = Schema([TaskEstimate.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - get / optionality

    func testUnknownTaskIdReturnsNil() {
        XCTAssertNil(EstimateStore.estimate(for: 999, in: context))
    }

    func testSetThenGet() {
        EstimateStore.set(1800, for: 42, in: context)
        XCTAssertEqual(EstimateStore.estimate(for: 42, in: context), 1800)
    }

    func testEstimateIsScopedToTaskId() {
        EstimateStore.set(1800, for: 42, in: context)
        XCTAssertNil(EstimateStore.estimate(for: 43, in: context))
    }

    // MARK: - set replaces (one row per task)

    func testSetReplacesExistingValueWithoutDuplicating() throws {
        EstimateStore.set(600, for: 7, in: context)
        EstimateStore.set(1200, for: 7, in: context)

        XCTAssertEqual(EstimateStore.estimate(for: 7, in: context), 1200)
        let all = try context.fetch(FetchDescriptor<TaskEstimate>())
        XCTAssertEqual(all.count, 1, "Setting twice must update in place, not insert a second row")
    }

    // MARK: - clear

    func testClearRemovesEstimate() {
        EstimateStore.set(900, for: 5, in: context)
        EstimateStore.clear(for: 5, in: context)
        XCTAssertNil(EstimateStore.estimate(for: 5, in: context))
    }

    func testClearUnknownTaskIdIsNoOp() throws {
        EstimateStore.clear(for: 12345, in: context)
        let all = try context.fetch(FetchDescriptor<TaskEstimate>())
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - non-positive value clears rather than persisting junk

    func testSetZeroClearsInsteadOfPersisting() {
        EstimateStore.set(1800, for: 9, in: context)
        EstimateStore.set(0, for: 9, in: context)
        XCTAssertNil(EstimateStore.estimate(for: 9, in: context))
    }

    func testSetNegativeClears() {
        EstimateStore.set(1800, for: 9, in: context)
        EstimateStore.set(-50, for: 9, in: context)
        XCTAssertNil(EstimateStore.estimate(for: 9, in: context))
    }

    func testSetZeroOnUnknownIdInsertsNothing() throws {
        EstimateStore.set(0, for: 100, in: context)
        let all = try context.fetch(FetchDescriptor<TaskEstimate>())
        XCTAssertTrue(all.isEmpty)
    }
}
