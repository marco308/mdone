import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum RichTextRenderer {
    static func render(_ source: String) -> AttributedString {
        if containsHTML(source), let rendered = renderHTML(source) {
            return rendered
        }
        return renderMarkdown(source)
    }

    /// Closing tag like </p> or </strong>. Markdown autolinks (<https://example.com>)
    /// have no closing form, so requiring one keeps them on the Markdown path.
    private static let htmlClosingTagPattern = try? NSRegularExpression(pattern: "</[a-zA-Z][a-zA-Z0-9]*\\s*>")

    static func containsHTML(_ source: String) -> Bool {
        guard let regex = htmlClosingTagPattern else { return false }
        let range = NSRange(source.startIndex ..< source.endIndex, in: source)
        return regex.firstMatch(in: source, options: [], range: range) != nil
    }

    private static func renderMarkdown(_ source: String) -> AttributedString {
        (
            try? AttributedString(markdown: source, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            ))
        ) ?? AttributedString(source)
    }

    private static func renderHTML(_ html: String) -> AttributedString? {
        let wrapped = """
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; }
          p, ul, ol { margin: 0 0 8px 0; }
          ul, ol { padding-left: 1.4em; }
          code { font-family: ui-monospace, Menlo, monospace; }
        </style>
        \(html)
        """
        guard let data = wrapped.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let nsAttr = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        let fullRange = NSRange(location: 0, length: nsAttr.length)
        nsAttr.removeAttribute(.foregroundColor, range: fullRange)
        nsAttr.removeAttribute(.backgroundColor, range: fullRange)
        rewriteFontsForDynamicType(nsAttr)
        trimTrailingNewlines(nsAttr)
        return AttributedString(nsAttr)
    }

    private static func rewriteFontsForDynamicType(_ attr: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attr.length)
        #if canImport(UIKit)
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        attr.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let traits = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            var keptTraits: UIFontDescriptor.SymbolicTraits = []
            if traits.contains(.traitBold) {
                keptTraits.insert(.traitBold)
            }
            if traits.contains(.traitItalic) {
                keptTraits.insert(.traitItalic)
            }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(keptTraits) ?? baseFont.fontDescriptor
            attr.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 0), range: range)
        }
        #elseif canImport(AppKit)
        let baseFont = NSFont.preferredFont(forTextStyle: .body)
        attr.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            var keptTraits: NSFontDescriptor.SymbolicTraits = []
            if traits.contains(.bold) {
                keptTraits.insert(.bold)
            }
            if traits.contains(.italic) {
                keptTraits.insert(.italic)
            }
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(keptTraits)
            let font = NSFont(descriptor: descriptor, size: 0) ?? baseFont
            attr.addAttribute(.font, value: font, range: range)
        }
        #endif
    }

    private static func trimTrailingNewlines(_ attr: NSMutableAttributedString) {
        let string = attr.string
        var end = string.endIndex
        while end > string.startIndex {
            let previous = string.index(before: end)
            if string[previous].isNewline {
                end = previous
            } else {
                break
            }
        }
        let trimmedLength = string.distance(from: string.startIndex, to: end)
        if trimmedLength < attr.length {
            attr.deleteCharacters(in: NSRange(location: trimmedLength, length: attr.length - trimmedLength))
        }
    }
}
