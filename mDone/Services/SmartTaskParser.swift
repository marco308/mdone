import Foundation

/// What the smart quick-add parser pulled out of a line of text (#215, #224).
///
/// Every extracted field keeps the text range it consumed, so the UI can strip
/// it from the title and, when the user rejects a chip, put it back with
/// `rejecting(_:)`.
struct SmartTaskParse: Equatable {
    enum Field: Hashable {
        case dueDate
        case project
        case priority
        case label(Int64)
    }

    /// One accepted parse and the text it came from. A due date can span
    /// several ranges ("friday ... at 3pm"), the other fields span one.
    struct Match: Equatable {
        let field: Field
        let ranges: [Range<String.Index>]
    }

    /// The raw input, untouched.
    let text: String
    let dueDate: Date?
    /// True when the text named a time ("at 5pm", "tonight"). False when the
    /// date is date-only and carries the default due time.
    let dueDateHasTime: Bool
    let projectId: Int64?
    let priority: Int?
    let labelIds: [Int64]
    let matches: [Match]

    /// The text with every accepted match removed and whitespace collapsed.
    /// When stripping would leave nothing ("tomorrow"), the raw text is kept
    /// so the task still gets a title; the parsed fields still apply.
    var title: String {
        let trimmedRaw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !matches.isEmpty else { return trimmedRaw }
        let consumed = matches.flatMap(\.ranges).sorted { $0.lowerBound < $1.lowerBound }
        var kept = ""
        var cursor = text.startIndex
        for range in consumed where range.lowerBound >= cursor {
            kept += text[cursor ..< range.lowerBound]
            kept += " "
            cursor = range.upperBound
        }
        kept += text[cursor...]
        let stripped = Self.collapsingWhitespace(kept)
        return stripped.isEmpty ? Self.collapsingWhitespace(trimmedRaw) : stripped
    }

    func ranges(for field: Field) -> [Range<String.Index>] {
        matches.first { $0.field == field }?.ranges ?? []
    }

    /// The same parse with the given fields dropped: their values are cleared
    /// and their words go back into the title.
    func rejecting(_ fields: Set<Field>) -> SmartTaskParse {
        SmartTaskParse(
            text: text,
            dueDate: fields.contains(.dueDate) ? nil : dueDate,
            dueDateHasTime: fields.contains(.dueDate) ? false : dueDateHasTime,
            projectId: fields.contains(.project) ? nil : projectId,
            priority: fields.contains(.priority) ? nil : priority,
            labelIds: labelIds.filter { !fields.contains(.label($0)) },
            matches: matches.filter { !fields.contains($0.field) }
        )
    }

    static func collapsingWhitespace(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pure, DB-free parser behind smart quick add (#215, phase 1 in #224), in the
/// style of `EstimateSuggester` and `QuickSchedule`.
///
/// Syntax follows Vikunja's web "Quick Add Magic": `+project` or `#project`,
/// `!1` to `!5` for priority, `*label`, plus natural-language dates.
///
/// Dates come from two layers:
/// 1. A keyword table (today, tomorrow, tonight, weekdays, "in 3 days",
///    "at 5pm", "17:30", noon, ...) plus the common absolute forms ("Sept 25",
///    "15 April", "25/9", "2026-12-01"). Deterministic against the injected
///    clock, calendar and locale.
/// 2. `NSDataDetector` as the fallback for anything else absolute. It cannot
///    take a fake clock, so its matches are filtered hard: bare numbers and
///    time-only matches are rejected.
///
/// Everything works on string ranges rather than whitespace-split words, and
/// each fixed keyword says whether it needs word boundaries, so a column of Chinese
/// keywords (no spaces between words) can be added without a rewrite.
struct SmartTaskParser {
    /// A project or label the text can refer to by name.
    struct Candidate: Equatable {
        let id: Int64
        let name: String
    }

    let projects: [Candidate]
    let labels: [Candidate]
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let defaultDueTime: DefaultDueTimePreference
    /// Off in tests that need determinism; the data detector reads the real
    /// clock and the system locale.
    let usesDataDetector: Bool

    init(
        projects: [Candidate],
        labels: [Candidate],
        now: Date = Date(),
        calendar: Calendar = .app,
        locale: Locale = .current,
        defaultDueTime: DefaultDueTimePreference = .current(),
        usesDataDetector: Bool = true
    ) {
        self.projects = projects
        self.labels = labels
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.defaultDueTime = defaultDueTime
        self.usesDataDetector = usesDataDetector
    }

    /// Convenience for call sites holding the app's models. Archived projects
    /// are not offered: a task should not quietly land in one.
    init(
        projects: [Project],
        labels: [VLabel],
        now: Date = Date(),
        calendar: Calendar = .app,
        locale: Locale = .current,
        defaultDueTime: DefaultDueTimePreference = .current()
    ) {
        self.init(
            projects: projects
                .filter { $0.isArchived != true }
                .map { Candidate(id: $0.id, name: $0.title) },
            labels: labels.map { Candidate(id: $0.id, name: $0.title) },
            now: now,
            calendar: calendar,
            locale: locale,
            defaultDueTime: defaultDueTime
        )
    }

    func parse(_ text: String) -> SmartTaskParse {
        var consumed: [Range<String.Index>] = []
        var matches: [SmartTaskParse.Match] = []

        // Sigil tokens first, so a project called "Friday Club" is not read
        // as a weekday.
        var projectId: Int64?
        if let hit = firstNameMatch(sigils: ["+", "#"], candidates: projects, in: text, excluding: consumed) {
            projectId = hit.id
            consumed.append(hit.range)
            matches.append(.init(field: .project, ranges: [hit.range]))
        }

        var labelIds: [Int64] = []
        var searchFrom = text.startIndex
        while let hit = firstNameMatch(
            sigils: ["*"], candidates: labels, in: text, from: searchFrom, excluding: consumed
        ) {
            searchFrom = hit.range.upperBound
            guard !labelIds.contains(hit.id) else { continue }
            labelIds.append(hit.id)
            consumed.append(hit.range)
            matches.append(.init(field: .label(hit.id), ranges: [hit.range]))
        }

        var priority: Int?
        if let hit = firstRegexMatch(Self.priorityRegex, in: text, excluding: consumed),
           let range = Range(hit.range, in: text),
           let digitRange = Range(hit.range(at: 1), in: text),
           let value = Int(text[digitRange])
        {
            priority = value
            consumed.append(range)
            matches.append(.init(field: .priority, ranges: [range]))
        }

        var dueDate: Date?
        var dueDateHasTime = false
        if let date = parseDate(in: text, excluding: consumed) {
            dueDate = date.date
            dueDateHasTime = date.hasTime
            matches.append(.init(field: .dueDate, ranges: date.ranges))
        }

        return SmartTaskParse(
            text: text,
            dueDate: dueDate,
            dueDateHasTime: dueDateHasTime,
            projectId: projectId,
            priority: priority,
            labelIds: labelIds,
            matches: matches
        )
    }

    // MARK: - Names

    private struct NameHit {
        let id: Int64
        let range: Range<String.Index>
    }

    /// The first sigil (at the start or after whitespace) followed by a known
    /// name. Longest case-insensitive full-name match wins, so
    /// "+Home Improvements" beats "Home". Failing that, a word that is a
    /// prefix of exactly one name matches it. Unknown names are skipped and
    /// stay in the title.
    private func firstNameMatch(
        sigils: Set<Character>,
        candidates: [Candidate],
        in text: String,
        from start: String.Index? = nil,
        excluding consumed: [Range<String.Index>]
    ) -> NameHit? {
        guard !candidates.isEmpty else { return nil }
        var index = start ?? text.startIndex
        while index < text.endIndex {
            defer { index = text.index(after: index) }
            guard sigils.contains(text[index]) else { continue }
            if index > text.startIndex, !text[text.index(before: index)].isWhitespace {
                continue
            }
            let nameStart = text.index(after: index)
            guard nameStart < text.endIndex, !text[nameStart].isWhitespace else { continue }
            guard let (candidate, nameEnd) = bestName(at: nameStart, in: text, candidates: candidates) else {
                continue
            }
            let range = index ..< nameEnd
            if consumed.contains(where: { $0.overlaps(range) }) {
                continue
            }
            return NameHit(id: candidate.id, range: range)
        }
        return nil
    }

    private func bestName(
        at start: String.Index,
        in text: String,
        candidates: [Candidate]
    ) -> (Candidate, String.Index)? {
        let rest = text[start...]
        var best: (Candidate, String.Index)?
        for candidate in candidates where !candidate.name.isEmpty {
            guard let found = rest.range(of: candidate.name, options: [.caseInsensitive, .anchored]),
                  Self.isNameBoundary(at: found.upperBound, in: text) else { continue }
            if let current = best, current.1 >= found.upperBound {
                continue
            }
            best = (candidate, found.upperBound)
        }
        if let best {
            return best
        }

        // Unique-prefix fallback: "+Improv" finds "Home Improvements" only if
        // nothing else starts with "Improv".
        let wordEnd = rest.firstIndex(where: \.isWhitespace) ?? text.endIndex
        let word = text[start ..< wordEnd]
        guard word.count >= 2 else { return nil }
        let prefixed = candidates.filter {
            $0.name.range(of: word, options: [.caseInsensitive, .anchored]) != nil
        }
        guard prefixed.count == 1, let only = prefixed.first else { return nil }
        return (only, wordEnd)
    }

    private static func isNameBoundary(at index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        let next = text[index]
        return !(next.isLetter || next.isNumber)
    }

    // MARK: - Dates

    private struct ParsedDate {
        let date: Date
        let hasTime: Bool
        let ranges: [Range<String.Index>]
    }

    private struct DayHit {
        let range: Range<String.Index>
        let day: Date
        /// A time the day word carries itself: "tonight" is 21:00.
        let impliedTime: (hour: Int, minute: Int)?
    }

    private struct TimeHit {
        let range: Range<String.Index>
        let hour: Int
        let minute: Int
    }

    private func parseDate(in text: String, excluding consumed: [Range<String.Index>]) -> ParsedDate? {
        var consumed = consumed
        let day = firstDayHit(in: text, excluding: consumed)
        if let day {
            consumed.append(day.range)
        }

        var time = firstTimeHit(in: text, excluding: consumed)
        if time == nil {
            time = dayPartHit(in: text, adjacentTo: day?.range, excluding: consumed)
        }
        if let time {
            consumed.append(time.range)
        }

        if let day {
            let clock = time.map { ($0.hour, $0.minute) } ?? day.impliedTime
            let hour = clock?.0 ?? defaultDueTime.hour
            let minute = clock?.1 ?? defaultDueTime.minute
            guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day.day) else {
                return nil
            }
            return ParsedDate(date: date, hasTime: clock != nil, ranges: [day.range] + (time.map { [$0.range] } ?? []))
        }

        if usesDataDetector, let detected = detectorDate(in: text, excluding: consumed, time: time) {
            return detected
        }

        // A time with no date: today, or tomorrow once it has passed.
        guard let time,
              var date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now)
        else { return nil }
        if date <= now, let rolled = calendar.date(byAdding: .day, value: 1, to: date) {
            date = rolled
        }
        return ParsedDate(date: date, hasTime: true, ranges: [time.range])
    }

    /// The earliest day expression in the text, across every keyword rule.
    private func firstDayHit(in text: String, excluding consumed: [Range<String.Index>]) -> DayHit? {
        var hits: [DayHit] = []
        let whole = NSRange(text.startIndex..., in: text)
        for rule in dayRules {
            for result in rule.regex.matches(in: text, range: whole) {
                guard let range = Range(result.range, in: text),
                      !consumed.contains(where: { $0.overlaps(range) }),
                      let hit = rule.resolve(result, text, range) else { continue }
                hits.append(hit)
                break
            }
        }
        return hits.min { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func firstTimeHit(in text: String, excluding consumed: [Range<String.Index>]) -> TimeHit? {
        var hits: [TimeHit] = []
        let whole = NSRange(text.startIndex..., in: text)
        for rule in Self.timeRules {
            for result in rule.regex.matches(in: text, range: whole) {
                guard let range = Range(result.range, in: text),
                      !consumed.contains(where: { $0.overlaps(range) }),
                      let clock = rule.resolve(result, text) else { continue }
                hits.append(TimeHit(range: range, hour: clock.hour, minute: clock.minute))
                break
            }
        }
        return hits.min { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// "morning", "afternoon" and "evening" only count next to a day
    /// ("tomorrow morning", "friday evening") or after "this", so a title like
    /// "Morning pages" is left alone.
    private func dayPartHit(
        in text: String,
        adjacentTo dayRange: Range<String.Index>?,
        excluding consumed: [Range<String.Index>]
    ) -> TimeHit? {
        let whole = NSRange(text.startIndex..., in: text)
        for result in Self.dayPartRegex.matches(in: text, range: whole) {
            guard let range = Range(result.range, in: text),
                  !consumed.contains(where: { $0.overlaps(range) }),
                  let wordRange = Range(result.range(at: 2), in: text),
                  let clock = Self.dayParts[text[wordRange].lowercased()] else { continue }
            let hasThis = result.range(at: 1).location != NSNotFound
            let isAdjacent = dayRange.map { day in
                let between = day.upperBound <= range.lowerBound
                    ? text[day.upperBound ..< range.lowerBound]
                    : range.upperBound <= day.lowerBound ? text[range.upperBound ..< day.lowerBound] : "x"
                return between.allSatisfy(\.isWhitespace)
            } ?? false
            if hasThis || isAdjacent {
                return TimeHit(range: range, hour: clock.hour, minute: clock.minute)
            }
        }
        return nil
    }

    // MARK: - Data detector fallback

    private func detectorDate(
        in text: String,
        excluding consumed: [Range<String.Index>],
        time: TimeHit?
    ) -> ParsedDate? {
        guard let detector = Self.dateDetector else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for result in detector.matches(in: text, range: whole) {
            guard let detected = result.date,
                  var range = Range(result.range, in: text),
                  !consumed.contains(where: { $0.overlaps(range) }),
                  Self.isPlausibleDetectorMatch(String(text[range])),
                  Self.isNameBoundary(at: range.upperBound, in: text),
                  !Self.isApostrophe(after: range.upperBound, in: text) else { continue }

            let matched = String(text[range])
            let matchedHasTime = Self.containsTime(matched)
            var clock: (hour: Int, minute: Int)?
            if let time {
                clock = (time.hour, time.minute)
            } else if matchedHasTime {
                let parts = calendar.dateComponents([.hour, .minute], from: detected)
                clock = (parts.hour ?? defaultDueTime.hour, parts.minute ?? defaultDueTime.minute)
            }

            var day = calendar.startOfDay(for: detected)
            if !Self.containsYear(matched), day < calendar.startOfDay(for: now),
               let rolled = calendar.date(byAdding: .year, value: 1, to: day)
            {
                day = rolled
            }
            guard let date = calendar.date(
                bySettingHour: clock?.hour ?? defaultDueTime.hour,
                minute: clock?.minute ?? defaultDueTime.minute,
                second: 0,
                of: day
            ) else { continue }

            // Take a leading "on" with the date, as the keyword layer does.
            if let on = text[..<range.lowerBound].range(
                of: "(?i)(?<![\\p{L}\\p{N}])on\\s+$",
                options: .regularExpression
            ) {
                range = on.lowerBound ..< range.upperBound
            }
            return ParsedDate(
                date: date,
                hasTime: clock != nil,
                ranges: [range] + (time.map { [$0.range] } ?? [])
            )
        }
        return nil
    }

    /// Rejects detector matches that are bare numbers ("Buy 3 apples",
    /// "Order 2024 calendar") or only a time, which the keyword layer owns.
    /// A match must carry a digit and something date-shaped: a separator
    /// between digits, a CJK date character, or a word such as a month name.
    static func isPlausibleDetectorMatch(_ matched: String) -> Bool {
        guard matched.contains(where: \.isNumber) else { return false }
        if matched.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            return false
        }
        if matched.range(of: "\\d\\s*[/.\\-]\\s*\\d", options: .regularExpression) != nil {
            return true
        }
        if matched.range(of: "[年月日号]", options: .regularExpression) != nil {
            return true
        }
        let words = matched.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
            .filter { !["noon", "midnight", "tonight", "today", "tomorrow"].contains($0) }
        return !words.isEmpty
    }

    private static func containsTime(_ string: String) -> Bool {
        string.range(of: "(?i)\\d\\s*(?::\\d{2}|[ap]\\.?m\\.?)|noon|midnight|[点時时]", options: .regularExpression) != nil
    }

    private static func containsYear(_ string: String) -> Bool {
        string.range(of: "(?<!\\d)\\d{4}(?!\\d)", options: .regularExpression) != nil
    }

    private static func isApostrophe(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return false }
        return text[index] == "'" || text[index] == "\u{2019}"
    }

    private static let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    // MARK: - Helpers

    private func firstRegexMatch(
        _ regex: NSRegularExpression,
        in text: String,
        excluding consumed: [Range<String.Index>]
    ) -> NSTextCheckingResult? {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).first { result in
            guard let range = Range(result.range, in: text) else { return false }
            return !consumed.contains { $0.overlaps(range) }
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals in this file; a bad one is a programmer error.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Wraps a keyword pattern in word boundaries. An apostrophe after the
    /// word also blocks it, so "Tomorrow's paper" is not a date.
    private static func bounded(_ pattern: String) -> String {
        "(?<![\\p{L}\\p{N}])(?:\(pattern))(?![\\p{L}\\p{N}'\u{2019}])"
    }

    private static func group(_ result: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < result.numberOfRanges,
              let range = Range(result.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Keyword tables

    private struct DayRule {
        let regex: NSRegularExpression
        let resolve: (NSTextCheckingResult, String, Range<String.Index>) -> DayHit?
    }

    private struct TimeRule {
        let regex: NSRegularExpression
        let resolve: (NSTextCheckingResult, String) -> (hour: Int, minute: Int)?
    }

    private static let priorityRegex = regex("(?<!\\S)!([1-5])(?![\\p{L}\\p{N}])")

    /// 一 is Monday, matching `Calendar.weekday` where 1 is Sunday. Both 日
    /// and 天 are Sunday.
    private static let chineseWeekdays = [
        "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1,
    ]

    private static let weekdays = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4,
        "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10, "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    private static let monthPattern = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    private static let dayParts: [String: (hour: Int, minute: Int)] = [
        "morning": (9, 0), "afternoon": (15, 0), "evening": (19, 0),
    ]

    private static let dayPartRegex = regex(bounded("(this\\s+)?(morning|afternoon|evening)"))

    private var dayRules: [DayRule] {
        let calendar = calendar
        let now = now
        let startOfToday = calendar.startOfDay(for: now)
        let dayFirst = Self.isDayFirst(locale)

        func offset(_ days: Int) -> Date? {
            calendar.date(byAdding: .day, value: days, to: startOfToday)
        }

        /// Builds a start-of-day date, rejecting impossible ones (31 Feb)
        /// instead of letting the calendar roll them over. With no year, a
        /// date already past this year means next year.
        func absolute(year: Int?, month: Int, day: Int) -> Date? {
            let currentYear = calendar.component(.year, from: now)
            var components = DateComponents(year: year ?? currentYear, month: month, day: day)
            guard var date = calendar.date(from: components),
                  calendar.component(.day, from: date) == day,
                  calendar.component(.month, from: date) == month else { return nil }
            if year == nil, date < startOfToday {
                components.year = currentYear + 1
                guard let rolled = calendar.date(from: components),
                      calendar.component(.day, from: rolled) == day else { return nil }
                date = rolled
            }
            return date
        }

        /// `wordBoundaries: false` is for scripts written without spaces,
        /// such as the zh-Hans column in phase 3 ("买牛奶明天").
        func fixed(
            _ pattern: String,
            _ date: @escaping () -> Date?,
            time: (Int, Int)? = nil,
            wordBoundaries: Bool = true
        ) -> DayRule {
            DayRule(regex: Self.regex(wordBoundaries ? Self.bounded(pattern) : pattern)) { _, _, range in
                date().map { DayHit(range: range, day: $0, impliedTime: time.map { (hour: $0.0, minute: $0.1) }) }
            }
        }

        return [
            fixed("(?:on\\s+)?today") { startOfToday },
            fixed("(?:on\\s+)?tomorrow") { QuickSchedule.tomorrow.resolvedDate(now: now, calendar: calendar) },
            fixed("tonight", { startOfToday }, time: (21, 0)),
            fixed("next\\s+week") { QuickSchedule.nextWeek.resolvedDate(now: now, calendar: calendar) },
            fixed("next\\s+month") { QuickSchedule.nextMonth.resolvedDate(now: now, calendar: calendar) },

            // Bare and "next" weekdays both mean the next occurrence strictly
            // after today (decision 1 in #223), matching Vikunja.
            DayRule(regex: Self.regex(Self.bounded(
                "(?:on\\s+)?(?:next\\s+)?(\(Self.weekdays.keys.joined(separator: "|")))"
            ))) { result, text, range in
                guard let name = Self.group(result, 1, in: text)?.lowercased(),
                      let target = Self.weekdays[name] else { return nil }
                let today = calendar.component(.weekday, from: now)
                let ahead = (target - today + 7) % 7
                return offset(ahead == 0 ? 7 : ahead).map { DayHit(range: range, day: $0, impliedTime: nil) }
            },

            DayRule(regex: Self.regex(Self.bounded("in\\s+(\\d{1,3})\\s+(days?|weeks?)"))) { result, text, range in
                guard let count = Self.group(result, 1, in: text).flatMap(Int.init),
                      let unit = Self.group(result, 2, in: text)?.lowercased() else { return nil }
                let days = unit.hasPrefix("week") ? count * 7 : count
                return offset(days).map { DayHit(range: range, day: $0, impliedTime: nil) }
            },

            // 2026-12-01
            DayRule(regex: Self
                .regex(Self.bounded("(?:on\\s+)?(\\d{4})-(\\d{1,2})-(\\d{1,2})")))
            { result, text, range in
                guard let year = Self.group(result, 1, in: text).flatMap(Int.init),
                      let month = Self.group(result, 2, in: text).flatMap(Int.init),
                      let day = Self.group(result, 3, in: text).flatMap(Int.init) else { return nil }
                return absolute(year: year, month: month, day: day)
                    .map { DayHit(range: range, day: $0, impliedTime: nil) }
            },

            // 25/9 or 9/25, ordered by the locale; optional year.
            DayRule(regex: Self.regex(
                "(?<![\\p{L}\\p{N}/.])(?:on\\s+)?(\\d{1,2})/(\\d{1,2})(?:/(\\d{2}|\\d{4}))?(?![\\p{L}\\p{N}/])"
            )) { result, text, range in
                guard let first = Self.group(result, 1, in: text).flatMap(Int.init),
                      let second = Self.group(result, 2, in: text).flatMap(Int.init) else { return nil }
                var year = Self.group(result, 3, in: text).flatMap(Int.init)
                if let short = year, short < 100 {
                    year = 2000 + short
                }
                let (day, month) = dayFirst ? (first, second) : (second, first)
                return absolute(year: year, month: month, day: day)
                    .map { DayHit(range: range, day: $0, impliedTime: nil) }
            },

            // Sept 25, Sept 25th, Sept 25 2027
            DayRule(regex: Self.regex(Self.bounded(
                "(?:on\\s+)?(\(Self.monthPattern))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?"
            ))) { result, text, range in
                guard let month = Self.group(result, 1, in: text).flatMap({ Self.months[$0.lowercased()] }),
                      let day = Self.group(result, 2, in: text).flatMap(Int.init) else { return nil }
                let year = Self.group(result, 3, in: text).flatMap(Int.init)
                return absolute(year: year, month: month, day: day)
                    .map { DayHit(range: range, day: $0, impliedTime: nil) }
            },

            // 15 April, 15th of April, 15 April 2027
            DayRule(regex: Self.regex(Self.bounded(
                "(?:on\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(\(Self.monthPattern))\\.?(?:,?\\s+(\\d{4}))?"
            ))) { result, text, range in
                guard let day = Self.group(result, 1, in: text).flatMap(Int.init),
                      let month = Self.group(result, 2, in: text).flatMap({ Self.months[$0.lowercased()] })
                else { return nil }
                let year = Self.group(result, 3, in: text).flatMap(Int.init)
                return absolute(year: year, month: month, day: day)
                    .map { DayHit(range: range, day: $0, impliedTime: nil) }
            },

            // zh-Hans. Chinese is written without spaces between words, so
            // these keywords take no word boundaries (#226).
            fixed("今天", { startOfToday }, wordBoundaries: false),
            fixed("明天", { offset(1) }, wordBoundaries: false),
            fixed("后天|後天", { offset(2) }, wordBoundaries: false),
            fixed("今晚|今天晚上", { startOfToday }, time: (21, 0), wordBoundaries: false),
            fixed("下周|下週|下星期", {
                QuickSchedule.nextWeek.resolvedDate(now: now, calendar: calendar)
            }, wordBoundaries: false),
            fixed("下个月|下個月", {
                QuickSchedule.nextMonth.resolvedDate(now: now, calendar: calendar)
            }, wordBoundaries: false),

            // 周一 to 周日, also 星期一 and 礼拜一. Same rule as the English
            // weekdays: the next occurrence strictly after today.
            DayRule(regex: Self.regex("(?:这|這|下)?(?:周|週|星期|礼拜|禮拜)([一二三四五六日天])")) { result, text, range in
                guard let name = Self.group(result, 1, in: text),
                      let target = Self.chineseWeekdays[name] else { return nil }
                let today = calendar.component(.weekday, from: now)
                let ahead = (target - today + 7) % 7
                return offset(ahead == 0 ? 7 : ahead).map { DayHit(range: range, day: $0, impliedTime: nil) }
            },
        ]
    }

    private static let timeRules: [TimeRule] = [
        // 5pm, 5 pm, 5:30pm, at 5pm
        TimeRule(regex: regex(bounded("(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*([ap])\\.?m\\.?"))) { result, text in
            guard let hour = group(result, 1, in: text).flatMap(Int.init), (1 ... 12).contains(hour),
                  let meridiem = group(result, 3, in: text)?.lowercased() else { return nil }
            let minute = group(result, 2, in: text).flatMap(Int.init) ?? 0
            guard (0 ... 59).contains(minute) else { return nil }
            let base = hour % 12
            return (meridiem == "p" ? base + 12 : base, minute)
        },
        // 17:30, 9:30, at 09:30
        TimeRule(regex: regex(bounded("(?:at\\s+)?(\\d{1,2}):(\\d{2})"))) { result, text in
            guard let hour = group(result, 1, in: text).flatMap(Int.init), (0 ... 23).contains(hour),
                  let minute = group(result, 2, in: text).flatMap(Int.init), (0 ... 59).contains(minute)
            else { return nil }
            return (hour, minute)
        },
        // zh-Hans: 3点, 下午3点, 上午9点30分, 中午. No word boundaries.
        TimeRule(
            regex: regex("(上午|早上|中午|下午|晚上)?\\s*(\\d{1,2})\\s*[点點](?:\\s*(\\d{1,2})\\s*分?)?")
        ) { result, text in
            guard let hour = group(result, 2, in: text).flatMap(Int.init), (0 ... 23).contains(hour)
            else { return nil }
            let minute = group(result, 3, in: text).flatMap(Int.init) ?? 0
            guard (0 ... 59).contains(minute) else { return nil }
            let period = group(result, 1, in: text)
            let isAfternoon = period == "下午" || period == "晚上" || period == "中午"
            return (isAfternoon && hour < 12 ? hour + 12 : hour, minute)
        },
        TimeRule(regex: regex("中午(?![\\d一二三四五六七八九十])")) { _, _ in (12, 0) },
        TimeRule(regex: regex(bounded("(?:at\\s+)?noon"))) { _, _ in (12, 0) },
        TimeRule(regex: regex(bounded("(?:at\\s+)?midnight"))) { _, _ in (0, 0) },
    ]

    /// Whether the locale writes numeric dates day first (25/9) or month
    /// first (9/25).
    static func isDayFirst(_ locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: locale) ?? "d/M"
        guard let day = format.firstIndex(of: "d"), let month = format.firstIndex(of: "M") else { return true }
        return day < month
    }
}
