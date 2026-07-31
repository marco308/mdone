import XCTest
@testable import mDone

final class TaskDateRangeMetadataTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    private let locale = Locale(identifier: "en_US")

    func testReturnsNilWithoutStartOrEndDate() {
        XCTAssertNil(TaskDateRangeMetadata.make(
            startDate: nil,
            endDate: nil,
            calendar: calendar,
            locale: locale
        ))
    }

    func testFormatsInclusiveMultiDayRangeCompactly() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 17
        )))

        let metadata = try XCTUnwrap(TaskDateRangeMetadata.make(
            startDate: start,
            endDate: end,
            calendar: calendar,
            locale: locale
        ))

        XCTAssertTrue(metadata.compactText.contains("24"))
        XCTAssertTrue(metadata.compactText.contains("26"))
        XCTAssertTrue(metadata.accessibilityText.localizedCaseInsensitiveContains("starts"))
        XCTAssertTrue(metadata.accessibilityText.localizedCaseInsensitiveContains("ends"))
    }

    func testFormatsStartOnlyDate() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))

        let metadata = try XCTUnwrap(TaskDateRangeMetadata.make(
            startDate: start,
            endDate: nil,
            calendar: calendar,
            locale: locale
        ))

        XCTAssertTrue(metadata.compactText.hasPrefix("Starts "))
        XCTAssertTrue(metadata.compactText.contains("24"))
        XCTAssertTrue(metadata.accessibilityText.contains("9:00"))
    }

    func testFormatsEndOnlyDate() throws {
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 17
        )))

        let metadata = try XCTUnwrap(TaskDateRangeMetadata.make(
            startDate: nil,
            endDate: end,
            calendar: calendar,
            locale: locale
        ))

        XCTAssertTrue(metadata.compactText.hasPrefix("Ends "))
        XCTAssertTrue(metadata.compactText.contains("26"))
        XCTAssertTrue(metadata.accessibilityText.contains("5:00"))
    }

    func testSameDayRangeKeepsBothTimesForAccessibility() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 17
        )))

        let metadata = try XCTUnwrap(TaskDateRangeMetadata.make(
            startDate: start,
            endDate: end,
            calendar: calendar,
            locale: locale
        ))

        XCTAssertTrue(metadata.compactText.contains("24"))
        XCTAssertTrue(metadata.accessibilityText.contains("9:00"))
        XCTAssertTrue(metadata.accessibilityText.contains("5:00"))
    }

    func testLocalizesBoundaryLabelsInGerman() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))
        let german = Locale(identifier: "de_CH")

        let metadata = try XCTUnwrap(TaskDateRangeMetadata.make(
            startDate: start,
            endDate: nil,
            calendar: calendar,
            locale: german
        ))

        XCTAssertTrue(metadata.compactText.hasPrefix("Beginnt "))
        XCTAssertTrue(metadata.accessibilityText.hasPrefix("beginnt "))
        XCTAssertFalse(metadata.compactText.contains("Starts"))
    }

    func testReversedRangeUsesOrderedBoundsAndNeutralAccessibilityLabel() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 17
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))
        let german = Locale(identifier: "de_CH")

        let metadata = try XCTUnwrap(TaskDateRangeMetadata.make(
            startDate: start,
            endDate: end,
            calendar: calendar,
            locale: german
        ))

        XCTAssertTrue(metadata.compactText.contains("24"))
        XCTAssertTrue(metadata.compactText.contains("26"))
        XCTAssertTrue(metadata.accessibilityText.hasPrefix("Datumsbereich "))
        XCTAssertTrue(metadata.accessibilityText.contains(" bis "))
    }
}
