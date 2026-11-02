import SwiftUI

/// The line under the description editor saying how the text is written
/// (#277). Plain-text descriptions need no hint.
struct DescriptionEditHint: View {
    let mode: DescriptionEditSession.Mode

    var body: some View {
        switch mode {
        case .plainText:
            EmptyView()
        case .formatted:
            // A String, not a literal: a literal would render the examples as
            // Markdown instead of showing the characters to type.
            Text(
                String(
                    localized: "Formatting: **bold**, *italic*, [link](https://example.com), - bullet, 1. numbered, - [ ] checklist"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .rawHTML:
            Text("This description has formatting mDone cannot edit, so it is shown as HTML.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
