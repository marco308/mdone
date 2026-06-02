import SwiftUI

/// Create or edit a project. Pass `project: nil` to create a new project, or an
/// existing project to edit it. Shared by iOS and macOS.
struct ProjectEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// The project being edited, or `nil` when creating a new one.
    let project: Project?

    @State private var title: String
    @State private var description: String
    @State private var colorHex: String
    @State private var isFavorite: Bool
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(project: Project? = nil) {
        self.project = project
        _title = State(initialValue: project?.title ?? "")
        _description = State(initialValue: project?.description ?? "")
        _colorHex = State(initialValue: project?.hexColor ?? "")
        _isFavorite = State(initialValue: project?.isFavorite ?? false)
    }

    private var isEditing: Bool {
        project != nil
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Project name", text: $title)
                        .focused($titleFocused)
                }

                Section("Description") {
                    TextField("Optional", text: $description, axis: .vertical)
                        .lineLimit(2 ... 5)
                }

                Section("Color") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }

                Section {
                    Toggle(isOn: $isFavorite) {
                        Label("Add to Favorites", systemImage: "star")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Project" : "New Project")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                    }
                }
                .onAppear {
                    if !isEditing { titleFocused = true }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }

    private func save() {
        isSaving = true
        Task {
            if let project {
                await appState.updateProject(
                    project,
                    title: title,
                    description: description,
                    hexColor: colorHex,
                    isFavorite: isFavorite
                )
            } else {
                await appState.createProject(
                    title: title,
                    description: description,
                    hexColor: colorHex,
                    isFavorite: isFavorite
                )
            }
            dismiss()
        }
    }
}
