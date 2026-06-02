#if os(iOS)
import SwiftUI
import XCTest
@testable import mDone

/// Marketing-screenshot generator for the Focus Timer screen.
///
/// This is NOT a behavioural test: it renders `FocusSessionView` to a PNG via
/// `ImageRenderer` using mock data, so the website can show a real screenshot of
/// the focus screen without a live server.
///
/// It self-disables outside the dev worktree: the guard checks that the source
/// file lives under `.claude/worktrees/`, so a normal checkout (and CI) skips it
/// and never rewrites the asset. Run it here with:
///   xcodebuild test -project mDone.xcodeproj -scheme mDone -sdk iphonesimulator \
///     -destination 'platform=iOS Simulator,name=iPhone 16e' \
///     -only-testing:mDoneTests/FocusShotRenderTests
@MainActor
final class FocusShotRenderTests: XCTestCase {
    /// Repo root derived from this file's compile-time path (…/mDoneTests/<this>).
    private var repoRoot: URL {
        URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testRenderFocusScreen() throws {
        try XCTSkipUnless(
            #file.contains("/.claude/worktrees/"),
            "Screenshot generator — only runs from the dev worktree."
        )

        // Mock an in-progress focus session on a task that matches the demo data
        // shown in the site's Inbox screenshot.
        let focusManager = FocusManager()
        focusManager.currentSession = FocusSession(
            taskId: 1,
            taskTitle: "Finalize Q1 report",
            projectName: "Work",
            priorityLevel: 4,
            sessionStartDate: Date(timeIntervalSinceNow: -1500),
            focusIntervalStartDate: Date(timeIntervalSinceNow: -1500), // ~25:00 elapsed
            elapsedBeforePause: 0,
            isPaused: false,
            activityId: nil
        )

        // The view's own background is a gradient ending in a near-transparent
        // colour; in the real app it sits over the white system background, so
        // give it an opaque white backing here (otherwise transparent regions
        // composite over black).
        let view = FocusSessionView()
            .environment(focusManager)
            .environment(AppState())
            .frame(width: 393, height: 852)
            .background(Color.white)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.isOpaque = true

        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("ImageRenderer produced no image")
            return
        }

        let url = repoRoot.appendingPathComponent("website/assets/shot-focus.png")
        try data.write(to: url)
        print("[render] wrote \(Int(image.size.width))x\(Int(image.size.height)) -> \(url.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
#endif
