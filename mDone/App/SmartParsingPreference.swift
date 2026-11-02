import Foundation

/// The "Smart parsing in quick add" setting (#215). Off by default: with it
/// off, the quick-add bar creates the title verbatim, exactly as before.
enum SmartParsingPreference {
    static let storageKey = "smartQuickAddParsing"
    static let defaultValue = false

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}

/// What the quick-add bar sends to `AppState.createTask`, worked out from the
/// typed text, the parse (when smart parsing is on) and the chips the user
/// rejected. Pure, so the #223 behaviour rows are unit-testable without a view.
struct QuickAddSubmission: Equatable {
    let title: String
    let projectId: Int64
    let dueDate: Date?
    let priority: Int64
    let labelIds: [Int64]

    /// - Parameters:
    ///   - parse: the parser's result for `text`, or nil when smart parsing
    ///     is off. With nil, the title is the trimmed text and the list's
    ///     defaults apply, as they always have.
    ///   - rejected: fields whose chip the user dismissed. Their words stay
    ///     in the title and their values are dropped.
    ///   - projectId: the project of the list being viewed. A parsed project
    ///     beats it.
    ///   - defaultDueDate: the list's default (the Inbox setting). A parsed
    ///     date beats it.
    static func make(
        text: String,
        parse: SmartTaskParse?,
        rejected: Set<SmartTaskParse.Field>,
        projectId: Int64,
        defaultDueDate: Date?
    ) -> QuickAddSubmission? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parse else {
            return QuickAddSubmission(
                title: trimmed, projectId: projectId, dueDate: defaultDueDate, priority: 0, labelIds: []
            )
        }
        let accepted = parse.rejecting(rejected)
        return QuickAddSubmission(
            title: accepted.title,
            projectId: accepted.projectId ?? projectId,
            dueDate: accepted.dueDate ?? defaultDueDate,
            priority: Int64(accepted.priority ?? 0),
            labelIds: accepted.labelIds
        )
    }
}
