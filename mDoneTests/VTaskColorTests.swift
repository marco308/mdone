import XCTest
@testable import mDone

final class VTaskColorTests: XCTestCase {
    func testValidSixDigitHexIsReturned() {
        XCTAssertEqual(makeTask(hexColor: "F2490C").normalizedHexColor, "F2490C")
    }

    func testLeadingHashIsStripped() {
        XCTAssertEqual(makeTask(hexColor: "#4772FA").normalizedHexColor, "4772FA")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(makeTask(hexColor: "  1a8cff \n").normalizedHexColor, "1a8cff")
    }

    func testThreeAndEightDigitHexAreAccepted() {
        XCTAssertEqual(makeTask(hexColor: "f00").normalizedHexColor, "f00")
        XCTAssertEqual(makeTask(hexColor: "FF4444AA").normalizedHexColor, "FF4444AA")
    }

    func testNilHexColorReturnsNil() {
        XCTAssertNil(makeTask(hexColor: nil).normalizedHexColor)
    }

    func testEmptyOrHashOnlyReturnsNil() {
        // Vikunja sends an empty string for uncolored tasks.
        XCTAssertNil(makeTask(hexColor: "").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "   ").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "#").normalizedHexColor)
    }

    func testInvalidLengthReturnsNil() {
        XCTAssertNil(makeTask(hexColor: "FFFF").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "1234567").normalizedHexColor)
    }

    func testNonHexCharactersReturnNil() {
        XCTAssertNil(makeTask(hexColor: "GGGGGG").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "12 34 56").normalizedHexColor)
    }

    /// Only one leading `#` is a prefix; anything else is a malformed value, not
    /// a color with decoration.
    func testRepeatedOrTrailingHashIsNil() {
        XCTAssertNil(makeTask(hexColor: "##FF0000").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "#FF0000#").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "FF0000#").normalizedHexColor)
        XCTAssertNil(makeTask(hexColor: "##").normalizedHexColor)
    }

    private func makeTask(hexColor: String?) -> VTask {
        VTask(
            id: 1,
            title: "T",
            description: nil,
            done: false,
            doneAt: nil,
            dueDate: nil,
            startDate: nil,
            endDate: nil,
            priority: 0,
            projectId: 1,
            hexColor: hexColor,
            percentDone: nil,
            uid: nil,
            position: nil,
            isFavorite: nil,
            repeatAfter: nil,
            repeatMode: nil,
            identifier: nil,
            index: nil,
            reminders: nil,
            assignees: nil,
            labels: nil,
            createdBy: nil,
            created: nil,
            updated: nil,
            bucketId: nil,
            coverImageAttachmentId: nil
        )
    }
}
