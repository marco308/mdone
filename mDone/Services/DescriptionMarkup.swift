import Foundation

/// Converts the HTML Vikunja's web editor (Tiptap) stores in a task
/// description to a light Markdown-style text for editing, and back (#277).
///
/// The editable text understands:
///
/// - paragraphs, separated by a blank line; a single line break inside one
///   is a `<br>`
/// - `# Heading` (one to six `#`)
/// - `**bold**`, `*italic*` and `[text](https://link)`; a bare `https://`
///   address becomes a link on save
/// - `- item` bullets and `1. item` numbered lists
/// - `- [ ] item` and `- [x] item` checklists, written back as the Tiptap
///   task list the web app shows as checkboxes
///
/// A literal `\`, `*`, `[` or `]` in the text is escaped with a backslash,
/// as is a line that would otherwise read as a list or heading, so text that
/// only looks like markup survives a round trip.
///
/// Anything else (tables, images, code, quotes, nested lists, comments,
/// underline, ...) makes `editableText(fromHTML:)` return `nil`, and the
/// caller edits the raw HTML instead, so nothing is ever silently dropped.
/// Pure string work with no UI dependencies, so it is unit tested directly.
enum DescriptionMarkup {
    // MARK: - HTML to editable text

    /// The editable text for `html`, or `nil` when the HTML holds something
    /// this format cannot represent.
    static func editableText(fromHTML html: String) -> String? {
        guard let nodes = HTMLParser.parse(html) else { return nil }
        var blocks: [String?] = []
        for node in nodes {
            switch node {
            case let .text(text):
                guard isBlank(text) else { return nil }
            case let .element(name, attributes, children):
                guard let block = editableBlock(name: name, attributes: attributes, children: children) else {
                    return nil
                }
                blocks.append(block.isEmpty ? nil : block)
            }
        }
        // Leading and trailing empty paragraphs carry nothing.
        while blocks.first == .some(nil) {
            blocks.removeFirst()
        }
        while blocks.last == .some(nil) {
            blocks.removeLast()
        }
        var text = ""
        for (index, block) in blocks.enumerated() {
            if let block {
                text += (index == 0 ? "" : "\n\n") + block
            } else {
                // Each empty paragraph between blocks is one extra blank line.
                text += "\n"
            }
        }
        return text
    }

    private static func editableBlock(name: String, attributes: [String: String], children: [Node]) -> String? {
        switch name {
        case "p":
            return inlineText(children).map(escapeLineStarts)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            guard let level = Int(name.dropFirst()), let text = inlineText(children), !text.contains("\n") else {
                return nil
            }
            return String(repeating: "#", count: level) + " " + text
        case "ul" where attributes["data-type"]?.lowercased() == "tasklist":
            return taskListText(children)
        case "ul":
            guard let items = listItems(children) else { return nil }
            return items.map { "- " + $0 }.joined(separator: "\n")
        case "ol":
            guard let items = listItems(children) else { return nil }
            let start = attributes["start"].flatMap { Int($0) } ?? 1
            return items.enumerated().map { "\(start + $0.offset). " + $0.element }.joined(separator: "\n")
        default:
            return nil
        }
    }

    private static func taskListText(_ children: [Node]) -> String? {
        var lines: [String] = []
        for child in children {
            guard case let .element(name, attributes, itemChildren) = child else {
                if case let .text(text) = child, isBlank(text) {
                    continue
                }
                return nil
            }
            guard name == "li", let checked = attributes["data-checked"]?.lowercased(),
                  checked == "true" || checked == "false"
            else { return nil }
            // The label only holds the checkbox; the text lives in the div.
            var content: [Node] = []
            for node in itemChildren {
                switch node {
                case let .element("label", _, labelChildren):
                    guard plainText(labelChildren).allSatisfy(\.isWhitespace) else { return nil }
                case let .element("div", _, divChildren):
                    content += divChildren
                default:
                    content.append(node)
                }
            }
            guard let text = itemText(content) else { return nil }
            lines.append((checked == "true" ? "- [x]" : "- [ ]") + (text.isEmpty ? "" : " " + text))
        }
        return lines.joined(separator: "\n")
    }

    private static func listItems(_ children: [Node]) -> [String]? {
        var items: [String] = []
        for child in children {
            guard case let .element(name, _, itemChildren) = child else {
                if case let .text(text) = child, isBlank(text) {
                    continue
                }
                return nil
            }
            guard name == "li", let text = itemText(itemChildren) else { return nil }
            items.append(text)
        }
        return items
    }

    /// One list item's text: a single paragraph, or bare inline content.
    /// Two paragraphs or a nested list cannot be written on one line.
    private static func itemText(_ nodes: [Node]) -> String? {
        let meaningful = nodes.filter {
            if case let .text(text) = $0 {
                return !isBlank(text)
            }
            return true
        }
        let inline: String?
        if meaningful.count == 1, case let .element("p", _, children) = meaningful[0] {
            inline = inlineText(children)
        } else if meaningful.contains(where: {
            if case .element("p", _, _) = $0 {
                return true
            }
            return false
        }) {
            return nil
        } else {
            inline = inlineText(meaningful)
        }
        guard let inline, !inline.contains("\n") else { return nil }
        return inline
    }

    /// Inline markup as editable text, or `nil` for an element it cannot
    /// represent. Lines are trimmed, as HTML collapses that space anyway.
    private static func inlineText(_ nodes: [Node]) -> String? {
        guard let raw = inlineRaw(nodes) else { return nil }
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private static func inlineRaw(_ nodes: [Node]) -> String? {
        var result = ""
        for node in nodes {
            switch node {
            case let .text(text):
                result += escapeInline(collapseWhitespace(text))
            case let .element(name, attributes, children):
                switch name {
                case "br":
                    result += "\n"
                case "strong", "b", "em", "i":
                    guard let inner = inlineRaw(children) else { return nil }
                    let marker = (name == "strong" || name == "b") ? "**" : "*"
                    // Spaces just inside the markers would stop them pairing up.
                    let trimmed = inner.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else {
                        result += inner
                        continue
                    }
                    let leading = inner.prefix { $0 == " " }
                    let trailing = String(inner.reversed().prefix { $0 == " " })
                    result += String(leading) + marker + trimmed + marker + trailing
                case "a":
                    guard let href = attributes["href"], let inner = inlineRaw(children) else { return nil }
                    if children.count <= 1, plainText(children) == href, autolinkedURL(in: href) == href {
                        result += inner
                    } else {
                        result += "[" + inner + "](" + escapeURL(href) + ")"
                    }
                case "span":
                    guard let inner = inlineRaw(children) else { return nil }
                    result += inner
                default:
                    return nil
                }
            }
        }
        return result
    }

    // MARK: - Editable text to HTML

    /// The HTML for `text`, in the shape Vikunja's web editor writes.
    static func html(fromEditableText text: String) -> String {
        var html = ""
        for block in blocks(in: text) {
            switch block {
            case let .paragraph(lines):
                html += "<p>" + inlineHTML(lines.joined(separator: "\n")) + "</p>"
            case let .heading(level, text):
                html += "<h\(level)>" + inlineHTML(text) + "</h\(level)>"
            case let .bullets(items):
                html += "<ul>" + items.map { "<li><p>" + inlineHTML($0) + "</p></li>" }.joined() + "</ul>"
            case let .numbered(start, items):
                let open = start == 1 ? "<ol>" : "<ol start=\"\(start)\">"
                html += open + items.map { "<li><p>" + inlineHTML($0) + "</p></li>" }.joined() + "</ol>"
            case let .tasks(items):
                html += "<ul data-type=\"taskList\">"
                for item in items {
                    let checked = item.checked ? "true" : "false"
                    let checkbox = item.checked ? "<input type=\"checkbox\" checked=\"checked\">" :
                        "<input type=\"checkbox\">"
                    html += "<li data-checked=\"\(checked)\" data-type=\"taskItem\"><label>\(checkbox)<span></span></label>"
                    html += "<div><p>" + inlineHTML(item.text) + "</p></div></li>"
                }
                html += "</ul>"
            case .empty:
                html += "<p></p>"
            }
        }
        return html
    }

    private enum Block {
        case paragraph([String])
        case heading(Int, String)
        case bullets([String])
        case numbered(start: Int, [String])
        case tasks([(checked: Bool, text: String)])
        case empty
    }

    private enum Line {
        case blank
        case text(String)
        case heading(Int, String)
        case bullet(String)
        case numbered(Int, String)
        case task(Bool, String)
    }

    private static func classify(_ line: String) -> Line {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .blank
        }
        if let match = firstMatch(taskLineRegex, in: trimmed) {
            return .task(match[1].lowercased() == "x", match[2])
        }
        if let match = firstMatch(bulletLineRegex, in: trimmed) {
            return .bullet(match[1])
        }
        if let match = firstMatch(numberedLineRegex, in: trimmed), let number = Int(match[1]) {
            return .numbered(number, match[2])
        }
        if let match = firstMatch(headingLineRegex, in: trimmed) {
            return .heading(match[1].count, match[2])
        }
        return .text(trimmed)
    }

    private static func blocks(in text: String) -> [Block] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        var blocks: [Block] = []
        var current: Block?
        var blankRun = 0

        func close() {
            if let block = current {
                blocks.append(block)
            }
            current = nil
        }

        for rawLine in lines {
            let line = classify(String(rawLine))
            if case .blank = line {
                blankRun += 1
                continue
            }
            if blankRun > 0 {
                close()
                // One blank line separates blocks; each extra one is an
                // empty paragraph, the way the web editor keeps spacing.
                if !blocks.isEmpty {
                    blocks += Array(repeating: .empty, count: blankRun - 1)
                }
                blankRun = 0
            }
            switch (line, current) {
            case let (.text(text), .paragraph(existing)?):
                current = .paragraph(existing + [text])
            case let (.bullet(text), .bullets(existing)?):
                current = .bullets(existing + [text])
            case let (.numbered(_, text), .numbered(start, existing)?):
                current = .numbered(start: start, existing + [text])
            case let (.task(checked, text), .tasks(existing)?):
                current = .tasks(existing + [(checked, text)])
            default:
                close()
                switch line {
                case let .text(text): current = .paragraph([text])
                case let .heading(level, text): current = .heading(level, text)
                case let .bullet(text): current = .bullets([text])
                case let .numbered(start, text): current = .numbered(start: start, [text])
                case let .task(checked, text): current = .tasks([(checked, text)])
                case .blank: break
                }
            }
        }
        close()
        return blocks
    }

    /// Inline Markdown-style text as HTML: escapes, `**bold**`, `*italic*`,
    /// `[text](url)`, bare links, and line breaks.
    private static func inlineHTML(_ text: String) -> String {
        let chars = Array(text.trimmingCharacters(in: .whitespaces))
        return renderInline(chars, 0 ..< chars.count)
    }

    private static func renderInline(_ chars: [Character], _ range: Range<Int>) -> String {
        var output = ""
        var literal = ""
        func flush() {
            output += autolinkedHTML(literal)
            literal = ""
        }
        let end = range.upperBound
        var index = range.lowerBound
        while index < end {
            let char = chars[index]
            if char == "\\", index + 1 < end, escapable.contains(chars[index + 1]) {
                literal.append(chars[index + 1])
                index += 2
                continue
            }
            if char == "*" {
                let boldClose = starRun(chars, at: index, end: end) >= 2
                    ? closingDoubleStar(chars, from: index + 2, end: end) : nil
                if let close = boldClose, close > index + 2 {
                    flush()
                    output += "<strong>" + renderInline(chars, (index + 2) ..< close) + "</strong>"
                    index = close + 2
                    continue
                }
                if let close = closingSingleStar(chars, from: index + 1, end: end), close > index + 1 {
                    flush()
                    output += "<em>" + renderInline(chars, (index + 1) ..< close) + "</em>"
                    index = close + 1
                    continue
                }
            }
            if char == "[", let (textEnd, urlEnd) = linkBounds(chars, openingAt: index, end: end) {
                flush()
                let url = String(chars[(textEnd + 2) ..< urlEnd]).trimmingCharacters(in: .whitespaces)
                output += "<a href=\"" + escapeHTML(url, attribute: true) + "\">"
                output += renderInline(chars, (index + 1) ..< textEnd) + "</a>"
                index = urlEnd + 1
                continue
            }
            if char == "\n" {
                flush()
                output += "<br>"
                index += 1
                continue
            }
            literal.append(char)
            index += 1
        }
        flush()
        return output
    }

    private static func starRun(_ chars: [Character], at index: Int, end: Int) -> Int {
        var run = 0
        while index + run < end, chars[index + run] == "*" {
            run += 1
        }
        return run
    }

    /// Where the `**` closing a bold run starts. In a run of three, the last
    /// two close the bold and the first closes an italic inside it.
    private static func closingDoubleStar(_ chars: [Character], from start: Int, end: Int) -> Int? {
        var index = start
        while index < end {
            if chars[index] == "\\" {
                index += 2
                continue
            }
            if chars[index] == "*" {
                let run = starRun(chars, at: index, end: end)
                if run >= 2 {
                    return index + run - 2
                }
                index += run
                continue
            }
            index += 1
        }
        return nil
    }

    /// Where the `*` closing an italic run is, stepping over bold pairs.
    private static func closingSingleStar(_ chars: [Character], from start: Int, end: Int) -> Int? {
        var index = start
        while index < end {
            if chars[index] == "\\" {
                index += 2
                continue
            }
            if chars[index] == "*" {
                let run = starRun(chars, at: index, end: end)
                if run == 1 {
                    return index
                }
                if run >= 3 {
                    return index + run - 1
                }
                index += run
                continue
            }
            index += 1
        }
        return nil
    }

    /// The `]` and `)` of a `[text](url)` link opening at `start`.
    private static func linkBounds(_ chars: [Character], openingAt start: Int, end: Int) -> (Int, Int)? {
        var depth = 0
        var index = start
        var textEnd: Int?
        while index < end {
            let char = chars[index]
            if char == "\\" {
                index += 2
                continue
            }
            if char == "\n" {
                return nil
            }
            if char == "[" {
                depth += 1
            }
            if char == "]" {
                depth -= 1
                if depth == 0 {
                    textEnd = index
                    break
                }
            }
            index += 1
        }
        guard let textEnd, textEnd + 1 < end, chars[textEnd + 1] == "(" else { return nil }
        var urlEnd = textEnd + 2
        while urlEnd < end, chars[urlEnd] != ")" {
            if chars[urlEnd].isWhitespace {
                return nil
            }
            urlEnd += 1
        }
        guard urlEnd < end, urlEnd > textEnd + 2 else { return nil }
        return (textEnd, urlEnd)
    }

    // MARK: - Escaping

    /// Characters a backslash makes literal in the editable text.
    private static let escapable: Set<Character> = ["\\", "*", "[", "]", "#", "-", "+", ".", ")"]

    private static func escapeInline(_ text: String) -> String {
        var result = ""
        for char in text {
            if char == "\\" || char == "*" || char == "[" || char == "]" {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }

    /// Escapes a paragraph line that would otherwise read as a heading or a
    /// list item.
    private static func escapeLineStarts(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let line = String(line)
            if firstMatch(headingLineRegex, in: line) != nil || firstMatch(bulletLineRegex, in: line) != nil {
                return "\\" + line
            }
            if let match = firstMatch(numberedLineRegex, in: line) {
                // `1. ` becomes `1\. `: escape the punctuation after the digits.
                return match[1] + "\\" + line.dropFirst(match[1].count)
            }
            return line
        }.joined(separator: "\n")
    }

    private static func escapeURL(_ url: String) -> String {
        url.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: ")", with: "%29")
    }

    private static func escapeHTML(_ text: String, attribute: Bool = false) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if attribute {
            result = result.replacingOccurrences(of: "\"", with: "&quot;")
        }
        return result
    }

    // MARK: - Links

    private static let autolinkRegex = try? NSRegularExpression(
        pattern: #"https?://[^\s<>"]+"#,
        options: [.caseInsensitive]
    )

    /// The address a bare link in `text` would link to: the first `http(s)`
    /// run, less trailing sentence punctuation.
    private static func autolinkedURL(in text: String) -> String? {
        guard let match = autolinkRanges(in: text).first else { return nil }
        return String(text[match])
    }

    private static func autolinkRanges(in text: String) -> [Range<String.Index>] {
        guard let autolinkRegex else { return [] }
        let matches = autolinkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard var range = Range(match.range, in: text) else { return nil }
            while let last = text[range].last, ".,;:!?)]'".contains(last) {
                range = range.lowerBound ..< text.index(before: range.upperBound)
            }
            return range.isEmpty ? nil : range
        }
    }

    private static func autolinkedHTML(_ text: String) -> String {
        var output = ""
        var cursor = text.startIndex
        for range in autolinkRanges(in: text) {
            output += escapeHTML(String(text[cursor ..< range.lowerBound]))
            let url = String(text[range])
            output += "<a href=\"" + escapeHTML(url, attribute: true) + "\">" + escapeHTML(url) + "</a>"
            cursor = range.upperBound
        }
        return output + escapeHTML(String(text[cursor...]))
    }

    // MARK: - Helpers

    private static let taskLineRegex = try? NSRegularExpression(pattern: #"^[-*+]\s+\[([ xX])\](?:\s+(.*))?$"#)
    private static let bulletLineRegex = try? NSRegularExpression(pattern: #"^[-*+]\s+(.*)$"#)
    private static let numberedLineRegex = try? NSRegularExpression(pattern: #"^(\d{1,9})[.)]\s+(.*)$"#)
    private static let headingLineRegex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+(.*)$"#)

    /// Capture groups of the first match, with a missing group as "".
    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> [String]? {
        guard let regex,
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (0 ..< match.numberOfRanges).map { group in
            Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
    }

    /// HTML treats any run of spaces, tabs and newlines as one space.
    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
    }

    private static func plainText(_ nodes: [Node]) -> String {
        nodes.map { node in
            switch node {
            case let .text(text): text
            case let .element(_, _, children): plainText(children)
            }
        }.joined()
    }

    // MARK: - HTML parsing

    fileprivate indirect enum Node {
        case text(String)
        case element(String, [String: String], [Node])
    }

    /// A small, strict HTML reader: enough for the well-formed markup the
    /// web editor writes. Comments, unbalanced tags and the like return
    /// `nil` so the caller falls back to editing the raw HTML.
    private enum HTMLParser {
        static let voidElements: Set<String> = ["br", "input", "img", "hr", "wbr", "meta", "col", "source"]

        static func parse(_ html: String) -> [Node]? {
            let chars = Array(html)
            var stack = [OpenElement(name: "", attributes: [:])]
            var text = ""
            var index = 0

            func flushText() {
                if !text.isEmpty {
                    stack[stack.count - 1].children.append(.text(decodeEntities(text)))
                    text = ""
                }
            }

            while index < chars.count {
                let char = chars[index]
                guard char == "<", index + 1 < chars.count else {
                    text.append(char)
                    index += 1
                    continue
                }
                let next = chars[index + 1]
                if next == "!" || next == "?" {
                    return nil
                }
                if next == "/" {
                    guard let close = chars[index...].firstIndex(of: ">") else { return nil }
                    let name = String(chars[(index + 2) ..< close]).trimmingCharacters(in: .whitespaces).lowercased()
                    flushText()
                    guard stack.count > 1, stack[stack.count - 1].name == name else { return nil }
                    let element = stack.removeLast()
                    stack[stack.count - 1].children.append(.element(element.name, element.attributes, element.children))
                    index = close + 1
                    continue
                }
                guard next.isLetter, let tag = parseTag(chars, from: index + 1) else {
                    text.append(char)
                    index += 1
                    continue
                }
                flushText()
                if tag.selfClosing || voidElements.contains(tag.name) {
                    stack[stack.count - 1].children.append(.element(tag.name, tag.attributes, []))
                } else {
                    stack.append(OpenElement(name: tag.name, attributes: tag.attributes))
                }
                index = tag.end
            }
            flushText()
            guard stack.count == 1 else { return nil }
            return stack[0].children
        }

        /// Reads an opening tag whose name starts at `start`, returning the
        /// index just past its `>`.
        private struct OpenElement {
            let name: String
            let attributes: [String: String]
            var children: [Node] = []
        }

        private struct Tag {
            let name: String
            let attributes: [String: String]
            let selfClosing: Bool
            /// Index just past the tag's `>`.
            let end: Int
        }

        private static func parseTag(_ chars: [Character], from start: Int) -> Tag? {
            var index = start
            var name = ""
            while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "-" {
                name.append(chars[index])
                index += 1
            }
            var attributes: [String: String] = [:]
            while index < chars.count {
                let char = chars[index]
                if char.isWhitespace {
                    index += 1
                    continue
                }
                if char == ">" {
                    return Tag(name: name.lowercased(), attributes: attributes, selfClosing: false, end: index + 1)
                }
                if char == "/", index + 1 < chars.count, chars[index + 1] == ">" {
                    return Tag(name: name.lowercased(), attributes: attributes, selfClosing: true, end: index + 2)
                }
                var attribute = ""
                while index < chars.count, !chars[index].isWhitespace, !"=>/".contains(chars[index]) {
                    attribute.append(chars[index])
                    index += 1
                }
                guard !attribute.isEmpty else { return nil }
                var value = ""
                if index < chars.count, chars[index] == "=" {
                    index += 1
                    if index < chars.count, chars[index] == "\"" || chars[index] == "'" {
                        let quote = chars[index]
                        index += 1
                        while index < chars.count, chars[index] != quote {
                            value.append(chars[index])
                            index += 1
                        }
                        guard index < chars.count else { return nil }
                        index += 1
                    } else {
                        while index < chars.count, !chars[index].isWhitespace, chars[index] != ">" {
                            value.append(chars[index])
                            index += 1
                        }
                    }
                }
                attributes[attribute.lowercased()] = decodeEntities(value)
            }
            return nil
        }

        private static func decodeEntities(_ text: String) -> String {
            guard text.contains("&") else { return text }
            var result = ""
            var index = text.startIndex
            while index < text.endIndex {
                let char = text[index]
                guard char == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                    result.append(char)
                    index = text.index(after: index)
                    continue
                }
                let entity = String(text[text.index(after: index) ..< semicolon])
                if let decoded = decode(entity) {
                    result.append(decoded)
                    index = text.index(after: semicolon)
                } else {
                    result.append(char)
                    index = text.index(after: index)
                }
            }
            return result
        }

        private static func decode(_ entity: String) -> Character? {
            switch entity {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos": return "'"
            case "nbsp": return "\u{00A0}"
            default:
                guard entity.hasPrefix("#") else { return nil }
                let digits = entity.dropFirst()
                let value = digits.first == "x" || digits.first == "X"
                    ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                return value.flatMap { Unicode.Scalar($0) }.map { Character($0) }
            }
        }
    }
}

/// One stint in the description editor: what the stored description was, how
/// it is being edited, and the text in the editor. Shared by the iOS sheet and
/// the Mac detail view (#277).
struct DescriptionEditSession: Equatable {
    enum Mode: Equatable {
        /// No HTML: the text is the description, edited as is.
        case plainText
        /// Web-editor HTML, edited as Markdown-style text.
        case formatted
        /// HTML the formatted text cannot represent, edited as raw HTML so
        /// nothing in it is lost.
        case rawHTML
    }

    let original: String
    let mode: Mode
    let initialText: String
    var text: String

    init(stored: String) {
        original = stored
        if !RichTextRenderer.containsHTML(stored) {
            mode = .plainText
            initialText = stored
        } else if let editable = DescriptionMarkup.editableText(fromHTML: stored) {
            mode = .formatted
            initialText = editable
        } else {
            mode = .rawHTML
            initialText = stored
        }
        text = initialText
    }

    /// The description to store for what is in the editor. Untouched text
    /// gives back the original byte for byte, so opening the editor and
    /// closing it again never rewrites the web app's markup.
    var storedDescription: String {
        guard text != initialText else { return original }
        switch mode {
        case .plainText, .rawHTML:
            return text
        case .formatted:
            return DescriptionMarkup.html(fromEditableText: text)
        }
    }
}
