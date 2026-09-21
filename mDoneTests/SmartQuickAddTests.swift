import XCTest
@testable import mDone

/// The quick-add side of smart parsing (#225): the setting, how a parse and
/// rejected chips turn into what gets created, and labels landing on the new
/// task. Rows come from "Setting, rejection, and entry-point behaviour" and
/// "Parses, but the chip is the safety net" in #223.
@MainActor
final class SmartQuickAddTests: XCTestCase {
    private static let inbox: Int64 = 1
    private static let home: Int64 = 2
    private static let work: Int64 = 4
    private static let shopping: Int64 = 10

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Inbox with its default due date set to "Today" (18:00).
    private var inboxDefault: Date {
        date(2026, 9, 21, 18)
    }

    private func parse(_ text: String) -> SmartTaskParse {
        SmartTaskParser(
            projects: [
                .init(id: Self.inbox, name: "Inbox"),
                .init(id: Self.home, name: "Home"),
                .init(id: Self.work, name: "Work"),
            ],
            labels: [.init(id: Self.shopping, name: "shopping")],
            now: date(2026, 9, 21, 10),
            calendar: calendar,
            locale: Locale(identifier: "en_GB"),
            defaultDueTime: .sixPM,
            usesDataDetector: false
        ).parse(text)
    }

    private func submission(
        _ text: String,
        smart: Bool = true,
        rejecting rejected: Set<SmartTaskParse.Field> = [],
        projectId: Int64 = SmartQuickAddTests.inbox,
        defaultDueDate: Date? = nil
    ) -> QuickAddSubmission? {
        QuickAddSubmission.make(
            text: text,
            parse: smart ? parse(text) : nil,
            rejected: rejected,
            projectId: projectId,
            defaultDueDate: defaultDueDate
        )
    }

    // MARK: - Setting

    func testSmartParsingIsOffByDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        XCTAssertFalse(SmartParsingPreference.isEnabled(defaults: defaults))
        defaults.set(true, forKey: SmartParsingPreference.storageKey)
        XCTAssertTrue(SmartParsingPreference.isEnabled(defaults: defaults))
    }

    func testSettingOffKeepsTitleVerbatimAndInboxDefault() {
        XCTAssertEqual(
            submission("Buy milk tomorrow", smart: false, defaultDueDate: inboxDefault),
            QuickAddSubmission(
                title: "Buy milk tomorrow", projectId: Self.inbox, dueDate: inboxDefault, priority: 0, labelIds: []
            )
        )
    }

    // MARK: - Rejection and precedence

    func testRejectingDateChipRestoresWordsAndInboxDefault() {
        let result = submission("Buy milk tomorrow", rejecting: [.dueDate], defaultDueDate: inboxDefault)
        XCTAssertEqual(result?.title, "Buy milk tomorrow")
        XCTAssertEqual(result?.dueDate, inboxDefault)
    }

    func testParsedDateBeatsInboxDefault() {
        let result = submission("Buy milk tomorrow", defaultDueDate: inboxDefault)
        XCTAssertEqual(result?.title, "Buy milk")
        XCTAssertEqual(result?.dueDate, date(2026, 9, 22, 18))
    }

    func testParsedProjectBeatsViewedProject() {
        let result = submission("Fix tap +Work", projectId: Self.home)
        XCTAssertEqual(result?.title, "Fix tap")
        XCTAssertEqual(result?.projectId, Self.work)
    }

    func testRejectingProjectChipUsesViewedProject() {
        let result = submission("Fix tap +Work", rejecting: [.project], projectId: Self.home)
        XCTAssertEqual(result?.title, "Fix tap +Work")
        XCTAssertEqual(result?.projectId, Self.home)
    }

    func testPriorityAndLabelsCarryThrough() {
        let result = submission("Buy gift !2 *shopping")
        XCTAssertEqual(result?.title, "Buy gift")
        XCTAssertEqual(result?.priority, 2)
        XCTAssertEqual(result?.labelIds, [Self.shopping])
    }

    // MARK: - Safety net rows

    func testWeekdayChipRejectedGivesFullTitleBack() {
        let parsed = submission("Watch Friday Night Lights")
        XCTAssertEqual(parsed?.title, "Watch Night Lights")
        XCTAssertEqual(parsed?.dueDate, date(2026, 9, 25, 18))

        let rejected = submission("Watch Friday Night Lights", rejecting: [.dueDate])
        XCTAssertEqual(rejected?.title, "Watch Friday Night Lights")
        XCTAssertNil(rejected?.dueDate)
    }

    func testDateOnlyTextKeepsRawTitleAndStillApplies() {
        let result = submission("tomorrow", defaultDueDate: inboxDefault)
        XCTAssertEqual(result?.title, "tomorrow")
        XCTAssertEqual(result?.dueDate, date(2026, 9, 22, 18))
    }

    func testBlankTextSubmitsNothing() {
        XCTAssertNil(submission("   "))
        XCTAssertNil(submission("", smart: false))
    }

    // MARK: - Labels on create

    /// Vikunja ignores labels in the create body, so each parsed label goes
    /// through `PUT /tasks/{id}/labels` after the task exists.
    func testCreateTaskAddsLabelsThroughLabelEndpoint() async {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let state = AppState(
            taskService: TaskService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
        state.labels = [VLabel(id: Self.shopping, title: "shopping")]

        var paths: [String] = []
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            paths.append("\(request.httpMethod ?? "") \(path)")
            let body = path.hasSuffix("/labels")
                ? #"{"label_id": 10}"#
                : #"{"id": 99, "title": "Buy gift", "done": false, "project_id": 1, "priority": 2}"#
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data(body.utf8))
        }

        let created = await state.createTask(title: "Buy gift", projectId: 1, priority: 2, labelIds: [Self.shopping])

        XCTAssertEqual(paths, ["PUT /api/v1/projects/1/tasks", "PUT /api/v1/tasks/99/labels"])
        XCTAssertEqual(created?.labels?.map(\.id), [Self.shopping])
        XCTAssertEqual(state.tasks.first { $0.id == 99 }?.labels?.map(\.id), [Self.shopping])
    }
}
