import SwiftUI

/// A round badge with a user's initials. Drawn locally rather than loading
/// Vikunja's avatar images, so showing assignees costs no requests.
struct AssigneeAvatar: View {
    let user: User
    var size: CGFloat = 22

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .brown]

    /// Keyed on the id so a person keeps their colour across screens.
    private var color: Color {
        Self.palette[Int(user.id.magnitude % UInt64(Self.palette.count))]
    }

    var body: some View {
        Text(user.initials)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityLabel(user.displayName)
    }
}

/// Overlapping avatars for a task row: up to three, then "+N".
struct AssigneeStack: View {
    let users: [User]
    var size: CGFloat = 20
    private let visibleLimit = 3

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(users.prefix(visibleLimit)) { user in
                AssigneeAvatar(user: user, size: size)
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            if users.count > visibleLimit {
                Text("+\(users.count - visibleLimit)")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, size * 0.4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Assigned to \(users.map(\.displayName).joined(separator: ", "))"))
    }
}

/// The Assignees section of a task's detail view, shared by the iOS sheet,
/// the iPad pane and the macOS detail view. Renders nothing while Team
/// features is off, so personal use looks exactly as it did.
struct TaskAssigneesSection: View {
    @Environment(AppState.self) private var appState
    @AppStorage(TeamFeaturesPreference.storageKey) private var teamFeatures = TeamFeaturesPreference.defaultValue
    let task: VTask

    @State private var isPicking = false

    /// The live copy, so a change made in the picker shows straight away.
    private var assignees: [User] {
        (appState.tasks.first(where: { $0.id == task.id }) ?? task).assignees ?? []
    }

    var body: some View {
        if teamFeatures {
            Section("Assignees") {
                ForEach(assignees) { user in
                    HStack(spacing: 10) {
                        AssigneeAvatar(user: user, size: 26)
                        Text(user.displayName)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    isPicking = true
                } label: {
                    if assignees.isEmpty {
                        Label("Assign", systemImage: "person.badge.plus")
                    } else {
                        Label("Edit Assignees", systemImage: "person.2")
                    }
                }
                .sheet(isPresented: $isPicking) {
                    AssigneePickerSheet(projectId: task.projectId, target: .task(task))
                }
            }
        }
    }
}

/// Picks who a task is assigned to from the people who can see its project.
///
/// For an existing task every tap is applied at once through the bulk
/// assignee endpoint, the way the label picker works, so Done just closes.
/// For a task not created yet it edits a draft list the create sends later.
struct AssigneePickerSheet: View {
    enum Target {
        case task(VTask)
        case draft(Binding<[User]>)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let projectId: Int64
    let target: Target

    @State private var users: [User] = []
    @State private var isLoading = true
    @State private var query = ""
    @State private var isSaving = false

    private var selected: [User] {
        switch target {
        case let .task(task):
            (appState.tasks.first(where: { $0.id == task.id }) ?? task).assignees ?? []
        case let .draft(binding):
            binding.wrappedValue
        }
    }

    /// The project's people plus anyone already assigned who is not among
    /// them (someone the project was unshared from), so they can be removed.
    private var candidates: [User] {
        let known = Set(users.map(\.id))
        return users + selected.filter { !known.contains($0.id) }
    }

    private var visibleUsers: [User] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || ($0.username ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if candidates.count > 8 {
                    Section {
                        TextField("Search people", text: $query)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    if isLoading, candidates.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if visibleUsers.isEmpty {
                        Text(query.isEmpty ? "No one else can see this project yet." : "No one matches.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visibleUsers) { user in
                        row(user)
                    }
                } footer: {
                    Text("Only people this project is shared with in Vikunja can be assigned.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Assignees")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task {
                    users = appState.assignableUsers[projectId] ?? []
                    users = await appState.loadAssignableUsers(projectId: projectId)
                    isLoading = false
                }
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 380)
        #endif
    }

    private func row(_ user: User) -> some View {
        let isSelected = selected.contains(user)
        return Button {
            toggle(user)
        } label: {
            HStack(spacing: 12) {
                AssigneeAvatar(user: user, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .foregroundStyle(.primary)
                    if let username = user.username, !username.isEmpty, username != user.displayName {
                        Text(verbatim: "@\(username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(user.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ user: User) {
        var updated = selected
        if let index = updated.firstIndex(of: user) {
            updated.remove(at: index)
        } else {
            updated.append(user)
        }
        switch target {
        case let .draft(binding):
            binding.wrappedValue = updated
        case let .task(task):
            isSaving = true
            Task { @MainActor in
                await appState.setAssignees(updated, on: task)
                isSaving = false
            }
        }
    }
}
