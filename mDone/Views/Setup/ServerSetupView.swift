import SwiftUI

struct ServerSetupView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiToken = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var authMode: AuthMode = .credentials

    enum AuthMode: String, CaseIterable {
        case credentials = "Login"
        case apiToken = "API Token"
    }

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

                        Picker("Auth Method", selection: $authMode) {
                            ForEach(AuthMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if authMode == .credentials {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Username")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                TextField("Username", text: $username)
                                    .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                    .textContentType(.username)
                                    .textInputAutocapitalization(.never)
                                #endif
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                    .textContentType(.password)
                                #endif
                            }
                        } else {
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
                    .disabled(isFormIncomplete || isConnecting)
                    .padding(.horizontal)

                    if authMode == .credentials {
                        Text("Login with your Vikunja username and password for full functionality")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        Text("API tokens have limited permissions. Use Login for full functionality including task reordering.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Spacer()
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var isFormIncomplete: Bool {
        if serverURL.isEmpty { return true }
        if authMode == .credentials {
            return username.isEmpty || password.isEmpty
        } else {
            return apiToken.isEmpty
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }

        Task {
            do {
                if authMode == .credentials {
                    try await appState.loginWithCredentials(
                        serverURL: url,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                } else {
                    let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await appState.login(serverURL: url, token: token)
                }
            } catch {
                #if DEBUG
                print("[mDone] Login error: \(error)")
                #endif
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
