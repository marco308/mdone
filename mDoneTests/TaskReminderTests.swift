import XCTest
@testable import mDone

/// Issue #242: a fixed-time reminder came back from Vikunja looking like
/// "At time of due date". The payloads here are what a Vikunja v2.4.0 server
/// actually returned for a task due 15:00 with reminders set through the API,
/// so they carry the `relative_period: 0, relative_to: ""` the server adds
/// to an absolute reminder.
final class TaskReminderTests: XCTestCase {
    private static let serverTaskJSON = """
    {
        "id": 1,
        "title": "probe 242",
        "done": false,
        "due_date": "2026-10-17T15:00:00Z",
        "start_date": "2026-10-17T09:00:00Z",
        "end_date": "0001-01-01T00:00:00Z",
        "priority": 0,
        "project_id": 2,
        "reminders": [
            {"reminder": "2026-10-17T12:00:00Z", "relative_period": 0, "relative_to": ""},
            {"reminder": "2026-10-17T15:00:00Z", "relative_period": 0, "relative_to": "due_date"},
            {"reminder": "2026-10-17T14:30:00Z", "relative_period": -1800, "relative_to": "due_date"}
        ]
    }
    """

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private func decodeServerTask() throws -> VTask {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let isoFormatter = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if dateString.hasPrefix("0001-01-01") {
                return .distantPast
            }
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return try decoder.decode(VTask.self, from: Data(Self.serverTaskJSON.utf8))
    }

    func testServerAbsoluteReminderIsNotRelative() throws {
        let reminders = try XCTUnwrap(decodeServerTask().reminders)
        XCTAssertEqual(reminders[0].relativePeriod, 0, "precondition: the server sends a zero period")
        XCTAssertFalse(reminders[0].isRelative)
        XCTAssertTrue(reminders[1].isRelative)
        XCTAssertTrue(reminders[2].isRelative)
    }

    func testServerAbsoluteReminderFiresAtItsOwnTime() throws {
        let task = try decodeServerTask()
        let reminders = try XCTUnwrap(task.reminders)
        XCTAssertEqual(reminders[0].fireDate(for: task), date("2026-10-17T12:00:00Z"))
        XCTAssertEqual(reminders[1].fireDate(for: task), date("2026-10-17T15:00:00Z"))
        XCTAssertEqual(reminders[2].fireDate(for: task), date("2026-10-17T14:30:00Z"))
    }

    func testServerAbsoluteReminderIsNotLabelledAsDueTime() throws {
        let reminders = try XCTUnwrap(decodeServerTask().reminders)
        let noon = date("2026-10-17T12:00:00Z")
        XCTAssertEqual(
            ReminderEditor.displayText(for: reminders[0]),
            noon.formatted(date: .abbreviated, time: .shortened)
        )
        XCTAssertEqual(
            ReminderEditor.displayText(for: reminders[1]),
            String(localized: "At time of due date")
        )
    }

    func testRelativeReminderFollowsALocallyEditedDueDate() throws {
        var task = try decodeServerTask()
        task.dueDate = date("2026-10-18T10:00:00Z")
        let reminders = try XCTUnwrap(task.reminders)
        // The server's computed `reminder` is now stale; the offset wins.
        XCTAssertEqual(reminders[2].fireDate(for: task), date("2026-10-18T09:30:00Z"))
        XCTAssertEqual(reminders[0].fireDate(for: task), date("2026-10-17T12:00:00Z"))
    }

    func testRelativeReminderUsesTheDateItIsRelativeTo() throws {
        let task = try decodeServerTask()
        let toStart = TaskReminder(reminder: nil, relativePeriod: -600, relativeTo: "start_date")
        XCTAssertEqual(toStart.fireDate(for: task), date("2026-10-17T08:50:00Z"))

        // The server's zero end date means "unset", so there is nothing to fire from.
        let toEnd = TaskReminder(reminder: nil, relativePeriod: 0, relativeTo: "end_date")
        XCTAssertNil(toEnd.fireDate(for: task))
    }

    func testRelativeReminderWithoutItsDateDoesNotFire() throws {
        var task = try decodeServerTask()
        task.dueDate = nil
        let atDue = TaskReminder(reminder: nil, relativePeriod: 0, relativeTo: "due_date")
        XCTAssertNil(atDue.fireDate(for: task))
    }

    func testReminderCreatedInTheEditorWithNilFieldsIsAbsolute() {
        let noon = date("2026-10-17T12:00:00Z")
        let reminder = TaskReminder(reminder: noon, relativePeriod: nil, relativeTo: nil)
        XCTAssertFalse(reminder.isRelative)
        let task = VTask(id: 1, title: "t", done: false, priority: 0, projectId: 1)
        XCTAssertEqual(reminder.fireDate(for: task), noon)
    }
}
