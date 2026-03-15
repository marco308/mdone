import SwiftUI

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.primary.colorInvert()
                .opacity(0.8)

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)

                Text("Loading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}
