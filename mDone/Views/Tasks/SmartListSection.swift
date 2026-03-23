import SwiftUI

struct SmartListSection: View {
    @Environment(AppState.self) private var appState
    let title: String
    let tasks: [VTask]
    let accentColor: Color

    var body: some View {
        Section {
            ForEach(tasks) { task in
                TaskRow(task: task)
            }
            .onMove { source, destination in
                handleMove(from: source, to: destination)
            }
        } header: {
            HStack {
                Text(title)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(accentColor)

                Spacer()

                Text("\(tasks.count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(tasks.count) \(tasks.count == 1 ? "task" : "tasks")")
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func handleMove(from source: IndexSet, to destination: Int) {
        var reordered = tasks
        reordered.move(fromOffsets: source, toOffset: destination)

        guard let movedIndex = source.first else { return }
        let task = tasks[movedIndex]

        let actualDestination = movedIndex < destination ? destination - 1 : destination
        let newPosition: Double
        if reordered.count <= 1 {
            newPosition = 0
        } else if actualDestination == 0 {
            newPosition = (reordered[1].position ?? 1) - 1
        } else if actualDestination >= reordered.count - 1 {
            newPosition = (reordered[reordered.count - 2].position ?? Double(reordered.count - 2)) + 1
        } else {
            let before = reordered[actualDestination - 1].position ?? Double(actualDestination - 1)
            let after = reordered[actualDestination + 1].position ?? Double(actualDestination + 1)
            newPosition = (before + after) / 2
        }

        let viewId: Int64 = 0

        Task {
            await appState.moveTask(task, toPosition: newPosition, viewId: viewId)
        }
    }
}
