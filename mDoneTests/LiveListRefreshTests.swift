import XCTest
@testable import mDone

/// The coordinator behind live list refresh (#241): when a quiet read may
/// apply, and when it must be thrown away.
@MainActor
final class LiveListRefreshTests: XCTestCase {
    func testExternalChangesReplaceRowsAndCanEmptyTheList() async {
        let refresh = LiveListRefresh()
        var rows = [1]
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [2, 3] }, apply: { rows = $0
            return true
        })
        XCTAssertEqual(rows, [2, 3])
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [Int]() }, apply: { rows = $0
            return true
        })
        XCTAssertTrue(rows.isEmpty)
    }

    func testDisabledListDoesNotFetch() async {
        let refresh = LiveListRefresh()
        var fetched = false
        let outcome = await refresh.refresh(
            isEnabled: { false }, revision: { 0 }, fetch: { fetched = true }, apply: { _ in true }
        )
        XCTAssertFalse(fetched)
        XCTAssertEqual(outcome, .skipped)
    }

    func testLocalChangeWhileFetchingDropsTheResponse() async {
        let refresh = LiveListRefresh()
        var revision: UInt64 = 0
        var title = "Original"
        await refresh.refresh(isEnabled: { true }, revision: { revision }, fetch: {
            title = "Saved locally"
            revision += 1
            return "Older server snapshot"
        }, apply: { title = $0
            return true
        })
        XCTAssertEqual(title, "Saved locally")
    }

    func testBecomingDisabledWhileFetchingKeepsTheRows() async {
        let refresh = LiveListRefresh()
        var enabled = true
        var rows = [1]
        await refresh.refresh(isEnabled: { enabled }, revision: { 0 }, fetch: {
            enabled = false
            return [2]
        }, apply: { rows = $0
            return true
        })
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
            }, apply: { rows = $0
                return true
            })
            return [1]
        }, apply: { rows = $0
            return true
        })
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(rows, [1])
    }

    func testFailureKeepsRowsAndTheNextTickRecovers() async {
        let refresh = LiveListRefresh()
        var rows = [1]
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { () throws -> [Int] in
            throw URLError(.notConnectedToInternet)
        }, apply: { rows = $0
            return true
        })
        XCTAssertEqual(rows, [1])
        await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [2] }, apply: { rows = $0
            return true
        })
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
            }, apply: { rows = $0
                return true
            })
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
        await LiveListRefresh.poll(pace: { .foreground }, sleep: { _ in
            waits += 1
            if waits == 3 {
                throw CancellationError()
            }
        }, refresh: {
            refreshes += 1
            return .unchanged
        })
        XCTAssertEqual(refreshes, 2)
    }

    // MARK: - Outcomes

    func testOutcomeSaysWhetherAnythingChanged() async {
        let refresh = LiveListRefresh()
        let nothingToDownload = await refresh.refresh(
            isEnabled: { true },
            revision: { 0 },
            fetch: { [Int]?.none },
            apply: { _ in
                XCTFail("A nil fetch has nothing to apply")
                return true
            }
        )
        XCTAssertEqual(nothingToDownload, .unchanged)
        let sameRows = await refresh.refresh(
            isEnabled: { true },
            revision: { 0 },
            fetch: { [1] },
            apply: { _ in false }
        )
        XCTAssertEqual(sameRows, .unchanged)
        let newRows = await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { [2] }, apply: { _ in true })
        XCTAssertEqual(newRows, .changed)
        let failed = await refresh.refresh(isEnabled: { true }, revision: { 0 }, fetch: { () throws -> [Int]? in
            throw URLError(.timedOut)
        }, apply: { _ in true })
        XCTAssertEqual(failed, .skipped)
    }

    // MARK: - Backoff

    func testQuietTicksBackOffToTheMaximumAndAChangeSnapsBack() {
        var schedule = LivePollSchedule(pace: .foreground)
        var waits = [schedule.interval]
        for _ in 0 ..< 5 {
            schedule.record(.unchanged, pace: .foreground)
            waits.append(schedule.interval)
        }
        XCTAssertEqual(waits, [15, 30, 60, 120, 120, 120].map(Duration.seconds))

        schedule.record(.changed, pace: .foreground)
        XCTAssertEqual(schedule.interval, .seconds(15))
    }

    func testSkippedTickKeepsTheCurrentWait() {
        var schedule = LivePollSchedule(pace: .foreground)
        schedule.record(.unchanged, pace: .foreground)
        schedule.record(.skipped, pace: .foreground)
        XCTAssertEqual(schedule.interval, .seconds(30))
    }

    /// Low Power Mode or a cellular network arriving mid-loop takes effect
    /// on the next tick, and leaving it lets the loop speed up again.
    func testPaceChangeMidLoopClampsTheWait() {
        var schedule = LivePollSchedule(pace: .foreground)
        schedule.record(.unchanged, pace: .foregroundConstrained)
        XCTAssertEqual(schedule.interval, .seconds(60))
        for _ in 0 ..< 4 {
            schedule.record(.unchanged, pace: .foregroundConstrained)
        }
        XCTAssertEqual(schedule.interval, .seconds(300))
        schedule.record(.unchanged, pace: .foreground)
        XCTAssertEqual(schedule.interval, .seconds(120))
        schedule.record(.changed, pace: .foreground)
        XCTAssertEqual(schedule.interval, .seconds(15))
    }

    func testPaceIsSlowerBehindOtherAppsAndWhenConstrained() {
        XCTAssertEqual(LivePollPace.current(inFront: true, constrained: false), .foreground)
        XCTAssertEqual(LivePollPace.current(inFront: true, constrained: true), .foregroundConstrained)
        XCTAssertEqual(LivePollPace.current(inFront: false, constrained: false), .behind)
        XCTAssertEqual(LivePollPace.current(inFront: false, constrained: true), .behindConstrained)
        let paces: [LivePollPace] = [.foreground, .foregroundConstrained, .behind, .behindConstrained]
        for pair in zip(paces, paces.dropFirst()) {
            XCTAssertLessThan(pair.0.minimum, pair.1.minimum)
            XCTAssertLessThan(pair.0.maximum, pair.1.maximum)
        }
    }

    /// Cellular, a hotspot or Low Data Mode each count as constrained. The
    /// unconstrained answer is not asserted: it also depends on whether the
    /// host happens to be in Low Power Mode.
    func testExpensiveOrConstrainedNetworkSlowsThePace() {
        let network = NetworkMonitor(stubbedConnection: true)
        network.isExpensive = true
        XCTAssertTrue(LivePollPace.isConstrained(network: network))
        network.isExpensive = false
        network.isConstrained = true
        XCTAssertTrue(LivePollPace.isConstrained(network: network))
    }

    func testPollWaitsLongerAfterEachQuietTick() async {
        var waits: [Duration] = []
        var outcomes: [LiveRefreshOutcome] = [.unchanged, .unchanged, .changed, .unchanged]
        await LiveListRefresh.poll(pace: { .foreground }, sleep: { wait in
            waits.append(wait)
            if outcomes.isEmpty {
                throw CancellationError()
            }
        }, refresh: { outcomes.removeFirst() })
        XCTAssertEqual(waits, [15, 30, 60, 15, 30].map(Duration.seconds))
    }
}
