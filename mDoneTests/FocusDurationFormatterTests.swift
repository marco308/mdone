import XCTest
@testable import mDone

final class FocusDurationFormatterTests: XCTestCase {
    func testSecondsUnderOneMinute() {
        XCTAssertEqual(FocusDurationFormatter.string(from: 0), "0s")
        XCTAssertEqual(FocusDurationFormatter.string(from: 1), "1s")
        XCTAssertEqual(FocusDurationFormatter.string(from: 45), "45s")
        XCTAssertEqual(FocusDurationFormatter.string(from: 59), "59s")
    }

    func testMinutesUnderOneHour() {
        // DateComponentsFormatter truncates rather than rounding — conservative
        // for focus stats: never credit the user with more time than they did.
        XCTAssertEqual(FocusDurationFormatter.string(from: 60), "1m")
        XCTAssertEqual(FocusDurationFormatter.string(from: 90), "1m")
        XCTAssertEqual(FocusDurationFormatter.string(from: 600), "10m")
        XCTAssertEqual(FocusDurationFormatter.string(from: 3599), "59m")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(FocusDurationFormatter.string(from: 3600), "1h")
        XCTAssertEqual(FocusDurationFormatter.string(from: 3660), "1h 1m")
        XCTAssertEqual(FocusDurationFormatter.string(from: 5400), "1h 30m")
        XCTAssertEqual(FocusDurationFormatter.string(from: 7320), "2h 2m")
    }

    func testCapsAtTwoUnits() {
        // 1d 2h 3m 4s would be 4 units — formatter should cap at 2 (hours + minutes)
        let oneDayTwoHoursThree = TimeInterval(86400 + 7200 + 180)
        let result = FocusDurationFormatter.string(from: oneDayTwoHoursThree)
        // Result should contain at most 2 unit segments
        let segments = result.split(separator: " ").count
        XCTAssertLessThanOrEqual(segments, 2, "Got \(result) — expected at most 2 units")
    }

    func testNegativeInputClampsToZero() {
        XCTAssertEqual(FocusDurationFormatter.string(from: -5), "0s")
        XCTAssertEqual(FocusDurationFormatter.string(from: -3600), "0s")
    }
}
