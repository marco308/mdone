import XCTest
import SwiftUI
@testable import mDone

final class WidgetDataTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeSampleTask(
        id: Int64 = 1,
        title: String = "Buy groceries",
        done: Bool = false,
        dueDate: Date? = Date(),
        priority: Int = 3,
        projectId: Int64 = 10,
        projectTitle: String? = "Shopping",
        isOverdue: Bool = false
    ) -> WidgetTask {
        WidgetTask(
            id: id,
            title: title,
            done: done,
            dueDate: dueDate,
            priority: priority,
            projectId: projectId,
            projectTitle: projectTitle,
            isOverdue: isOverdue
        )
    }

    private func makeSampleWidgetData(
        todayTasks: [WidgetTask]? = nil,
        upcomingTasks: [WidgetTask]? = nil,
        overdueTasks: [WidgetTask]? = nil,
        lastUpdated: Date = Date()
    ) -> WidgetData {
        WidgetData(
            todayTasks: todayTasks ?? [makeSampleTask(id: 1, title: "Morning standup", priority: 2)],
            upcomingTasks: upcomingTasks ?? [makeSampleTask(id: 2, title: "Dentist appointment", priority: 1)],
            overdueTasks: overdueTasks ?? [makeSampleTask(id: 3, title: "Submit report", priority: 4, isOverdue: true)],
            lastUpdated: lastUpdated
        )
    }

    // MARK: - WidgetTask Priority Colors

    func testWidgetTaskPriorityColors() {
        let taskPriority0 = makeSampleTask(priority: 0)
        let taskPriority1 = makeSampleTask(priority: 1)
        let taskPriority2 = makeSampleTask(priority: 2)
        let taskPriority3 = makeSampleTask(priority: 3)
        let taskPriority4 = makeSampleTask(priority: 4)
        let taskPriority5 = makeSampleTask(priority: 5)
        let taskPriority99 = makeSampleTask(priority: 99)

        XCTAssertEqual(taskPriority0.priorityColor, .gray, "Priority 0 should be gray")
        XCTAssertEqual(taskPriority1.priorityColor, .blue, "Priority 1 should be blue")
        XCTAssertEqual(taskPriority2.priorityColor, .yellow, "Priority 2 should be yellow")
        XCTAssertEqual(taskPriority3.priorityColor, .orange, "Priority 3 should be orange")
        XCTAssertEqual(taskPriority4.priorityColor, .red, "Priority 4 should be red")
        XCTAssertEqual(taskPriority5.priorityColor, .purple, "Priority 5 should be purple")
        XCTAssertEqual(taskPriority99.priorityColor, .gray, "Unknown priority should default to gray")
    }

    // MARK: - WidgetTask Codable

    func testWidgetTaskCodable() throws {
        let dueDate = Date(timeIntervalSince1970: 1_710_500_000)
        let original = makeSampleTask(
            id: 42,
            title: "Write unit tests",
            done: false,
            dueDate: dueDate,
            priority: 4,
            projectId: 7,
            projectTitle: "Engineering",
            isOverdue: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WidgetTask.self, from: data)

        XCTAssertEqual(decoded.id, 42)
        XCTAssertEqual(decoded.title, "Write unit tests")
        XCTAssertFalse(decoded.done)
        XCTAssertEqual(decoded.dueDate?.timeIntervalSince1970 ?? 0, dueDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded.priority, 4)
        XCTAssertEqual(decoded.projectId, 7)
        XCTAssertEqual(decoded.projectTitle, "Engineering")
        XCTAssertTrue(decoded.isOverdue)
    }

    // MARK: - WidgetTask Identifiable

    func testWidgetTaskIdentifiable() {
        let task = makeSampleTask(id: 99)
        XCTAssertEqual(task.id, 99, "Identifiable id should match the task id")

        let taskA = makeSampleTask(id: 1)
        let taskB = makeSampleTask(id: 2)
        XCTAssertNotEqual(taskA.id, taskB.id, "Different tasks should have different ids")
    }

    // MARK: - WidgetTask with nil dueDate

    func testWidgetTaskWithNilDueDate() throws {
        let original = makeSampleTask(
            id: 5,
            title: "No deadline task",
            dueDate: nil,
            priority: 1
        )

        XCTAssertNil(original.dueDate)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WidgetTask.self, from: data)

        XCTAssertNil(decoded.dueDate, "Nil dueDate should round-trip as nil")
        XCTAssertEqual(decoded.id, 5)
        XCTAssertEqual(decoded.title, "No deadline task")
    }

    // MARK: - WidgetData Codable

    func testWidgetDataCodable() throws {
        let lastUpdated = Date(timeIntervalSince1970: 1_710_600_000)
        let todayTasks = [
            makeSampleTask(id: 10, title: "Code review", priority: 3),
            makeSampleTask(id: 11, title: "Team sync", priority: 2)
        ]
        let upcomingTasks = [
            makeSampleTask(id: 20, title: "Sprint planning", priority: 2)
        ]
        let overdueTasks = [
            makeSampleTask(id: 30, title: "File taxes", priority: 5, isOverdue: true)
        ]

        let original = WidgetData(
            todayTasks: todayTasks,
            upcomingTasks: upcomingTasks,
            overdueTasks: overdueTasks,
            lastUpdated: lastUpdated
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WidgetData.self, from: data)

        XCTAssertEqual(decoded.todayTasks.count, 2)
        XCTAssertEqual(decoded.todayTasks[0].title, "Code review")
        XCTAssertEqual(decoded.todayTasks[1].title, "Team sync")
        XCTAssertEqual(decoded.upcomingTasks.count, 1)
        XCTAssertEqual(decoded.upcomingTasks[0].title, "Sprint planning")
        XCTAssertEqual(decoded.overdueTasks.count, 1)
        XCTAssertEqual(decoded.overdueTasks[0].title, "File taxes")
        XCTAssertTrue(decoded.overdueTasks[0].isOverdue)
        XCTAssertEqual(decoded.lastUpdated.timeIntervalSince1970, lastUpdated.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - WidgetData Empty Arrays

    func testWidgetDataEmptyArrays() throws {
        let lastUpdated = Date(timeIntervalSince1970: 1_710_700_000)
        let original = WidgetData(
            todayTasks: [],
            upcomingTasks: [],
            overdueTasks: [],
            lastUpdated: lastUpdated
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WidgetData.self, from: data)

        XCTAssertTrue(decoded.todayTasks.isEmpty)
        XCTAssertTrue(decoded.upcomingTasks.isEmpty)
        XCTAssertTrue(decoded.overdueTasks.isEmpty)
        XCTAssertEqual(decoded.lastUpdated.timeIntervalSince1970, lastUpdated.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - WidgetData lastUpdated

    func testWidgetDataLastUpdated() throws {
        let specificDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = makeSampleWidgetData(lastUpdated: specificDate)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WidgetData.self, from: data)

        XCTAssertEqual(
            decoded.lastUpdated.timeIntervalSince1970,
            specificDate.timeIntervalSince1970,
            accuracy: 1.0,
            "lastUpdated should survive encoding/decoding round-trip"
        )
    }

    // MARK: - WidgetDataProvider isAuthenticated

    func testIsAuthenticatedFalseByDefault() {
        let provider = WidgetDataProvider()
        // A fresh provider with no credentials in shared defaults should not be authenticated
        // (Unless the real app has stored credentials, but the shared defaults for the App Group
        // are separate from the test host's defaults.)
        // We clear the keys to ensure a clean state.
        let defaults = SharedKeys.sharedDefaults
        let savedServerURL = defaults.string(forKey: SharedKeys.serverURLKey)
        let savedApiToken = defaults.string(forKey: SharedKeys.apiTokenKey)

        defaults.removeObject(forKey: SharedKeys.serverURLKey)
        defaults.removeObject(forKey: SharedKeys.apiTokenKey)

        addTeardownBlock {
            // Restore original values
            if let url = savedServerURL {
                defaults.set(url, forKey: SharedKeys.serverURLKey)
            }
            if let token = savedApiToken {
                defaults.set(token, forKey: SharedKeys.apiTokenKey)
            }
        }

        let freshProvider = WidgetDataProvider()
        XCTAssertFalse(freshProvider.isAuthenticated, "A provider with no stored credentials should not be authenticated")
    }

    // MARK: - WidgetDataProvider Cache and Retrieve

    func testCacheAndRetrieveWidgetData() throws {
        let defaults = SharedKeys.sharedDefaults
        let savedData = defaults.data(forKey: SharedKeys.widgetDataKey)

        addTeardownBlock {
            // Restore original cached data
            if let data = savedData {
                defaults.set(data, forKey: SharedKeys.widgetDataKey)
            } else {
                defaults.removeObject(forKey: SharedKeys.widgetDataKey)
            }
        }

        let lastUpdated = Date(timeIntervalSince1970: 1_710_800_000)
        let widgetData = WidgetData(
            todayTasks: [
                makeSampleTask(id: 100, title: "Deploy to staging", priority: 4, projectId: 5, projectTitle: "DevOps")
            ],
            upcomingTasks: [
                makeSampleTask(id: 101, title: "Quarterly review", priority: 2, projectId: 3, projectTitle: "HR")
            ],
            overdueTasks: [],
            lastUpdated: lastUpdated
        )

        let provider = WidgetDataProvider()
        provider.cacheWidgetData(widgetData)

        let retrieved = provider.cachedWidgetData()
        XCTAssertNotNil(retrieved, "cachedWidgetData should return data after caching")

        let cached = try XCTUnwrap(retrieved)
        XCTAssertEqual(cached.todayTasks.count, 1)
        XCTAssertEqual(cached.todayTasks[0].id, 100)
        XCTAssertEqual(cached.todayTasks[0].title, "Deploy to staging")
        XCTAssertEqual(cached.todayTasks[0].priority, 4)
        XCTAssertEqual(cached.todayTasks[0].projectId, 5)
        XCTAssertEqual(cached.todayTasks[0].projectTitle, "DevOps")
        XCTAssertEqual(cached.upcomingTasks.count, 1)
        XCTAssertEqual(cached.upcomingTasks[0].title, "Quarterly review")
        XCTAssertTrue(cached.overdueTasks.isEmpty)
        XCTAssertEqual(cached.lastUpdated.timeIntervalSince1970, lastUpdated.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - WidgetDataProvider Cached Returns Nil When Empty

    func testCachedWidgetDataReturnsNilWhenEmpty() {
        let defaults = SharedKeys.sharedDefaults
        let savedData = defaults.data(forKey: SharedKeys.widgetDataKey)

        addTeardownBlock {
            if let data = savedData {
                defaults.set(data, forKey: SharedKeys.widgetDataKey)
            } else {
                defaults.removeObject(forKey: SharedKeys.widgetDataKey)
            }
        }

        defaults.removeObject(forKey: SharedKeys.widgetDataKey)

        let provider = WidgetDataProvider()
        XCTAssertNil(provider.cachedWidgetData(), "cachedWidgetData should return nil when nothing is cached")
    }

    // MARK: - SharedKeys Constants

    func testSharedKeysConstants() {
        let keys = [
            SharedKeys.appGroupID,
            SharedKeys.apiTokenKey,
            SharedKeys.serverURLKey,
            SharedKeys.widgetDataKey
        ]

        // All keys should be non-empty
        for key in keys {
            XCTAssertFalse(key.isEmpty, "SharedKeys constant should not be empty: got '\(key)'")
        }

        // All keys should be unique
        let uniqueKeys = Set(keys)
        XCTAssertEqual(uniqueKeys.count, keys.count, "All SharedKeys constants should be unique")
    }

    // MARK: - SharedKeys sharedDefaults

    func testSharedDefaultsNotNil() {
        let defaults = SharedKeys.sharedDefaults
        // UserDefaults(suiteName:) can return nil, but SharedKeys falls back to .standard
        // Either way, the computed property should never return nil
        XCTAssertNotNil(defaults, "sharedDefaults should return a valid UserDefaults instance")

        // Verify it's usable by writing and reading a test value
        let testKey = "com.mdone.test.tempKey.\(UUID().uuidString)"
        defaults.set("testValue", forKey: testKey)
        XCTAssertEqual(defaults.string(forKey: testKey), "testValue")

        // Clean up
        defaults.removeObject(forKey: testKey)
    }
}
