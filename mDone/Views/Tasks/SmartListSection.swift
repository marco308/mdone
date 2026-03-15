import SwiftUI

struct SmartListSection: View {
    let title: String
    let tasks: [VTask]
    let accentColor: Color

    var body: some View {
        Section {
            ForEach(tasks) { task in
                TaskRow(task: task)
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
        }
    }
}
