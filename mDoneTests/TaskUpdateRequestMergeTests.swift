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
            hexColor: "e8283c",
            percentDone: 0.75,
            isFavorite: true
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

    /// The color and favorite flag are set from other Vikunja clients, but the
    /// server wipes them on partial updates just like the fields above, so every
    /// update must carry them too (verified against Vikunja v2.4.0: a bare
    /// `{done: true}` resets `hex_color` to "" and `is_favorite` to false).
    func testCompletingATaskCarriesColorAndFavorite() throws {
        let task = richTask()
        let body = try encodedBody(TaskUpdateRequest(done: true).preservingExistingValues(from: task))

        XCTAssertEqual(body["hex_color"] as? String, "e8283c")
        XCTAssertEqual(body["is_favorite"] as? Bool, true)
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

    func testExplicitColorAndFavoriteAreNotOverwrittenByTheSnapshot() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: true)
        request.hexColor = "00ff00"
        request.isFavorite = false
        let body = try encodedBody(request.preservingExistingValues(from: task))

        XCTAssertEqual(body["hex_color"] as? String, "00ff00")
        XCTAssertEqual(body["is_favorite"] as? Bool, false)
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
        XCTAssertNil(body["hex_color"])
        XCTAssertNil(body["is_favorite"])
    }

    // MARK: - What the task editors send

    /// The edit sheets compose their description through `EstimateMarker.apply`
    /// and must fall back to "" (an explicit clear), never nil: under
    /// `preservingExistingValues` a nil description means "keep the old text",
    /// which would silently undo the user deleting a description.
    func testEditorStyleClearedDescriptionReachesTheWire() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: false)
        // What TaskDetailSheet/MacTaskDetailView build for an emptied editor
        // with no estimate set.
        request.description = EstimateMarker.apply(nil, to: nil) ?? ""
        let body = try encodedBody(request.preservingExistingValues(from: task))

        XCTAssertEqual(body["description"] as? String, "")
    }

    /// The converse pin: removing the body but keeping an estimate must still
    /// send the marker-only description, not resurrect the old body.
    func testEditorStyleMarkerOnlyDescriptionReachesTheWire() throws {
        let task = richTask()
        var request = TaskUpdateRequest(done: false)
        request.description = EstimateMarker.apply(1500, to: nil) ?? ""
        let body = try encodedBody(request.preservingExistingValues(from: task))

        XCTAssertEqual(body["description"] as? String, "<!-- mdone:estimate=1500 -->")
    }
}
