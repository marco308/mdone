import SwiftUI

struct ErrorBanner: View {
    let error: NetworkError
    var onDismiss: () -> Void
    var onRetry: (() -> Void)?

    @State private var isVisible = false

    private var backgroundColor: Color {
        switch error {
        case .unauthorized, .invalidURL:
            .red
        case .networkUnavailable, .timeout, .serverUnreachable:
            .orange
        default:
            .red
        }
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: error.iconName)
                        .font(.title3)
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.errorDescription ?? "Something went wrong.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        if let suggestion = error.recoverySuggestion {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isVisible = false
                        }
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(6)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let onRetry {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isVisible = false
                        }
                        onDismiss()
                        onRetry()
                    } label: {
                        Text("Try Again")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(backgroundColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(backgroundColor.gradient, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                if !error.isCritical {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isVisible = false
                        }
                        onDismiss()
                    }
                }
            }
        }
    }

    init(error: NetworkError, onDismiss: @escaping () -> Void, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onDismiss = onDismiss
        self.onRetry = onRetry
        _isVisible = State(initialValue: true)
    }
}

// MARK: - View Modifier

struct ErrorBannerModifier: ViewModifier {
    @Binding var error: NetworkError?
    var onRetry: (() -> Void)?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let currentError = error {
                ErrorBanner(
                    error: currentError,
                    onDismiss: { error = nil },
                    onRetry: onRetry
                )
                .padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: error != nil)
    }
}

extension View {
    func errorBanner(_ error: Binding<NetworkError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(ErrorBannerModifier(error: error, onRetry: onRetry))
    }
}
