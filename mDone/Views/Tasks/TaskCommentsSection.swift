import SwiftUI

/// A task's comments in its detail view (#2): who wrote each and when, a box
/// to add one, and Edit and Delete on the user's own. Comments save as soon
/// as they are sent, apart from the task form's Save.
///
/// Comment text is HTML, and the HTML import behind `RichTextRenderer` must
/// not run inside a SwiftUI update (see `RichDescriptionView`), so each
/// comment is rendered once, in the task that loads or changes it, and kept
/// in `rendered`.
struct TaskCommentsSection: View {
    @Environment(AppState.self) private var appState
    let task: VTask

    private enum LoadState {
        case loading, loaded, failed
    }

    @State private var comments: [TaskComment] = []
    @State private var rendered: [Int64: AttributedString] = [:]
    @State private var loadState: LoadState = .loading
    @State private var draft = ""
    @State private var isPosting = false
    @State private var editing: TaskComment?
    @State private var pendingDelete: TaskComment?

    var body: some View {
        Section {
            switch loadState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading comments…")
                        .foregroundStyle(.secondary)
                }
            case .failed:
                HStack {
                    Text("Comments could not be loaded.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await load() }
                    }
                }
            case .loaded:
                if comments.isEmpty {
                    Text("No comments yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }

            composer
        } header: {
            Text("Comments")
        }
        .task(id: task.id) {
            await load()
        }
        .sheet(item: $editing) { comment in
            CommentEditSheet(comment: comment) { text, isHTML in
                await save(comment, text: text, isHTML: isHTML)
            }
        }
        .confirmationDialog(
            "Delete Comment?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { comment in
            Button("Delete", role: .destructive) {
                Task { await delete(comment) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This action cannot be undone.")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .lineLimit(1 ... 6)
                .disabled(isPosting)
            Button {
                Task { await post() }
            } label: {
                if isPosting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.borderless)
            .disabled(isPosting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send comment")
        }
    }

    private func commentRow(_ comment: TaskComment) -> some View {
        let isOwn = comment.author != nil && comment.author?.id == appState.currentUser?.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.author?.displayName ?? String(localized: "Unknown"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let created = comment.created {
                    Text(created, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if comment.isEdited {
                    Text("edited")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isOwn {
                    Menu {
                        ownCommentActions(comment)
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .accessibilityLabel("Comment actions")
                }
            }
            Text(rendered[comment.id] ?? AttributedString())
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if isOwn {
                ownCommentActions(comment)
            }
        }
    }

    @ViewBuilder
    private func ownCommentActions(_ comment: TaskComment) -> some View {
        Button {
            editing = comment
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            pendingDelete = comment
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func load() async {
        if comments.isEmpty {
            loadState = .loading
        }
        async let user: Void = appState.loadSignedInUserIfNeeded()
        let loaded = await appState.loadComments(taskId: task.id)
        await user
        guard let loaded else {
            if comments.isEmpty {
                loadState = .failed
            }
            return
        }
        rendered = Dictionary(
            loaded.map { ($0.id, RichTextRenderer.render($0.comment)) },
            uniquingKeysWith: { first, _ in first }
        )
        comments = loaded
        loadState = .loaded
    }

    private func post() async {
        isPosting = true
        defer { isPosting = false }
        guard let comment = await appState.addComment(taskId: task.id, text: draft) else { return }
        rendered[comment.id] = RichTextRenderer.render(comment.comment)
        comments.append(comment)
        loadState = .loaded
        draft = ""
    }

    private func save(_ comment: TaskComment, text: String, isHTML: Bool) async -> Bool {
        guard let updated = await appState.editComment(
            taskId: task.id, commentId: comment.id, text: text, isHTML: isHTML
        ) else { return false }
        rendered[updated.id] = RichTextRenderer.render(updated.comment)
        if let index = comments.firstIndex(where: { $0.id == updated.id }) {
            comments[index] = updated
        }
        return true
    }

    private func delete(_ comment: TaskComment) async {
        guard await appState.deleteComment(taskId: task.id, commentId: comment.id) else { return }
        comments.removeAll { $0.id == comment.id }
        rendered[comment.id] = nil
    }
}

/// Edits one comment. The text is the same light markup a description uses;
/// a comment that markup cannot hold (a table, an image) is edited as its raw
/// HTML instead, so saving never drops part of it.
private struct CommentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String, Bool) async -> Bool

    @State private var text: String
    @State private var isSaving = false
    private let isHTML: Bool

    init(comment: TaskComment, onSave: @escaping (String, Bool) async -> Bool) {
        self.onSave = onSave
        if let editable = DescriptionMarkup.editableText(fromHTML: comment.comment) {
            _text = State(initialValue: editable)
            isHTML = false
        } else {
            _text = State(initialValue: comment.comment)
            isHTML = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                if isHTML {
                    Text("This comment has formatting mDone can't edit, so it is shown as HTML.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Comment")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            let saved = await onSave(text, isHTML)
                            isSaving = false
                            if saved {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 280)
        #endif
    }
}
