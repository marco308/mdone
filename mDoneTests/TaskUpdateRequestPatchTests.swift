import XCTest
@testable import mDone

/// Task updates are a JSON Merge Patch (#292): the server changes only the
/// fields in the body, so the body must hold only what the user changed.
/// These assert on the encoded wire body, because what is left out is what
/// protects the task.
final class TaskUpdateRequestPatchTests: XCTestCase {
    private func encodedBody(_ request: TaskUpdateRequest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let alice = User(id: 3, username: "alice", name: "Alice Smith")

    private func richTask() -> VTask {
        var task = VTask(
            id: 1,
            title: "Water plants",
            description: "Back garden",
            done: false,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            priority: 3,
            projectId: 3,
            hexColor: "e8283c",
            percentDone: 0.5,
            isFavorite: true
        )
        task.repeatAfter = 86400
        task.repeatMode = 0
        task.assignees = [alice]
        task.reminders = [TaskReminder(reminder: nil, relativePeriod: -3600, relativeTo: "due_date")]
        return task
    }

    /// What the task editor sends on Save: every field it shows.
    private func editorSave(of task: VTask) -> TaskUpdateRequest {
        TaskUpdateRequest(
            title: task.title,
            description: task.description ?? "",
            dueDate: task.effectiveDueDate,
            startDate: task.effectiveStartDate,
            endDate: task.effectiveEndDate,
            priority: task.priority,
            projectId: task.projectId,
            repeatAfter: task.repeatAfter ?? 0,
            repeatMode: task.repeatModeForEditedRepeatAfter(task.repeatAfter ?? 0),
            reminders: task.reminders ?? [],
            percentDone: task.percentDone ?? 0,
            clearDueDate: task.effectiveDueDate == nil,
            clearStartDate: task.effectiveStartDate == nil,
            clearEndDate: task.effectiveEndDate == nil
        )
    }

    // MARK: - Encoding

    func testCompletingSendsOnlyDone() throws {
        let body = try encodedBody(TaskUpdateRequest(done: true))
        XCTAssertEqual(body.count, 1, "\(body)")
        XCTAssertEqual(body["done"] as? Bool, true)
    }

    func testAClearedDateIsSentAsNull() throws {
        let body = try encodedBody(TaskUpdateRequest(clearDueDate: true, clearStartDate: true))
        XCTAssertTrue(body["due_date"] is NSNull)
        XCTAssertTrue(body["start_date"] is NSNull)
        XCTAssertNil(body["end_date"], "A date nobody cleared stays out of the body")
    }

    func testAClearWinsOverADate() throws {
        let body = try encodedBody(TaskUpdateRequest(dueDate: Date(), clearDueDate: true))
        XCTAssertTrue(body["due_date"] is NSNull)
    }

    func testAssigneesAreLeftOutUnlessChanged() throws {
        XCTAssertNil(try encodedBody(TaskUpdateRequest(priority: 2))["assignees"])
        let cleared = try encodedBody(TaskUpdateRequest(assignees: []))
        XCTAssertEqual((cleared["assignees"] as? [Any])?.count, 0, "An empty list unassigns everyone")
    }

    // MARK: - onlyChanges

    func testSavingTheEditorUnchangedSendsNothing() {
        let task = richTask()
        XCTAssertTrue(editorSave(of: task).onlyChanges(from: task).isEmpty)
    }

    func testSavingAnUnchangedTaskWithNoDatesSendsNothing() {
        let task = VTask(id: 2, title: "Bare", done: false, priority: 0, projectId: 1)
        XCTAssertTrue(editorSave(of: task).onlyChanges(from: task).isEmpty)
    }

    func testOnlyTheEditedFieldIsSent() throws {
        let task = richTask()
        var save = editorSave(of: task)
        save.title = "Water all the plants"

        let body = try encodedBody(save.onlyChanges(from: task))

        XCTAssertEqual(body.keys.sorted(), ["title"])
        XCTAssertEqual(body["title"] as? String, "Water all the plants")
    }

    func testClearingADateTheTaskHasIsKept() throws {
        let task = richTask()
        var save = editorSave(of: task)
        save.dueDate = nil
        save.clearDueDate = true

        let body = try encodedBody(save.onlyChanges(from: task))

        XCTAssertEqual(body.keys.sorted(), ["due_date"])
        XCTAssertTrue(body["due_date"] is NSNull)
    }

    func testChangingADateIsKept() {
        let task = richTask()
        let later = Date(timeIntervalSince1970: 1_800_086_400)
        var save = editorSave(of: task)
        save.dueDate = later

        let changes = save.onlyChanges(from: task)

        XCTAssertEqual(changes.dueDate, later)
        XCTAssertNil(changes.clearDueDate)
    }

    func testClearingTheDescriptionIsKept() {
        let task = richTask()
        var save = editorSave(of: task)
        save.description = ""

        XCTAssertEqual(save.onlyChanges(from: task).description, "")
    }

    func testAnEmptyDescriptionMatchesNone() {
        var task = richTask()
        task.description = nil
        XCTAssertNil(TaskUpdateRequest(description: "").onlyChanges(from: task).description)
    }

    func testMovingProjectIsKept() {
        let task = richTask()
        var save = editorSave(of: task)
        save.projectId = 9

        XCTAssertEqual(save.onlyChanges(from: task), TaskUpdateRequest(projectId: 9))
    }

    func testStoppingARepeatIsKept() {
        let task = richTask()
        var save = editorSave(of: task)
        save.repeatAfter = 0
        save.repeatMode = task.repeatModeForEditedRepeatAfter(0)

        let changes = save.onlyChanges(from: task)
        XCTAssertEqual(changes.repeatAfter, 0)
    }

    func testSameAssigneesAreDropped() {
        let task = richTask()
        XCTAssertNil(TaskUpdateRequest(assignees: [alice]).onlyChanges(from: task).assignees)
        XCTAssertEqual(TaskUpdateRequest(assignees: []).onlyChanges(from: task).assignees, [])
    }

    func testTickingOffIsKept() {
        let task = richTask()
        XCTAssertEqual(TaskUpdateRequest(done: true).onlyChanges(from: task), TaskUpdateRequest(done: true))
    }
}
