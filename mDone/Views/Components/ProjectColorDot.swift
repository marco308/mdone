import SwiftUI

/// The small round color marker shown beside a project in lists and the Mac
/// sidebar.
///
/// A project with no color assigned draws a hollow ring instead of a filled
/// circle. Filling it with the accent color, as every call site used to, made an
/// uncolored project identical to one the user had deliberately colored blue,
/// since the accent color is also the first swatch in `ColorSwatchPicker` (#211).
/// The ring keeps the marker's footprint, so titles stay aligned with their
/// colored neighbors, and no assignable hex can render as an outline.
struct ProjectColorDot: View {
    let project: Project
    var size: CGFloat = 12

    var body: some View {
        Group {
            if let hex = project.normalizedHexColor {
                Circle().fill(Color(hex: hex))
            } else {
                Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
