import Foundation

/// Parsing for Vikunja's `hex_color`, shared by every model that carries one.
///
/// Lives in one place so tasks and projects cannot drift apart on what counts
/// as a usable color: both render an unparseable value as "no color" rather
/// than guessing, and `Color(hex:)` would otherwise turn anything that is not
/// 3, 6 or 8 hex digits into a stray mid-gray.
enum HexColor {
    /// The color stripped of an optional single leading `#`, or `nil` when the
    /// value is missing, empty or not a valid 3/6/8-digit hex.
    ///
    /// Only one `#`, and only at the front, is removed: a value like `##FF0000`
    /// or `#FF0000#` is malformed, not a color with decoration, so it resolves
    /// to `nil` the same as any other input we cannot read.
    static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        guard [3, 6, 8].contains(trimmed.count),
              trimmed.allSatisfy(\.isHexDigit)
        else { return nil }
        return trimmed
    }
}
