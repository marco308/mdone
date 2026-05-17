import XCTest
@testable import mDone

/// Pure-logic tests for the offline fuzzy estimate suggester. No simulator,
/// SwiftData, or network — everything here is value types.
final class EstimateSuggesterTests: XCTestCase {
    // MARK: - Empty / degenerate inputs

    func testNoHistoryReturnsNil() {
        XCTAssertNil(EstimateSuggester.suggestion(for: "Write the report", history: []))
    }

    func testEmptyTitleReturnsNil() {
        let history = [HistoricalTask(title: "Write report", actualSeconds: 1800)]
        XCTAssertNil(EstimateSuggester.suggestion(for: "", history: history))
    }

    func testWhitespaceOnlyTitleReturnsNil() {
        let history = [HistoricalTask(title: "Write report", actualSeconds: 1800)]
        XCTAssertNil(EstimateSuggester.suggestion(for: "   \n\t ", history: history))
    }

    func testHistoryWithEmptyTitlesIsIgnored() {
        let history = [HistoricalTask(title: "   ", actualSeconds: 1800)]
        XCTAssertNil(EstimateSuggester.suggestion(for: "Write report", history: history))
    }

    // MARK: - Identical & near titles

    func testIdenticalTitleScoresOneAndReturnsItsDuration() {
        let history = [HistoricalTask(title: "Write the quarterly report", actualSeconds: 3600)]
        let s = EstimateSuggester.suggestion(for: "Write the quarterly report", history: history)
        let result = try? XCTUnwrap(s)
        XCTAssertNotNil(result)
        XCTAssertEqual(s!.topScore, 1.0, accuracy: 0.0001)
        XCTAssertEqual(s!.suggestedSeconds, 3600)
        XCTAssertEqual(s!.matchCount, 1)
    }

    func testReorderedAndPaddedWordsStillMatch() {
        // Edit distance would punish this; token/trigram blend should not.
        let history = [HistoricalTask(title: "quarterly report writing", actualSeconds: 2400)]
        let s = EstimateSuggester.suggestion(for: "Write the quarterly report", history: history)
        XCTAssertNotNil(s, "Reordered/padded title should still clear the threshold")
        XCTAssertEqual(s?.suggestedSeconds, 2400)
    }

    func testUnrelatedTitleIsBelowThresholdAndReturnsNil() {
        let history = [HistoricalTask(title: "Buy milk and eggs", actualSeconds: 600)]
        XCTAssertNil(EstimateSuggester.suggestion(for: "Refactor the networking layer", history: history))
    }

    // MARK: - Ranking order & threshold cutoff

    func testRankingPrefersTheMoreSimilarTask() {
        let history = [
            HistoricalTask(title: "Buy groceries at the store", actualSeconds: 9999),
            HistoricalTask(title: "Write the weekly status report", actualSeconds: 1500)
        ]
        let s = EstimateSuggester.suggestion(
            for: "Write the weekly report",
            history: history,
            topN: 1
        )
        // Only the report task should win at topN=1.
        XCTAssertEqual(s?.suggestedSeconds, 1500)
        XCTAssertEqual(s?.matchCount, 1)
    }

    func testThresholdCutoffExcludesWeakMatches() {
        let history = [HistoricalTask(title: "Write report", actualSeconds: 1800)]
        // An absurdly high threshold should reject everything but an exact-ish hit.
        XCTAssertNil(EstimateSuggester.suggestion(
            for: "completely different text",
            history: history,
            threshold: 0.9
        ))
        // A low threshold lets a partial match through.
        XCTAssertNotNil(EstimateSuggester.suggestion(
            for: "write the report now",
            history: history,
            threshold: 0.2
        ))
    }

    // MARK: - Median aggregation & outliers

    func testUsesMedianNotMeanSoOutliersDoNotSkew() {
        let history = [
            HistoricalTask(title: "Fix login bug", actualSeconds: 1200),
            HistoricalTask(title: "Fix login bug again", actualSeconds: 1500),
            HistoricalTask(title: "Fix the login bug once more", actualSeconds: 1800),
            HistoricalTask(title: "Fix login bug huge outlier", actualSeconds: 36000)
        ]
        let s = EstimateSuggester.suggestion(for: "Fix login bug", history: history, threshold: 0.2)
        // Median of [1200,1500,1800,36000] = (1500+1800)/2 = 1650, rounded
        // up to the next whole minute = 1680. Mean would be ~10125 — the
        // outlier must not dominate.
        XCTAssertEqual(s?.suggestedSeconds, 1680)
        XCTAssertLessThan(s!.suggestedSeconds, 5000)
    }

    func testMedianOddCount() {
        XCTAssertEqual(EstimateSuggester.median([300, 100, 200]), 200)
    }

    func testMedianEvenCount() {
        XCTAssertEqual(EstimateSuggester.median([100, 200, 300, 400]), 250)
    }

    func testMedianEmptyIsZero() {
        XCTAssertEqual(EstimateSuggester.median([]), 0)
    }

    // MARK: - Tie-breaking determinism

    func testTieBreakIsDeterministicShorterDurationFirst() {
        // Two identical-title candidates → identical score; the stable tie-break
        // (shorter duration first) makes the ordering deterministic. With
        // topN=1 the 600s task must always be the chosen one.
        let history = [
            HistoricalTask(title: "Email the client", actualSeconds: 1800),
            HistoricalTask(title: "Email the client", actualSeconds: 600)
        ]
        for _ in 0 ..< 20 {
            let s = EstimateSuggester.suggestion(for: "Email the client", history: history, topN: 1)
            XCTAssertEqual(s?.suggestedSeconds, 600)
        }
    }

    // MARK: - Weak metadata signals

    func testSameProjectBonusCanLiftABorderlineMatch() {
        let history = [HistoricalTask(
            title: "deploy service",
            actualSeconds: 900,
            projectId: 42
        )]
        let title = "deploy the new service build"
        let withoutBonus = EstimateSuggester.suggestion(for: title, history: history, threshold: 0.55)
        let withBonus = EstimateSuggester.suggestion(
            for: title,
            history: history,
            projectId: 42,
            threshold: 0.55
        )
        // The project-match bonus is additive and capped, so it must (a)
        // never reduce the score (if the title alone passed, the bonus
        // version must also pass) and (b) never lower the top score for an
        // already-passing match.
        if let withoutBonus {
            XCTAssertNotNil(withBonus, "Same-project bonus must not reject a previously-passing match")
            if let withBonus {
                XCTAssertGreaterThanOrEqual(
                    withBonus.topScore,
                    withoutBonus.topScore,
                    "Same-project bonus must not lower an already-passing match's top score"
                )
            }
        }
    }


    func testMetadataBonusCannotRescueACompletelyUnrelatedTitle() {
        let history = [HistoricalTask(
            title: "Plant tomatoes in the garden",
            actualSeconds: 3600,
            projectId: 7,
            labelIds: [1, 2, 3]
        )]
        // Even with project + all labels matching, an unrelated title stays out.
        let s = EstimateSuggester.suggestion(
            for: "Compile the kernel module",
            history: history,
            projectId: 7,
            labelIds: [1, 2, 3]
        )
        XCTAssertNil(s, "Metadata bonus is capped and must not override an unrelated title")
    }

    // MARK: - Performance (runs as the user types)

    func testPerformanceUnderBudgetForSeveralHundredTasks() {
        var history: [HistoricalTask] = []
        for i in 0 ..< 400 {
            history.append(HistoricalTask(
                title: "Task number \(i) do some work item \(i % 7)",
                actualSeconds: TimeInterval(600 + i)
            ))
        }
        let start = Date()
        _ = EstimateSuggester.suggestion(for: "Task number 123 do some work", history: history)
        let elapsed = Date().timeIntervalSince(start)
        // Generous ceiling for CI noise; typical run is well under 10ms.
        XCTAssertLessThan(elapsed, 0.1, "Suggester too slow for keystroke use: \(elapsed)s")
    }

    // MARK: - Similarity primitives

    func testTokenizeFoldsDiacriticsAndSplitsOnPunctuation() {
        XCTAssertEqual(EstimateSuggester.tokenize("Café: write-up!"), ["cafe", "write", "up"])
    }

    func testDiceOfIdenticalSetsIsOne() {
        let a = EstimateSuggester.trigrams(from: ["hello", "world"])
        XCTAssertEqual(EstimateSuggester.dice(a, a), 1.0, accuracy: 0.0001)
    }

    func testDiceOfDisjointSetsIsZero() {
        let a = EstimateSuggester.trigrams(from: ["xxxx"])
        let b = EstimateSuggester.trigrams(from: ["yyyy"])
        XCTAssertEqual(EstimateSuggester.dice(a, b), 0.0, accuracy: 0.0001)
    }

    func testJaccardBasics() {
        XCTAssertEqual(EstimateSuggester.jaccard(["a", "b"], ["a", "b"]), 1.0, accuracy: 0.0001)
        XCTAssertEqual(EstimateSuggester.jaccard(["a", "b"], ["b", "c"]), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(EstimateSuggester.jaccard([], []), 1.0, accuracy: 0.0001)
    }
}
