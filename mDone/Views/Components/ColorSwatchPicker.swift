import SwiftUI

/// Horizontal preset colour picker for projects. Binds to a hex string where an
/// empty string means "no colour". Presets are stored as `#RRGGBB`, the format
/// Vikunja round-trips (max length 7).
struct ColorSwatchPicker: View {
    @Binding var selectedHex: String

    /// Preset palette. Kept to a curated set for consistency with the Vikunja web UI.
    static let palette: [String] = [
        "#4772FA", "#34C759", "#FF8C00", "#FF4444",
        "#9B59B6", "#00C2C7", "#FF6BAA", "#5856D6",
        "#F4B400", "#30D158", "#A0522D", "#8E8E93",
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                swatch(hex: "", isNone: true)
                ForEach(Self.palette, id: \.self) { hex in
                    swatch(hex: hex, isNone: false)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func swatch(hex: String, isNone: Bool) -> some View {
        let selected = normalized(selectedHex) == normalized(hex)
        return Button {
            selectedHex = hex
        } label: {
            ZStack {
                Circle()
                    .fill(isNone ? Color.gray.opacity(0.15) : Color(hex: hex))
                    .frame(width: 30, height: 30)
                if isNone {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                if selected {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isNone ? "No colour" : "Colour \(hex)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Compares hex strings ignoring a leading `#` and case.
    private func normalized(_ hex: String) -> String {
        hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
    }
}
