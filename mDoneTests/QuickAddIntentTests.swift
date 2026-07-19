import AppIntents
import XCTest
@testable import mDone

@MainActor
final class QuickAddIntentTests: XCTestCase {
    func testPerformSetsQuickAddTriggerOnSharedAppState() async throws {
        let state = AppState()
        state.quickAddTrigger = nil
        XCTAssertTrue(AppState.shared === state, "AppState.init should register itself as shared")

        _ = try await QuickAddIntent().perform()

        XCTAssertNotNil(state.quickAddTrigger, "Running the intent should raise the quick-add trigger")
    }

    func testPerformWithoutSharedStateDoesNotThrow() async throws {
        AppState.shared = nil

        _ = try await QuickAddIntent().perform()
    }
}
