import SwiftUI

/// Shared label display and picker entry point for iOS and macOS task detail.
/// It always reads the live task from `AppState` so optimistic changes remain
/// visible while a detail editor is open.
struct TaskLabelsSection: View {
    @Environment(AppState.self) private var appState
    let task: VTask

    @State private var isShowingPicker = false

    private var liveTask: VTask {
        appState.tasks.first(where: { $0.id == task.id }) ?? task
    }

    private var assignedLabels: [VLabel] {
        var seenIds: Set<Int64> = []
        return (liveTask.labels ?? []).filter { seenIds.insert($0.id).inserted }
    }

    var body: some View {
        Section("Labels") {
            if assignedLabels.isEmpty {
                Text("No labels assigned")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(assignedLabels) { label in
                        LabelChip(label: label)
                    }
                }
            }

            Button {
                isShowingPicker = true
            } label: {
                Label(assignedLabels.isEmpty ? "Add Labels" : "Manage Labels", systemImage: "tag")
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            TaskLabelPicker(task: liveTask)
        }
    }
}

private struct TaskLabelPicker: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let task: VTask

    @State private var searchText = ""
    @State private var pendingLabelIds: Set<Int64> = []
    @State private var isCreating = false

    private var liveTask: VTask {
        appState.tasks.first(where: { $0.id == task.id }) ?? task
    }

    private var assignedLabelIds: Set<Int64> {
        Set((liveTask.labels ?? []).map(\.id))
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleLabels: [VLabel] {
        let sorted = appState.labels.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard !trimmedSearchText.isEmpty else { return sorted }
        return sorted.filter { $0.title.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var canCreateLabel: Bool {
        guard !trimmedSearchText.isEmpty else { return false }
        return !appState.labels.contains {
            $0.title.caseInsensitiveCompare(trimmedSearchText) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Available Labels") {
                    if visibleLabels.isEmpty {
                        Text(trimmedSearchText.isEmpty ? "No labels available" : "No matching labels")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleLabels) { label in
                            labelRow(label)
                        }
                    }
                }

                if canCreateLabel {
                    Section {
                        Button(action: createLabel) {
                            HStack {
                                Label("Create \"\(trimmedSearchText)\"", systemImage: "plus.circle")
                                Spacer()
                                if isCreating {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(isCreating)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search or create labels")
            .navigationTitle("Labels")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #elseif os(macOS)
        .frame(minWidth: 400, minHeight: 440)
        #endif
    }

    private func labelRow(_ label: VLabel) -> some View {
        let isAssigned = assignedLabelIds.contains(label.id)
        let isPending = pendingLabelIds.contains(label.id)

        return Button {
            guard pendingLabelIds.insert(label.id).inserted else { return }
            Task {
                await appState.setLabel(label, on: liveTask, present: !isAssigned)
                pendingLabelIds.remove(label.id)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(label.color)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(label.title)
                    .foregroundStyle(.primary)
                Spacer()
                if isPending {
                    ProgressView()
                        .controlSize(.small)
                } else if isAssigned {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPending)
        .accessibilityLabel(isAssigned ? "Remove \(label.title)" : "Assign \(label.title)")
    }

    private func createLabel() {
        guard !trimmedSearchText.isEmpty, !isCreating else { return }
        let title = trimmedSearchText
        isCreating = true
        Task {
            if await appState.createAndAssignLabel(title: title, to: liveTask) != nil {
                searchText = ""
            }
            isCreating = false
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let positions = layout(sizes: sizes, containerWidth: bounds.width).positions

        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y),
                proposal: .unspecified
            )
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if x + size.width > containerWidth, x > 0 {
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxHeight = max(maxHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (positions, CGSize(width: maxWidth, height: y + maxHeight))
    }
}
