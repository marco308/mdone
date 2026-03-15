import XCTest
@testable import mDone

final class NotificationServiceTests: XCTestCase {

    func testReminderOffsetValues() {
        XCTAssertEqual(NotificationService.ReminderOffset.fifteenMinutes.timeInterval, 900)
        XCTAssertEqual(NotificationService.ReminderOffset.thirtyMinutes.timeInterval, 1800)
        XCTAssertEqual(NotificationService.ReminderOffset.oneHour.timeInterval, 3600)
        XCTAssertEqual(NotificationService.ReminderOffset.oneDay.timeInterval, 86400)
    }

    func testReminderOffsetLabels() {
        XCTAssertEqual(NotificationService.ReminderOffset.fifteenMinutes.label, "15 minutes before")
        XCTAssertEqual(NotificationService.ReminderOffset.thirtyMinutes.label, "30 minutes before")
        XCTAssertEqual(NotificationService.ReminderOffset.oneHour.label, "1 hour before")
        XCTAssertEqual(NotificationService.ReminderOffset.oneDay.label, "1 day before")
    }

    func testReminderOffsetAllCases() {
        XCTAssertEqual(NotificationService.ReminderOffset.allCases.count, 4)
    }
}
