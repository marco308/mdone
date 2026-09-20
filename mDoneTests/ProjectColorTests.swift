import XCTest
@testable import mDone

final class ProjectColorTests: XCTestCase {
    func testValidSixDigitHexIsReturned() {
        XCTAssertEqual(makeProject(hexColor: "F2490C").normalizedHexColor, "F2490C")
    }

    func testLeadingHashIsStripped() {
        XCTAssertEqual(makeProject(hexColor: "#4772FA").normalizedHexColor, "4772FA")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(makeProject(hexColor: "  1a8cff \n").normalizedHexColor, "1a8cff")
    }

    func testShorthandAndAlphaLengthsAreAccepted() {
        XCTAssertEqual(makeProject(hexColor: "f00").normalizedHexColor, "f00")
        XCTAssertEqual(makeProject(hexColor: "FF4444AA").normalizedHexColor, "FF4444AA")
    }

    func testMissingColorIsNil() {
        XCTAssertNil(makeProject(hexColor: nil).normalizedHexColor)
    }

    /// Vikunja stores an empty `hex_color` for a project created without a color,
    /// and the app's own "No color" swatch writes the same empty string back.
    func testEmptyColorIsNil() {
        XCTAssertNil(makeProject(hexColor: "").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "   ").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "#").normalizedHexColor)
    }

    func testWrongLengthIsNil() {
        XCTAssertNil(makeProject(hexColor: "FFFF").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "1234567").normalizedHexColor)
    }

    /// Only one leading `#` is a prefix; anything else is a malformed value, not
    /// a color with decoration.
    func testRepeatedOrTrailingHashIsNil() {
        XCTAssertNil(makeProject(hexColor: "##FF0000").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "#FF0000#").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "FF0000#").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "##").normalizedHexColor)
    }

    func testNonHexCharactersAreNil() {
        XCTAssertNil(makeProject(hexColor: "GGGGGG").normalizedHexColor)
        XCTAssertNil(makeProject(hexColor: "12 34 56").normalizedHexColor)
    }

    private func makeProject(hexColor: String?) -> Project {
        Project(id: 1, title: "Work", hexColor: hexColor, isArchived: false, isFavorite: false)
    }
}
