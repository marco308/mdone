import SwiftUI

struct LabelChip: View {
    let label: VLabel

    var body: some View {
        Text(label.title)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(label.color.opacity(0.2))
            .foregroundStyle(label.color)
            .clipShape(Capsule())
    }
}
