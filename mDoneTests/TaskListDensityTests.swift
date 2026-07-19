import SwiftUI
import XCTest
@testable import mDone

final class TaskListDensityTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "TaskListDensityTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCurrentFallsBackToStandardWhenUnset() {
        XCTAssertEqual(TaskListDensity.current(defaults: defaults), .standard)
    }

    func testCurrentRespectsStoredValue() {
        for density in TaskListDensity.allCases {
            defaults.set(density.rawValue, forKey: TaskListDensity.storageKey)
            XCTAssertEqual(TaskListDensity.current(defaults: defaults), density)
        }
    }

    func testCurrentFallsBackWhenStoredValueIsCorrupted() {
        // A leftover value from a renamed case, or a hand-edited defaults
        // plist, must fall back to the default rather than crash.
        defaults.set("tiny", forKey: TaskListDensity.storageKey)
        XCTAssertEqual(TaskListDensity.current(defaults: defaults), .standard)

        defaults.set(42, forKey: TaskListDensity.storageKey)
        XCTAssertEqual(TaskListDensity.current(defaults: defaults), .standard)
    }

    func testRawValuesMatchWidgetFontSizeOptions() {
        // The widgets offer the same Compact / Standard / Large choice via
        // WidgetFontSize (mDoneWidgets/AppIntents.swift). Keep the raw values
        // aligned so the two settings stay conceptually interchangeable.
        XCTAssertEqual(TaskListDensity.compact.rawValue, "compact")
        XCTAssertEqual(TaskListDensity.standard.rawValue, "standard")
        XCTAssertEqual(TaskListDensity.large.rawValue, "large")
    }

    func testStandardKeepsTheOriginalRowMetrics() {
        // Standard must stay pixel-identical to the row before this setting
        // existed: users who never touch the picker see no change (#122).
        let standard = TaskListDensity.standard
        XCTAssertEqual(standard.titleFont, .body)
        XCTAssertEqual(standard.metadataFont, .caption)
        XCTAssertEqual(standard.checkboxFont, .title3)
        XCTAssertEqual(standard.accentBarHeight, 36)
        XCTAssertEqual(standard.rowVerticalPadding, 4)
        XCTAssertEqual(standard.contentSpacing, 4)
        XCTAssertEqual(standard.titleLineLimit, 2)
    }

    func testNumericMetricsScaleWithDensity() {
        let compact = TaskListDensity.compact
        let standard = TaskListDensity.standard
        let large = TaskListDensity.large

        XCTAssertLessThan(compact.accentBarHeight, standard.accentBarHeight)
        XCTAssertLessThan(standard.accentBarHeight, large.accentBarHeight)

        XCTAssertLessThan(compact.rowVerticalPadding, standard.rowVerticalPadding)
        XCTAssertLessThan(standard.rowVerticalPadding, large.rowVerticalPadding)

        XCTAssertLessThan(compact.contentSpacing, standard.contentSpacing)
        XCTAssertLessThan(standard.contentSpacing, large.contentSpacing)

        XCTAssertLessThanOrEqual(compact.titleLineLimit, standard.titleLineLimit)
        XCTAssertLessThanOrEqual(standard.titleLineLimit, large.titleLineLimit)
    }

    func testLabels() {
        XCTAssertEqual(TaskListDensity.compact.label, "Compact")
        XCTAssertEqual(TaskListDensity.standard.label, "Standard")
        XCTAssertEqual(TaskListDensity.large.label, "Large")
    }
}
