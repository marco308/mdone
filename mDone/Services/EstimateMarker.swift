import Foundation

/// Read / write / strip the mDone estimate marker inside a Vikunja task
/// description.
///
/// **Wire format:** `<!-- mdone:estimate=NNN -->` where NNN is the estimated
/// duration in whole seconds (>0). The marker is appended as the trailing
/// segment of the description, separated from any body text by a blank line.
/// HTML comments survive Vikunja's storage path (Vikunja stores descriptions as
/// raw `longtext`; its bluemonday sanitiser is only used on outbound email
/// notifications) and survive every existing client renderer, since
/// NSAttributedString-based HTML parsing and Markdown renderers both treat
/// `<!-- ... -->` as a non-visible token.
///
/// **Agent contract:** any client (mDone, an LLM agent, a script) can set or
/// read a task's estimated duration by emitting/parsing this marker against
/// the standard Vikunja description field. No proprietary endpoint, no custom
/// field, no label namespace.
enum EstimateMarker {
    /// Matches one marker and any whitespace immediately surrounding it,
    /// so `strip` cleans up the blank line we insert on `apply` without
    /// touching user-intentional whitespace elsewhere in the body. The
    /// capture group is the integer seconds. Tolerates surrounding
    /// whitespace inside the comment but `mdone:estimate=` is exact
    /// (case-sensitive) so we don't collide with other tools' markers.
    static let pattern = #"\s*<!--\s*mdone:estimate=(\d+)\s*-->\s*"#

    /// Pre-compiled regex reused on every call so we don't re-parse the
    /// pattern per task render. `try?` matches `RichTextRenderer`'s style
    /// and keeps SwiftLint happy; a `nil` here would mean the literal
    /// pattern is malformed, which the marker test suite catches.
    private static let regex = try? NSRegularExpression(pattern: pattern)

    /// Extract the estimated duration (seconds) from a description, or `nil`
    /// if absent / malformed. First match wins if a description somehow
    /// contains more than one marker — `apply` deduplicates on write.
    static func parse(_ description: String?) -> TimeInterval? {
        guard let description, !description.isEmpty, let regex else { return nil }
        let range = NSRange(description.startIndex..., in: description)
        guard let match = regex.firstMatch(in: description, range: range),
              match.numberOfRanges >= 2,
              let group = Range(match.range(at: 1), in: description),
              let seconds = TimeInterval(description[group]),
              seconds > 0
        else { return nil }
        return seconds
    }

    /// The description with the marker(s) and the whitespace immediately
    /// around them removed. User-intentional whitespace elsewhere in the
    /// body (leading indentation, deliberate blank lines between paragraphs)
    /// is preserved. Returns `nil` for an empty / whitespace-only body so
    /// callers can treat "marker-only" descriptions as "no body".
    static func strip(_ description: String?) -> String? {
        guard let description else { return nil }
        let source: String
        if let regex {
            let range = NSRange(description.startIndex..., in: description)
            source = regex.stringByReplacingMatches(in: description, range: range, withTemplate: "")
        } else {
            source = description
        }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return source
    }

    /// Compose a wire description from a visible body and an estimate.
    ///
    /// - Existing markers in `body` are stripped first so this is idempotent.
    /// - A non-positive estimate is treated as "no estimate" and emits only
    ///   the stripped body (or `nil` if the body is empty).
    /// - With both body and estimate, the marker is appended after a blank
    ///   line for readability in any client that does show raw description.
    static func apply(_ estimate: TimeInterval?, to body: String?) -> String? {
        let cleanBody = strip(body)
        guard let estimate, estimate > 0 else { return cleanBody }
        // Clamp to >= 1 so a tiny positive (e.g. 0.4s) doesn't round to 0,
        // which `parse` would then reject — breaking the round-trip.
        let seconds = max(1, Int(estimate.rounded()))
        let marker = "<!-- mdone:estimate=\(seconds) -->"
        if let cleanBody, !cleanBody.isEmpty {
            return "\(cleanBody)\n\n\(marker)"
        }
        return marker
    }
}
