import Foundation
import SwiftUI

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

    static func containsHTML(_ source: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "<[a-zA-Z/][^>]*>") else { return false }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
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
        let styled = """
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; font-size: 16px; line-height: 1.4; }
          p, ul, ol { margin: 0 0 8px 0; }
          ul, ol { padding-left: 1.4em; }
          code { font-family: ui-monospace, Menlo, monospace; }
        </style>
        \(html)
        """
        guard let data = styled.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let nsAttr = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        let fullRange = NSRange(location: 0, length: nsAttr.length)
        nsAttr.removeAttribute(.foregroundColor, range: fullRange)
        nsAttr.removeAttribute(.backgroundColor, range: fullRange)
        trimTrailingNewlines(nsAttr)
        return AttributedString(nsAttr)
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
