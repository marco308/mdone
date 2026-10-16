import XCTest
@testable import mDone

/// The coordinator behind live list refresh (#241): when a quiet read may
/// apply, and when it must be thrown away.
@MainActor
final class LiveListRefreshTests: XCTestCase {
    func testExternalChangesReplaceRowsAndCanEmptyTheList() async {
        let refresh = LiveListRefresh()
        var rows = [1]
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [2, 3] }, apply: { rows = $0 })
        XCTAssertEqual(rows, [2, 3])
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [Int]() }, apply: { rows = $0 })
        XCTAssertTrue(rows.isEmpty)
    }

    func testDisabledListDoesNotFetch() async {
        let refresh = LiveListRefresh()
        var fetched = false
        await refresh.refresh(isEnabled: { false }, revision: { 0 }, fetch: { fetched = true }, apply: { _ in })
        XCTAssertFalse(fetched)
    }

    func testLocalChangeWhileFetchingDropsTheResponse() async {
        let refresh = LiveListRefresh()
        var revision: UInt64 = 0
        var title = "Original"
        await refresh.refresh(isEnabled: { true }, revision: { revision }, fetch: {
            title = "Saved locally"
            revision += 1
            return "Older server snapshot"
        }, apply: { title = $0 })
        XCTAssertEqual(title, "Saved locally")
    }

    func testBecomingDisabledWhileFetchingKeepsTheRows() async {
        let refresh = LiveListRefresh()
        var enabled = true
        var rows = [1]
        await refresh.refresh(isEnabled: { enabled }, revision: { 0 }, fetch: {
            enabled = false
            return [2]
        }, apply: { rows = $0 })
        XCTAssertEqual(rows, [1])
    }

    func testOverlappingRefreshIsSkipped() async {
        let refresh = LiveListRefresh()
        var requests = 0
        var rows = [Int]()
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: {
            requests += 1
            await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: {
                requests += 1
                return [99]
            }, apply: { rows = $0 })
            return [1]
        }, apply: { rows = $0 })
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(rows, [1])
    }

    func testFailureKeepsRowsAndTheNextTickRecovers() async {
        let refresh = LiveListRefresh()
        var rows = [1]
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { () throws -> [Int] in
            throw URLError(.notConnectedToInternet)
        }, apply: { rows = $0 })
        XCTAssertEqual(rows, [1])
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [2] }, apply: { rows = $0 })
        XCTAssertEqual(rows, [2])
    }

    func testCancelledListCannotApplyItsResponse() async {
        let refresh = LiveListRefresh()
        var rows = [1]
        let reachedFetch = expectation(description: "Read started")
        var resumeFetch: CheckedContinuation<Void, Never>?
        let request = Task {
            await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: {
                await withCheckedContinuation { continuation in
                    resumeFetch = continuation
                    reachedFetch.fulfill()
                }
                return [2]
            }, apply: { rows = $0 })
        }
        await fulfillment(of: [reachedFetch], timeout: 2)
        request.cancel()
        resumeFetch?.resume()
        await request.value
        XCTAssertEqual(rows, [1])
    }

    func testPollingStopsWhenItsWaitIsCancelled() async {
        var waits = 0
        var refreshes = 0
        await LiveListRefresh.poll(wait: {
            waits += 1
            if waits == 3 {
                throw CancellationError()
            }
        }, refresh: { refreshes += 1 })
        XCTAssertEqual(refreshes, 2)
    }
}
