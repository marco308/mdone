import SwiftUI

/// The description preview: prose through the rich-text renderer, and any
/// checklist in it as native rows that can be ticked in place (issue #200).
///
/// `onToggle` receives the item's document-order index, the one
/// `DescriptionChecklist.toggling(itemAt:in:)` expects. Pass `nil` for a
/// read-only preview.
///
/// The rendered segments live in `@State` and are refreshed by a task when
/// the HTML changes, never computed in `body`. The HTML import behind
/// `RichTextRenderer` pumps a nested run loop, which inside a SwiftUI update
/// either traps ("setting value during update", when it runs in a `ForEach`
/// closure) or silently loses the update (the ticks stayed stale after a
/// toggle while the summary beside them redrew). The first render happens
/// in `init`, the way the detail views always rendered on creation, so the
/// preview does not flash empty.
struct RichDescriptionView: View {
    let html: String
    var onToggle: ((Int) -> Void)?

    @State private var rendered: [Rendered]
    @State private var renderedHTML: String

    init(html: String, onToggle: ((Int) -> Void)? = nil) {
        self.html = html
        self.onToggle = onToggle
        _rendered = State(initialValue: Self.render(html))
        _renderedHTML = State(initialValue: html)
    }

    private struct Rendered: Identifiable {
        enum Content {
            case text(AttributedString)
            case checklist([DescriptionChecklist.Item])
        }

        let id: Int
        let content: Content
    }

    private static func render(_ html: String) -> [Rendered] {
        DescriptionChecklist.segments(of: html).enumerated().map { index, segment in
            switch segment {
            case let .html(fragment):
                Rendered(id: index, content: .text(RichTextRenderer.render(fragment)))
            case let .checklist(items):
                Rendered(id: index, content: .checklist(items))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rendered) { segment in
                switch segment.content {
                case let .text(attributed):
                    Text(attributed)
                        .font(.body)
                        .textSelection(.enabled)
                case let .checklist(items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            ChecklistItemRow(item: item) {
                                onToggle?(item.id)
                            }
                            .disabled(onToggle == nil)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: html) {
            guard html != renderedHTML else { return }
            rendered = Self.render(html)
            renderedHTML = html
        }
    }
}

private struct ChecklistItemRow: View {
    let item: DescriptionChecklist.Item
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(item.text)
                    .font(.body)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.text)
        .accessibilityValue(item.isChecked ? Text("Done") : Text("Not done"))
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        .accessibilityHint("Double tap to toggle")
    }
}

/// "2 of 3 done" with a thin progress bar, the same summary Vikunja's web
/// app shows above a description with a checklist.
struct ChecklistSummaryView: View {
    let checklist: DescriptionChecklist

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(checklist.doneCount) of \(checklist.totalCount) done")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(checklist.isComplete ? Color.green : Color.secondary)
            ProgressView(value: checklist.fraction)
                .tint(checklist.isComplete ? .green : .accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checklist")
        .accessibilityValue("\(checklist.doneCount) of \(checklist.totalCount) done")
    }
}

/// The compact "2/3" badge task rows and Kanban cards show for a task whose
/// description holds a checklist.
struct ChecklistCountBadge: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.square")
            Text("\(done)/\(total)")
                .monospacedDigit()
        }
        .foregroundStyle(done == total ? Color.green : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) checklist items done")
    }
}
