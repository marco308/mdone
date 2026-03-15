import SwiftUI

struct ServerSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL = ""
    @State private var apiToken = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    // Logo area
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor)

                        Text("mDone")
                            .font(.largeTitle.bold())

                        Text("Connect to your Vikunja server")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            TextField("https://vikunja.example.com", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .textContentType(.URL)
                                #endif
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Token")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            SecureField("Paste your API token", text: $apiToken)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .textContentType(.password)
                                #endif
                                .autocorrectionDisabled()
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                    .padding(.horizontal)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        connect()
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(serverURL.isEmpty || apiToken.isEmpty || isConnecting)
                    .padding(.horizontal)

                    Text("You can create an API token in your Vikunja instance under Settings > API Tokens")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                try await appState.login(serverURL: url, token: token)
            } catch {
                print("[mDone] Login error: \(error)")
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
