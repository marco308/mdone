import Foundation

/// Read and toggle the checklists Vikunja keeps inside a task description.
///
/// Vikunja's description editor (Tiptap) stores a checklist as a task list:
///
/// ```html
/// <ul data-type="taskList">
///   <li data-checked="true" data-type="taskItem">
///     <label><input type="checkbox" checked="checked"><span></span></label>
///     <div><p>Johnny</p></div>
///   </li>
///   <li data-checked="false" data-type="taskItem">
///     <label><input type="checkbox"><span></span></label>
///     <div><p>Atlas</p></div>
///   </li>
/// </ul>
/// ```
///
/// There is no separate API for the items: ticking one is a task update that
/// sends the description back with `data-checked` flipped. `data-checked` is
/// the attribute Vikunja's editor and its repeat-reset read; the `checked`
/// attribute on the input is kept in step so the markup stays the shape the
/// web app writes. The web app's card badge counts these attributes too, so
/// the counts here match what it shows (issue #200).
///
/// Everything here is pure string work over the raw HTML: nothing else in the
/// description is touched, so text the user wrote around the list survives a
/// toggle byte for byte.
struct DescriptionChecklist: Equatable {
    struct Item: Identifiable, Equatable {
        /// Position of the item in the description, counting every task item
        /// in document order. Stable for the lifetime of one description
        /// string, which is what `toggling(itemAt:in:)` keys on.
        let id: Int
        let text: String
        let isChecked: Bool
    }

    let items: [Item]

    var doneCount: Int {
        items.filter(\.isChecked).count
    }

    var totalCount: Int {
        items.count
    }

    var isComplete: Bool {
        !items.isEmpty && doneCount == totalCount
    }

    /// Completed fraction, 0...1, for a progress bar. Zero when empty.
    var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(doneCount) / Double(totalCount)
    }

    // MARK: - Parsing

    /// The checklist items in `html`, or `nil` when the description has none.
    static func parse(_ html: String?) -> DescriptionChecklist? {
        guard let html, hasChecklist(html) else { return nil }
        let items = itemMatches(in: html).enumerated().map { index, match in
            Item(id: index, text: match.text, isChecked: match.isChecked)
        }
        return items.isEmpty ? nil : DescriptionChecklist(items: items)
    }

    /// Cheap pre-check so lists of tasks without checklists never pay for a
    /// regex scan.
    static func hasChecklist(_ html: String) -> Bool {
        html.contains("data-checked=")
    }

    // MARK: - Toggling

    /// `html` with item `index` flipped, or `nil` when there is no such item.
    static func toggling(itemAt index: Int, in html: String) -> String? {
        let matches = itemMatches(in: html)
        guard matches.indices.contains(index) else { return nil }
        return setting(matches[index], checked: !matches[index].isChecked, in: html)
    }

    /// `html` with item `index` set to `checked`, or `nil` when there is no
    /// such item. A no-op returns the input unchanged.
    static func setting(itemAt index: Int, checked: Bool, in html: String) -> String? {
        let matches = itemMatches(in: html)
        guard matches.indices.contains(index) else { return nil }
        return setting(matches[index], checked: checked, in: html)
    }

    // MARK: - Segments

    /// A description split into the runs of ordinary HTML and the checklists
    /// between them, so a view can render the prose with the rich-text
    /// renderer and the checklists as native toggles. Item ids are the same
    /// document-order indices `parse` assigns, so a toggle from a segment
    /// maps straight back to `toggling(itemAt:in:)`.
    enum Segment: Equatable {
        case html(String)
        case checklist([Item])
    }

    static func segments(of html: String) -> [Segment] {
        guard hasChecklist(html), let listRegex = taskListOpenRegex else { return [.html(html)] }
        let matches = itemMatches(in: html)
        let nsHTML = html as NSString
        var segments: [Segment] = []
        var cursor = 0
        var searchFrom = 0

        while let open = listRegex.firstMatch(
            in: html, range: NSRange(location: searchFrom, length: nsHTML.length - searchFrom)
        ) {
            let listStart = open.range.location
            let listEnd = closingListEnd(in: nsHTML, openingAt: open.range)
            let listRange = NSRange(location: listStart, length: listEnd - listStart)
            let itemsInList = matches.enumerated().compactMap { index, match -> Item? in
                guard NSLocationInRange(match.openTagRange.location, listRange) else { return nil }
                return Item(id: index, text: match.text, isChecked: match.isChecked)
            }

            if itemsInList.isEmpty {
                // A task list with nothing in it, or one whose markup we do
                // not recognise: leave it to the rich-text renderer.
                searchFrom = listEnd
                continue
            }

            let before = nsHTML.substring(with: NSRange(location: cursor, length: listStart - cursor))
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.html(before))
            }
            segments.append(.checklist(itemsInList))
            cursor = listEnd
            searchFrom = listEnd
        }

        let tail = nsHTML.substring(from: cursor)
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.html(tail))
        }
        return segments.isEmpty ? [.html(html)] : segments
    }

    // MARK: - Internals

    private struct ItemMatch {
        /// The `<li ...>` opening tag.
        let openTagRange: NSRange
        /// From the end of the opening tag to the start of the next `<li` or
        /// `</li>`, whichever comes first. Nested lists therefore contribute
        /// their own flat items rather than being swallowed by the parent.
        let bodyRange: NSRange
        let isChecked: Bool
        let text: String
    }

    /// An `<li>` carrying `data-checked`. Attribute order is not fixed, so
    /// the tag is matched as a whole and the attribute read from it.
    private static let itemOpenRegex = try? NSRegularExpression(
        pattern: #"<li\b[^>]*\bdata-checked\s*=\s*"(true|false)"[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let taskListOpenRegex = try? NSRegularExpression(
        pattern: #"<ul\b[^>]*\bdata-type\s*=\s*"taskList"[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let listBoundaryRegex = try? NSRegularExpression(
        pattern: #"<ul\b[^>]*>|</ul\s*>"#,
        options: [.caseInsensitive]
    )
    private static let itemBoundaryRegex = try? NSRegularExpression(
        pattern: #"<li\b|</li\s*>"#,
        options: [.caseInsensitive]
    )
    private static let checkboxRegex = try? NSRegularExpression(
        pattern: #"<input\b[^>]*\btype\s*=\s*"checkbox"[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let checkedAttributeRegex = try? NSRegularExpression(
        pattern: #"\s+checked(\s*=\s*("[^"]*"|'[^']*'|[^\s>/]+))?"#,
        options: [.caseInsensitive]
    )
    private static let dataCheckedRegex = try? NSRegularExpression(
        pattern: #"\bdata-checked\s*=\s*"(true|false)""#,
        options: [.caseInsensitive]
    )
    private static let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#)

    private static func itemMatches(in html: String) -> [ItemMatch] {
        guard let itemOpenRegex, let itemBoundaryRegex else { return [] }
        let nsHTML = html as NSString
        let full = NSRange(location: 0, length: nsHTML.length)
        return itemOpenRegex.matches(in: html, range: full).map { match in
            let openTag = match.range
            let isChecked = nsHTML.substring(with: match.range(at: 1)).lowercased() == "true"
            let bodyStart = openTag.location + openTag.length
            let searchRange = NSRange(location: bodyStart, length: nsHTML.length - bodyStart)
            let bodyEnd = itemBoundaryRegex.firstMatch(in: html, range: searchRange)?.range.location ?? nsHTML.length
            let bodyRange = NSRange(location: bodyStart, length: bodyEnd - bodyStart)
            return ItemMatch(
                openTagRange: openTag,
                bodyRange: bodyRange,
                isChecked: isChecked,
                text: plainText(of: nsHTML.substring(with: bodyRange))
            )
        }
    }

    /// The end offset of the `</ul>` that closes the task list opened at
    /// `open`, counting nested lists. Falls back to the end of the string
    /// for unbalanced markup.
    private static func closingListEnd(in nsHTML: NSString, openingAt open: NSRange) -> Int {
        guard let listBoundaryRegex else { return nsHTML.length }
        var depth = 1
        var position = open.location + open.length
        while position < nsHTML.length {
            let range = NSRange(location: position, length: nsHTML.length - position)
            guard let boundary = listBoundaryRegex.firstMatch(in: nsHTML as String, range: range) else { break }
            let token = nsHTML.substring(with: boundary.range)
            depth += token.hasPrefix("</") ? -1 : 1
            position = boundary.range.location + boundary.range.length
            if depth == 0 {
                return position
            }
        }
        return nsHTML.length
    }

    private static func setting(_ item: ItemMatch, checked: Bool, in html: String) -> String {
        guard item.isChecked != checked,
              let dataCheckedRegex, let checkboxRegex, let checkedAttributeRegex
        else { return html }
        let nsHTML = html as NSString
        let result = NSMutableString(string: html)

        // Body first, so the opening tag's offsets are still valid after.
        if let checkbox = checkboxRegex.firstMatch(in: html, range: item.bodyRange) {
            let tag = NSMutableString(string: nsHTML.substring(with: checkbox.range))
            let tagRange = NSRange(location: 0, length: tag.length)
            checkedAttributeRegex.replaceMatches(in: tag, range: tagRange, withTemplate: "")
            if checked {
                // Re-insert before the closing `>` or `/>`, with the single
                // space the web app's serialiser would put there.
                let selfClosing = tag.hasSuffix("/>")
                var body = (tag as String).dropLast(selfClosing ? 2 : 1)
                while body.last?.isWhitespace == true {
                    body = body.dropLast()
                }
                tag.setString(body + " checked=\"checked\"" + (selfClosing ? " />" : ">"))
            }
            result.replaceCharacters(in: checkbox.range, with: tag as String)
        }

        let openTag = NSMutableString(string: nsHTML.substring(with: item.openTagRange))
        dataCheckedRegex.replaceMatches(
            in: openTag,
            range: NSRange(location: 0, length: openTag.length),
            withTemplate: "data-checked=\"\(checked ? "true" : "false")\""
        )
        result.replaceCharacters(in: item.openTagRange, with: openTag as String)
        return result as String
    }

    /// The item's label: tags removed, entities decoded, whitespace collapsed.
    private static func plainText(of fragment: String) -> String {
        var text = fragment
        if let tagRegex {
            text = tagRegex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " "
            )
        }
        text = decodeEntities(text)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
        ] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        // Last, so `&amp;lt;` decodes to `&lt;` and not to `<`.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension VTask {
    /// Completed/total counts across the checklist items in the description,
    /// matching the badge Vikunja's web app puts on a card. `nil` when the
    /// description has no checklist.
    var checklistCounts: (done: Int, total: Int)? {
        guard let checklist = DescriptionChecklist.parse(description) else { return nil }
        return (checklist.doneCount, checklist.totalCount)
    }
}
