import Foundation

/// A previously-completed task with recorded focus time, distilled to the only
/// fields the suggester needs. Pure value type — built from `FocusRecord` rows
/// at the call site so the matching logic stays DB- and UI-free and is fully
/// unit-testable.
struct HistoricalTask: Equatable {
    let title: String
    /// Actual focused seconds for this task (sum of its `FocusRecord` sessions).
    let actualSeconds: TimeInterval
    let projectId: Int64?
    let labelIds: [Int64]

    init(title: String, actualSeconds: TimeInterval, projectId: Int64? = nil, labelIds: [Int64] = []) {
        self.title = title
        self.actualSeconds = actualSeconds
        self.projectId = projectId
        self.labelIds = labelIds
    }
}

/// The suggester's answer: a robust estimate plus the supporting evidence so
/// the UI can show "Similar tasks took ~25m" and decide how confident to be.
struct EstimateSuggestion: Equatable {
    /// Median of the actual focused time of the matched tasks (seconds).
    let suggestedSeconds: TimeInterval
    /// How many historical tasks cleared the similarity threshold.
    let matchCount: Int
    /// Similarity score (0...1) of the single best match — used as a
    /// confidence signal by the caller.
    let topScore: Double
}

/// Deterministic, offline, pure-Swift fuzzy estimate suggester.
///
/// ## Algorithm: Sørensen–Dice coefficient over character trigrams, blended
/// with a Jaccard token-set ratio.
///
/// Why this and not the alternatives:
/// - **Levenshtein / Jaro-Winkler** are edit-distance metrics tuned for typos
///   in short strings. Task titles are *bags of words* ("Write Q3 report" vs
///   "Q3 report writing") where word order and small extra words shouldn't
///   tank the score. Edit distance punishes reordering harshly.
/// - **Embeddings / AI** are explicitly out of scope (no network, no models).
/// - **Trigram Dice** is order-insensitive enough (it shingles characters,
///   not whole strings), language-agnostic, needs no dictionary, and is O(n)
///   to build a set + O(min) to intersect — trivially under the ~10ms budget
///   for a few hundred history rows. We additionally blend in a **token-set
///   Jaccard** (word-level overlap) so that strong whole-word matches aren't
///   diluted by trigram noise from unrelated long words. The final score is a
///   weighted mean of the two (trigram-weighted, since it degrades more
///   gracefully on near-misses and inflections like "report"/"reports").
///
/// Weak signals: a small bonus is added when the project id matches and per
/// shared label, capped, so a same-project task with a so-so title still
/// surfaces, without letting metadata override a clearly-unrelated title.
///
/// The suggested duration is the **median** (not mean) of the matched tasks'
/// actual focused time — a single 4-hour outlier shouldn't drag a "usually
/// 20 minutes" estimate upward.
enum EstimateSuggester {
    /// Default similarity floor. Tuned empirically: trigram Dice on short,
    /// related titles ("write report" vs "write the report") lands ~0.45–0.7;
    /// unrelated titles sit well below 0.35.
    static let defaultThreshold: Double = 0.35

    /// Default number of top matches whose actual times feed the median.
    static let defaultTopN: Int = 7

    // Score blend weights (sum to 1).
    private static let trigramWeight = 0.65
    private static let tokenWeight = 0.35

    // Weak-signal bonuses, added post-blend and clamped to <= 1.
    private static let sameProjectBonus = 0.05
    private static let perLabelBonus = 0.03
    private static let maxMetadataBonus = 0.11

    /// Produce an estimate from the most similar completed tasks, or `nil` when
    /// nothing clears the threshold (caller shows no hint — there is no empty
    /// state by design).
    ///
    /// - Parameters:
    ///   - title: the in-progress task title the user is typing.
    ///   - history: completed tasks that have recorded focus time.
    ///   - projectId / labelIds: optional weak signals about the new task.
    ///   - threshold: minimum blended similarity (0...1) to count as a match.
    ///   - topN: at most this many best matches feed the median.
    static func suggestion(
        for title: String,
        history: [HistoricalTask],
        projectId: Int64? = nil,
        labelIds: [Int64] = [],
        threshold: Double = defaultThreshold,
        topN: Int = defaultTopN
    ) -> EstimateSuggestion? {
        // A caller passing `topN <= 0` would otherwise land us at
        // `prefix(0)` → empty top → `median([])` → a nonsensical
        // 0-second "suggestion". Clamp instead so the call still
        // produces a usable answer with a single best match.
        let effectiveTopN = max(1, topN)
        let queryTokens = tokenize(title)
        guard !queryTokens.isEmpty, !history.isEmpty else { return nil }
        let queryTrigrams = trigrams(from: queryTokens)
        // Hoist the query token set out of the loop — it's invariant per
        // suggestion call and otherwise gets rebuilt for every candidate.
        let queryTokenSet = Set(queryTokens)

        // Score every candidate, keep those above threshold.
        var scored: [(score: Double, seconds: TimeInterval)] = []
        scored.reserveCapacity(history.count)
        for task in history {
            let candTokens = tokenize(task.title)
            if candTokens.isEmpty {
                continue
            }
            let tri = dice(queryTrigrams, trigrams(from: candTokens))
            let tok = jaccard(queryTokenSet, Set(candTokens))
            var score = trigramWeight * tri + tokenWeight * tok

            // Weak metadata signals — additive, capped, never decisive.
            var bonus = 0.0
            if let p = projectId, let cp = task.projectId, p == cp {
                bonus += sameProjectBonus
            }
            if !labelIds.isEmpty, !task.labelIds.isEmpty {
                let shared = Set(labelIds).intersection(task.labelIds).count
                bonus += Double(shared) * perLabelBonus
            }
            score = min(1.0, score + min(bonus, maxMetadataBonus))

            if score >= threshold {
                scored.append((score, task.actualSeconds))
            }
        }

        guard !scored.isEmpty else { return nil }

        // Deterministic ordering: score desc, then shorter duration first as a
        // stable tie-break so identical inputs always yield the same answer.
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.seconds < rhs.seconds
        }

        let top = Array(scored.prefix(effectiveTopN))
        // Round the median up to the next whole minute so the suggestion
        // aligns with the UI's minute-granular formatter (and the custom
        // picker's 5-minute wheel after we round again on edit). A small
        // bias upward avoids "<1m" leaking into the hint when a few sub-
        // minute focus blips dominate the median.
        let suggested = (median(top.map(\.seconds)) / 60).rounded(.up) * 60
        return EstimateSuggestion(
            suggestedSeconds: suggested,
            matchCount: top.count,
            topScore: top.first?.score ?? 0
        )
    }

    // MARK: - String similarity primitives (pure, no dependencies)

    /// Lowercase, split on non-alphanumerics, drop empties. Diacritics are
    /// folded so "café" and "cafe" match.
    static func tokenize(_ s: String) -> [String] {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Character trigrams of the tokens joined by a space, padded so short
    /// tokens still produce shingles. Set-valued (membership, not multiset) —
    /// adequate for title similarity and keeps Dice symmetric and cheap.
    static func trigrams(from tokens: [String]) -> Set<String> {
        let joined = " " + tokens.joined(separator: " ") + " "
        let chars = Array(joined)
        guard chars.count >= 3 else { return chars.isEmpty ? [] : [String(chars)] }
        var set = Set<String>()
        set.reserveCapacity(chars.count)
        for i in 0 ... (chars.count - 3) {
            set.insert(String(chars[i ..< i + 3]))
        }
        return set
    }

    /// Sørensen–Dice coefficient: 2·|A∩B| / (|A|+|B|). 1 == identical sets.
    static func dice(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty, b.isEmpty {
            return 1
        }
        if a.isEmpty || b.isEmpty {
            return 0
        }
        let inter = a.intersection(b).count
        return (2.0 * Double(inter)) / Double(a.count + b.count)
    }

    /// Jaccard index over token sets: |A∩B| / |A∪B|.
    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty, b.isEmpty {
            return 1
        }
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }

    /// Median of a value list. Even count averages the two middle values.
    /// Empty list → 0 (callers guard against empty before relying on this).
    static func median(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
