import SwiftUI

struct ServerSetupView: View {
    @Environment(AppState.self) private var appState
    // When the session expires we keep the server URL in AuthService so the
    // user doesn't have to retype it — prefill it here on appear (issue #80).
    @State private var serverURL = AuthService.shared.getServerURL() ?? ""
    @State private var username = ""
    @State private var password = ""
    @State private var apiToken = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var authMode: AuthMode = .credentials

    /// What this server actually offers. Starts at the conservative default,
    /// which matches how the screen behaved before issue #153: credentials
    /// form, no SSO. A failed probe returns here rather than blocking anyone.
    @State private var authOptions: AuthOptions = .unknownServer
    @State private var probeTask: Task<Void, Never>?

    /// Injectable so previews and any future UI test can avoid the real system
    /// auth sheet, which cannot be driven from a test.
    @State private var webAuthenticator: any WebAuthenticating

    init(webAuthenticator: (any WebAuthenticating)? = nil) {
        _webAuthenticator = State(initialValue: webAuthenticator ?? WebAuthenticator())
    }

    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 64

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
                            .font(.system(size: logoSize))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)

                        Text("mDone")
                            .font(.largeTitle.bold())

                        Text("Connect to your Vikunja server")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if ssoIsPrimary {
                        ssoSection
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
                                .onChange(of: serverURL) { _, _ in checkServer(debounce: true) }
                                .onSubmit { checkServer(debounce: false) }
                        }

                        // Only worth showing when there is a choice to make.
                        if availableModes.count > 1 {
                            Picker("Auth Method", selection: $authMode) {
                                ForEach(availableModes, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if authMode == .credentials, authOptions.showsCredentials {
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

                    if !ssoIsPrimary {
                        ssoSection
                    }

                    if authMode == .credentials {
                        Text("Login with your Vikunja username and password for full functionality")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        Text(
                            "API tokens have limited permissions. Use Login for full functionality including task reordering."
                        )
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
            // A prefilled URL (issue #80, after a session expires) deserves an
            // immediate probe rather than waiting for a keystroke that may
            // never come.
            .task { checkServer(debounce: false) }
            .onChange(of: authOptions) { _, _ in
                // The picker's selection must stay inside its own ForEach or
                // SwiftUI renders no segment as selected.
                if !availableModes.contains(authMode) {
                    authMode = availableModes.first ?? .apiToken
                }
            }
            // The view is torn down the moment isAuthenticated flips, and a
            // probe outliving it would write to @State on a dead view.
            .onDisappear { probeTask?.cancel() }
        }
    }

    /// SSO buttons, plus a divider when they are sharing the screen with a
    /// password form.
    @ViewBuilder
    private var ssoSection: some View {
        if !authOptions.providers.isEmpty {
            VStack(spacing: 12) {
                if !ssoIsPrimary {
                    HStack(spacing: 12) {
                        VStack { Divider() }
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack { Divider() }
                    }
                }

                ForEach(authOptions.providers) { provider in
                    ssoButton(for: provider)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Prominent when SSO is the only way in, quiet when it is sharing the
    /// screen with a password form. Written out twice rather than through a
    /// type-erased style, which SwiftUI has no public equivalent of.
    @ViewBuilder
    private func ssoButton(for provider: OIDCProvider) -> some View {
        let disabled = isConnecting || ServerURL.normalized(serverURL) == nil
        if ssoIsPrimary {
            Button { signInWithSSO(provider) } label: { ssoLabel(provider) }
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
        } else {
            Button { signInWithSSO(provider) } label: { ssoLabel(provider) }
                .buttonStyle(.bordered)
                .disabled(disabled)
        }
    }

    private func ssoLabel(_ provider: OIDCProvider) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.badge.key.fill")
            Text("Continue with \(provider.name)")
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    /// True when there is no password form for SSO to sit politely beneath.
    private var ssoIsPrimary: Bool {
        !authOptions.providers.isEmpty && !authOptions.showsCredentials
    }

    private var availableModes: [AuthMode] {
        var modes: [AuthMode] = []
        if authOptions.showsCredentials {
            modes.append(.credentials)
        }
        if authOptions.showsAPIToken {
            modes.append(.apiToken)
        }
        return modes
    }

    /// Asks the server which auth methods it offers.
    ///
    /// One function with a flag rather than the two near-identical copies PR
    /// #103 grew (noted in the issue). Failure is deliberately silent: it lands
    /// on `AuthOptions.unknownServer`, which shows the same form the screen
    /// showed before any of this existed. Writing a probe failure into
    /// `errorMessage` would flash an error on every keystroke, since cancelling
    /// an in-flight request surfaces as one.
    private func checkServer(debounce: Bool) {
        probeTask?.cancel()

        guard let url = ServerURL.normalized(serverURL) else {
            authOptions = .unknownServer
            return
        }

        probeTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled {
                    return
                }
            }

            let info = try? await ServerInfoService().fetch(from: url)

            // Cancellation is cooperative and the response may already be in
            // flight, so re-check that the user has not moved on to a different
            // server before writing the result back.
            guard !Task.isCancelled, ServerURL.normalized(serverURL) == url else { return }
            authOptions = info.map(AuthOptions.init(info:)) ?? .unknownServer
        }
    }

    /// Runs the full OIDC flow for one provider.
    private func signInWithSSO(_ provider: OIDCProvider) {
        guard let serverURL = ServerURL.normalized(serverURL) else { return }
        isConnecting = true
        errorMessage = nil

        Task {
            defer { isConnecting = false }
            do {
                // Fresh per attempt, and never the same value for both.
                let state = OIDCLogin.generateState()
                let nonce = OIDCLogin.generateNonce()

                let authorizationURL = try OIDCLogin.authorizationURL(
                    for: provider,
                    redirectURI: OIDCLogin.redirectURI,
                    state: state,
                    nonce: nonce
                )

                let callback = try await webAuthenticator.authenticate(
                    url: authorizationURL,
                    callbackScheme: OIDCLogin.callbackScheme,
                    // Same isolation PR #103 wanted from a non-persistent data
                    // store, without giving up the URL bar.
                    prefersEphemeralSession: true
                )

                switch OIDCLogin.parseCallback(
                    callback,
                    expectedState: state,
                    expectedScheme: OIDCLogin.callbackScheme
                ) {
                case let .success(code):
                    try await appState.loginWithOIDC(
                        serverURL: serverURL.absoluteString,
                        provider: provider.key,
                        code: code,
                        redirectURI: OIDCLogin.redirectURI
                    )

                case let .providerError(error, description):
                    errorMessage = description ?? "Your provider refused the sign-in (\(error))."

                case .stateMismatch:
                    errorMessage = "That sign-in response didn't match this request, so it was rejected."

                case .malformed:
                    errorMessage = "Your provider sent a sign-in response we couldn't read."
                }
            } catch WebAuthenticationError.cancelled {
                // The user backed out. Say nothing.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var isFormIncomplete: Bool {
        if serverURL.isEmpty {
            return true
        }
        if authMode == .credentials {
            return username.isEmpty || password.isEmpty
        } else {
            return apiToken.isEmpty
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        guard let normalized = ServerURL.normalized(serverURL) else {
            errorMessage = NetworkError.invalidURL.localizedDescription
            isConnecting = false
            return
        }
        let url = normalized.absoluteString

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
