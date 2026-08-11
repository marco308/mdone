import XCTest
@testable import mDone

/// Issue #147: Vikunja's `POST /tasks/{id}` is a full replace, so any field left
/// out of the body is reset to its zero value. These tests assert on the encoded
/// wire body rather than the struct, because it's the omission that causes the
/// data loss, not the property being nil.
final class TaskUpdateRequestMergeTests: XCTestCase {
    private func encodedBody(_ request: TaskUpdateRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func richTask() -> VTask {
        VTask(
            id: 1,
            title: "Write quarterly report",
            description: "Focus on Q1 wins",
            done: false,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            priority: 5,
            projectId: 3,
            percentDone: 0.75
        )
    }

    // MARK: - The reported bug

    /// Ticking a task off sent `{done: true}` plus the schedule fields, which
    /// wiped the task's description, priority and progress server-side.
    func testCompletingATaskCarriesDescriptionPriorityAndProgress() throws {
        let task = richTask()
        let request = TaskUpdateRequest(done: true).preservingExistingValues(from: task)
        let body = try encodedBody(request)

        XCTAssertEqual(body["done"] as? Bool, true)
        XCTAssertEqual(body["description"] as? String, "Focus on Q1 wins")
        XCTAssertEqual(body["priority"] as? Int, 5)
        XCTAssertEqual(body["percent_done"] as? Double, 0.75)
    }

    func testReschedulingCarriesDescriptionPriorityAndProgress() throws {
        let task = richTask()
        let newDate = Date(timeIntervalSince1970: 1_900_000_000)
        let request = TaskUpdateRequest(dueDate: newDate).preservingExistingValues(from: task)
        let body = try encodedBody(request)

        XCTAssertNotNil(body["due_date"])
        XCTAssertEqual(body["description"] as? String, "Focus on Q1 wins")
        XCTAssertEqual(body["priority"] as? Int, 5)
        XCTAssertEqual(body["percent_done"] as? Double, 0.75)
    }

    /// `setProgress` was the sharpest case: it sets the progress of a task whose
    /// progress bar is the point of the Current section, and wiped that task's
    /// priority and description doing it.
    func testSettingProgressCarriesDescriptionAndPriority() throws {
        let task = richTask()
        let request = TaskUpdateRequest(percentDone: 0.25).preservingExistingValues(from: task)
        let body = try encodedBody(request)

        XCTAssertEqual(body["percent_done"] as? Double, 0.25)
        XCTAssertEqual(body["description"] as? String, "Focus on Q1 wins")
        XCTAssertEqual(body["priority"] as? Int, 5)
    }

    // MARK: - The caller's own values still win

    func testExplicitValuesAreNotOverwrittenByTheSnapshot() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: true)
        request.description = "Rewritten"
        request.priority = 1
        request.percentDone = 0.1
        let body = try encodedBody(request.preservingExistingValues(from: task))

        XCTAssertEqual(body["description"] as? String, "Rewritten")
        XCTAssertEqual(body["priority"] as? Int, 1)
        XCTAssertEqual(body["percent_done"] as? Double, 0.1)
    }

    /// Clearing a description to empty is a real edit, not "unset", so it must
    /// not be replaced by the old text.
    func testClearingDescriptionToEmptyIsPreserved() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: false)
        request.description = ""
        let body = try encodedBody(request.preservingExistingValues(from: task))

        XCTAssertEqual(body["description"] as? String, "")
    }

    /// Priority zero means "none" and is a legitimate value to send.
    func testExplicitZeroPriorityIsPreserved() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: false)
        request.priority = 0
        let body = try encodedBody(request.preservingExistingValues(from: task))

        XCTAssertEqual(body["priority"] as? Int, 0)
    }

    // MARK: - Fields the server keeps on its own

    /// The server preserves these when they're omitted, so we deliberately don't
    /// send our local snapshot back and risk clobbering an edit made elsewhere.
    func testTitleProjectAndLabelsAreNotCarried() throws {
        let task = richTask()
        let body = try encodedBody(TaskUpdateRequest(done: true).preservingExistingValues(from: task))

        XCTAssertNil(body["title"])
        XCTAssertNil(body["project_id"])
        XCTAssertNil(body["labels"])
    }

    // MARK: - Existing schedule behaviour still holds

    func testScheduleFieldsAreStillCarried() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_086_400)
        let task = VTask(
            id: 1,
            title: "Ranged",
            done: false,
            dueDate: end,
            startDate: start,
            endDate: end,
            priority: 2,
            projectId: 1
        )
        let body = try encodedBody(TaskUpdateRequest(done: true).preservingExistingValues(from: task))

        XCTAssertNotNil(body["due_date"])
        XCTAssertNotNil(body["start_date"])
        XCTAssertNotNil(body["end_date"])
    }

    func testClearFlagsStillWinOverCarriedValues() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: true)
        request.clearDueDate = true
        let body = try encodedBody(request.preservingExistingValues(from: task))

        // Vikunja's zero-date sentinel, i.e. explicitly cleared rather than kept.
        XCTAssertEqual(body["due_date"] as? String, "0001-01-01T00:00:00Z")
    }

    // MARK: - Tasks with nothing to carry

    /// A bare task has no description or progress to preserve; carrying "nothing"
    /// must not invent values or crash.
    func testMinimalTaskCarriesOnlyWhatItHas() throws {
        let task = VTask(id: 1, title: "Bare", done: false, priority: 0, projectId: 1)
        let body = try encodedBody(TaskUpdateRequest(done: true).preservingExistingValues(from: task))

        XCTAssertEqual(body["priority"] as? Int, 0)
        XCTAssertNil(body["description"])
        XCTAssertNil(body["percent_done"])
    }
}
