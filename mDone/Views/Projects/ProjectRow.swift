import SwiftUI

struct ProjectRow: View {
    let project: Project
    let taskCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(projectColor)
                .frame(width: 12, height: 12)

            Text(project.title)
                .font(.body)

            Spacer()

            if taskCount > 0 {
                Text("\(taskCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var projectColor: Color {
        guard let hex = project.hexColor, !hex.isEmpty else { return Color.accentColor }
        return Color(hex: hex)
    }
}
