import XCTest
@testable import mDone

/// One test per row of the "Example inputs" tables in #223, pinned to
/// Monday 21 Sep 2026 10:00, en_GB, week starting Monday, default due time
/// 18:00. The zh-Hans date rows arrive with the keyword column in phase 3.
final class SmartTaskParserTests: XCTestCase {
    private static let inbox: Int64 = 1
    private static let home: Int64 = 2
    private static let homeImprovements: Int64 = 3
    private static let work: Int64 = 4
    private static let shopping: Int64 = 10
    private static let urgent: Int64 = 11

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parser(locale: String = "en_GB", dataDetector: Bool = false) -> SmartTaskParser {
        SmartTaskParser(
            projects: [
                .init(id: Self.inbox, name: "Inbox"),
                .init(id: Self.home, name: "Home"),
                .init(id: Self.homeImprovements, name: "Home Improvements"),
                .init(id: Self.work, name: "Work"),
            ],
            labels: [
                .init(id: Self.shopping, name: "shopping"),
                .init(id: Self.urgent, name: "urgent"),
            ],
            now: date(2026, 9, 21, 10, 0),
            calendar: calendar,
            locale: Locale(identifier: locale),
            defaultDueTime: .sixPM,
            usesDataDetector: dataDetector
        )
    }

    private func assertParse(
        _ input: String,
        title: String,
        due: Date? = nil,
        project: Int64? = nil,
        priority: Int? = nil,
        labels: [Int64] = [],
        locale: String = "en_GB",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = parser(locale: locale).parse(input)
        XCTAssertEqual(result.title, title, "title", file: file, line: line)
        XCTAssertEqual(result.dueDate, due, "due date", file: file, line: line)
        XCTAssertEqual(result.projectId, project, "project", file: file, line: line)
        XCTAssertEqual(result.priority, priority, "priority", file: file, line: line)
        XCTAssertEqual(result.labelIds, labels, "labels", file: file, line: line)
    }

    // MARK: - Relative dates

    func testTomorrow() {
        assertParse("Buy milk tomorrow", title: "Buy milk", due: date(2026, 9, 22, 18))
    }

    func testToday() {
        assertParse("Call mum today", title: "Call mum", due: date(2026, 9, 21, 18))
    }

    func testTonightIsNinePM() {
        assertParse("Pay rent tonight", title: "Pay rent", due: date(2026, 9, 21, 21))
    }

    func testInNDays() {
        assertParse("Water plants in 3 days", title: "Water plants", due: date(2026, 9, 24, 18))
    }

    func testBareWeekdayIsNextOccurrence() {
        assertParse("Dentist friday", title: "Dentist", due: date(2026, 9, 25, 18))
    }

    func testNextWeekdayMatchesBareWeekday() {
        assertParse("Dentist next friday", title: "Dentist", due: date(2026, 9, 25, 18))
    }

    func testTodaysWeekdayIsAWeekOut() {
        assertParse("Dentist monday", title: "Dentist", due: date(2026, 9, 28, 18))
    }

    func testNextWeekIsStartOfNextWeek() {
        assertParse("Renew passport next week", title: "Renew passport", due: date(2026, 9, 28, 18))
    }

    func testNextMonthIsFirstOfNextMonth() {
        assertParse("Book MOT next month", title: "Book MOT", due: date(2026, 10, 1, 18))
    }

    // MARK: - Times

    func testWeekdayWithTime() {
        assertParse("Submit report friday at 3pm", title: "Submit report", due: date(2026, 9, 25, 15))
    }

    func testTimeWithoutAt() {
        assertParse("Call bank 5pm", title: "Call bank", due: date(2026, 9, 21, 17))
    }

    func testNoon() {
        assertParse("Lunch with Sam at noon", title: "Lunch with Sam", due: date(2026, 9, 21, 12))
    }

    func testPastTimeRollsToTomorrow() {
        assertParse("Standup at 9:30", title: "Standup", due: date(2026, 9, 22, 9, 30))
    }

    func testTwentyFourHourTimeBeforeDay() {
        assertParse("Standup at 09:30 tomorrow", title: "Standup", due: date(2026, 9, 22, 9, 30))
    }

    func testDayPartMorning() {
        assertParse("Gym tomorrow morning", title: "Gym", due: date(2026, 9, 22, 9))
    }

    // MARK: - Absolute dates

    func testMonthNameThenDayConsumesOn() {
        assertParse("Team meeting on Sept 25", title: "Team meeting", due: date(2026, 9, 25, 18))
    }

    func testNumericDateDayFirstInBritishEnglish() {
        assertParse("Flight 25/9", title: "Flight", due: date(2026, 9, 25, 18))
    }

    func testNumericDateIsNotParsedMonthFirstWhenInvalid() {
        assertParse("Flight 25/9", title: "Flight 25/9", locale: "en_US")
    }

    func testPastDateWithoutYearRollsToNextYear() {
        assertParse("Taxes 15 April", title: "Taxes", due: date(2027, 4, 15, 18))
    }

    func testISODate() {
        assertParse("Renew insurance 2026-12-01", title: "Renew insurance", due: date(2026, 12, 1, 18))
    }

    // MARK: - Project, priority, label

    func testPlusProject() {
        assertParse("Fix tap +Home", title: "Fix tap", project: Self.home)
    }

    func testHashProject() {
        assertParse("Fix tap #Home", title: "Fix tap", project: Self.home)
    }

    func testLongestProjectNameWins() {
        assertParse("Paint fence +Home Improvements", title: "Paint fence", project: Self.homeImprovements)
    }

    func testProjectMatchIsCaseInsensitiveAndExactBeatsPrefix() {
        assertParse("Paint fence +home", title: "Paint fence", project: Self.home)
    }

    func testProjectAtStart() {
        assertParse("+Work write deck tomorrow", title: "write deck", due: date(2026, 9, 22, 18), project: Self.work)
    }

    func testUnknownProjectStaysInTitle() {
        assertParse("Email +Nonexistent tomorrow", title: "Email +Nonexistent", due: date(2026, 9, 22, 18))
    }

    func testPlusInsideWordIsNotAProject() {
        assertParse("Review C++ notes", title: "Review C++ notes")
    }

    func testHashNumberIsNotAProject() {
        assertParse("Send #123 invoice", title: "Send #123 invoice")
    }

    func testPriority() {
        assertParse("Fix login !3", title: "Fix login", priority: 3)
    }

    func testOutOfRangePriorityIsLeftAlone() {
        assertParse("Fix login !9", title: "Fix login !9")
    }

    func testLabel() {
        assertParse("Buy gift *shopping", title: "Buy gift", labels: [Self.shopping])
    }

    func testUnknownLabelStaysInTitle() {
        assertParse("Buy gift *nothing", title: "Buy gift *nothing")
    }

    // MARK: - Must not parse

    func testPossessiveBlocksDate() {
        assertParse("Read Tomorrow's paper", title: "Read Tomorrow's paper")
    }

    func testBareNumberRoom() {
        assertParse("Call room 5", title: "Call room 5")
    }

    func testBareNumberQuantity() {
        assertParse("Buy 3 apples", title: "Buy 3 apples")
    }

    func testBareYear() {
        assertParse("Order 2024 calendar", title: "Order 2024 calendar")
    }

    func testMonthInsideWord() {
        assertParse("Monthly report", title: "Monthly report")
    }

    func testAtWithoutTime() {
        assertParse("Meet at the station", title: "Meet at the station")
    }

    func testWeekly() {
        assertParse("Weekly sync", title: "Weekly sync")
    }

    func testEmptyAndWhitespace() {
        assertParse("", title: "")
        assertParse("   ", title: "")
        XCTAssertTrue(parser().parse("  \n ").matches.isEmpty)
    }

    // MARK: - Parses, chip is the safety net

    func testWeekdayInsideTitleParses() {
        assertParse("Watch Friday Night Lights", title: "Watch Night Lights", due: date(2026, 9, 25, 18))
    }

    func testDateOnlyInputKeepsRawTitle() {
        assertParse("tomorrow", title: "tomorrow", due: date(2026, 9, 22, 18))
    }

    // MARK: - Combined

    func testDateTimeProjectPriority() {
        assertParse(
            "Buy milk tomorrow at 5pm +Home !2",
            title: "Buy milk", due: date(2026, 9, 22, 17), project: Self.home, priority: 2
        )
    }

    func testProjectBetweenDateAndLabels() {
        assertParse(
            "Buy milk +Home tomorrow at 5pm *shopping *urgent",
            title: "Buy milk", due: date(2026, 9, 22, 17), project: Self.home, labels: [Self.shopping, Self.urgent]
        )
    }

    func testWhitespaceCollapsedAfterStripping() {
        assertParse("Buy   milk   tomorrow", title: "Buy milk", due: date(2026, 9, 22, 18))
    }

    // MARK: - Any locale

    func testProjectPrefixWorksInChineseText() {
        assertParse("修水龙头 +Home", title: "修水龙头", project: Self.home, locale: "zh_Hans_CN")
    }

    // MARK: - Rejection and ranges

    func testRejectingDatePutsWordsBack() {
        let parse = parser().parse("Buy milk tomorrow at 5pm +Home").rejecting([.dueDate])
        XCTAssertEqual(parse.title, "Buy milk tomorrow at 5pm")
        XCTAssertNil(parse.dueDate)
        XCTAssertFalse(parse.dueDateHasTime)
        XCTAssertEqual(parse.projectId, Self.home)
    }

    func testRejectingWeekdayRestoresFullTitle() {
        let parse = parser().parse("Watch Friday Night Lights").rejecting([.dueDate])
        XCTAssertEqual(parse.title, "Watch Friday Night Lights")
        XCTAssertNil(parse.dueDate)
    }

    func testRejectingOneLabelKeepsTheOther() {
        let parse = parser().parse("Buy gift *shopping *urgent").rejecting([.label(Self.urgent)])
        XCTAssertEqual(parse.title, "Buy gift *urgent")
        XCTAssertEqual(parse.labelIds, [Self.shopping])
    }

    func testRangesCoverTheConsumedText() {
        let parse = parser().parse("Submit report friday at 3pm +Work")
        XCTAssertEqual(parse.ranges(for: .dueDate).map { String(parse.text[$0]) }, ["friday", "at 3pm"])
        XCTAssertEqual(parse.ranges(for: .project).map { String(parse.text[$0]) }, ["+Work"])
    }

    func testDateOnlyVersusExplicitTimeFlag() {
        XCTAssertFalse(parser().parse("Buy milk tomorrow").dueDateHasTime)
        XCTAssertTrue(parser().parse("Buy milk tomorrow at 5pm").dueDateHasTime)
        XCTAssertTrue(parser().parse("Pay rent tonight").dueDateHasTime)
    }

    // MARK: - Beyond the tables

    func testDayPartWithoutDayIsNotADate() {
        assertParse("Morning pages", title: "Morning pages")
    }

    func testImpossibleDateIsNotParsed() {
        assertParse("Party 31/2", title: "Party 31/2")
    }

    func testDuplicateLabelIsOnlyCountedOnce() {
        assertParse("Buy *shopping *Shopping", title: "Buy *Shopping", labels: [Self.shopping])
    }

    func testUniqueProjectPrefixMatches() {
        assertParse("Sand door +Improv", title: "Sand door +Improv")
        assertParse("Sand door +Home Imp", title: "Sand door Imp", project: Self.home)
        assertParse("Deck +Wor", title: "Deck", project: Self.work)
    }

    func testArchivedProjectsAreNotCandidates() {
        let active = Project(id: 5, title: "Garden", isArchived: false)
        let archived = Project(id: 6, title: "Garage", isArchived: true)
        let parser = SmartTaskParser(
            projects: [active, archived], labels: [],
            now: date(2026, 9, 21, 10), calendar: calendar, locale: Locale(identifier: "en_GB"), defaultDueTime: .sixPM
        )
        XCTAssertEqual(parser.parse("Weed +Garden").projectId, 5)
        XCTAssertNil(parser.parse("Tidy +Garage").projectId)
    }

    func testDayFirstLocaleDetection() {
        XCTAssertTrue(SmartTaskParser.isDayFirst(Locale(identifier: "en_GB")))
        XCTAssertFalse(SmartTaskParser.isDayFirst(Locale(identifier: "en_US")))
    }

    // MARK: - Data detector

    func testDetectorFilterRejectsBareNumbersAndTimes() {
        XCTAssertFalse(SmartTaskParser.isPlausibleDetectorMatch("2024"))
        XCTAssertFalse(SmartTaskParser.isPlausibleDetectorMatch("5"))
        XCTAssertFalse(SmartTaskParser.isPlausibleDetectorMatch("at 5"))
        XCTAssertFalse(SmartTaskParser.isPlausibleDetectorMatch("tomorrow"))
        XCTAssertTrue(SmartTaskParser.isPlausibleDetectorMatch("12.10.2026"))
        XCTAssertTrue(SmartTaskParser.isPlausibleDetectorMatch("Dezember 3"))
        XCTAssertTrue(SmartTaskParser.isPlausibleDetectorMatch("12月3日"))
    }

    /// The detector reads the real clock and system locale, so this only
    /// checks that the must-not-parse rows stay clean with it switched on.
    func testDetectorDoesNotParseBareNumbers() {
        let parser = parser(dataDetector: true)
        for input in [
            "Call room 5",
            "Buy 3 apples",
            "Order 2024 calendar",
            "Read Tomorrow's paper",
            "Meet at the station",
        ] {
            let parse = parser.parse(input)
            XCTAssertNil(parse.dueDate, input)
            XCTAssertEqual(parse.title, input)
        }
    }

    /// Tolerant of OS drift: whatever the detector makes of the date, it must
    /// strip it cleanly and land on a date-only default time.
    func testDetectorFallbackStripsWhatItParses() {
        let parse = parser(dataDetector: true).parse("Pay bill 12.10.2027")
        guard let due = parse.dueDate else { return }
        XCTAssertEqual(parse.title, "Pay bill")
        XCTAssertFalse(parse.dueDateHasTime)
        XCTAssertEqual(calendar.component(.hour, from: due), 18)
    }
}
