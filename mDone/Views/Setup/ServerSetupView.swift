import SwiftUI

struct OIDCLoginSession: Identifiable {
    let id = UUID()
    let authURL: URL
    let redirectURI: String
    let providerKey: String
}

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
    @State private var oidcProviders: [InfoResponse.Auth.OpenID.Provider] = []
    @State private var isLocalAuthEnabled = true
    @State private var oidcSession: OIDCLoginSession? = nil
    @State private var oidcRedirectURI = ""
    @State private var selectedProviderKey = ""
    @State private var checkTask: Task<Void, Never>? = nil
    @State private var isCheckingServer = false
    @FocusState private var isServerURLFocused: Bool


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

                    // Form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                             ZStack(alignment: .trailing) {
                                 TextField("https://vikunja.example.com", text: $serverURL)
                                     .textFieldStyle(.roundedBorder)
                                     .focused($isServerURLFocused)
                                     .onSubmit {
                                         checkServerImmediately(serverURL)
                                     }
                                 #if os(iOS)
                                     .textContentType(.URL)
                                 #endif
                                     .autocorrectionDisabled()
                                 #if os(iOS)
                                     .textInputAutocapitalization(.never)
                                     .keyboardType(.URL)
                                 #endif

                                 if isCheckingServer {
                                     ProgressView()
                                         .controlSize(.small)
                                         .padding(.trailing, 8)
                                 }
                             }

                        }

                        Picker("Auth Method", selection: $authMode) {
                            ForEach(AuthMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if authMode == .credentials {
                            if isLocalAuthEnabled {
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

                    if authMode != .credentials || isLocalAuthEnabled {
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
                    }

                    if authMode == .credentials {
                        if isLocalAuthEnabled {
                            Text("Login with your Vikunja username and password for full functionality")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    } else {
                        Text(
                            "API tokens have limited permissions. Use Login for full functionality including task reordering."
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    }

                    if !oidcProviders.isEmpty {
                        VStack(spacing: 12) {
                            if isLocalAuthEnabled || authMode == .apiToken {
                                HStack {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.3))
                                        .frame(height: 1)
                                    Text("or sign in with")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.3))
                                        .frame(height: 1)
                                }
                                .padding(.vertical, 8)
                            }

                            ForEach(oidcProviders) { provider in
                                Button {
                                    startOIDCLogin(provider: provider)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "lock.circle.fill")
                                            .font(.title3)
                                        Text("Sign in with \(provider.name)")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(.accentColor)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer()

                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                if !serverURL.isEmpty {
                    checkServerImmediately(serverURL)
                }
            }
            .onChange(of: serverURL) { _, newValue in
                checkServerDebounced(newValue)
            }
            .onChange(of: isServerURLFocused) { _, isFocused in
                if !isFocused && !serverURL.isEmpty {
                    checkServerImmediately(serverURL)
                }
            }

            .sheet(item: $oidcSession) { session in
                NavigationStack {
                    OIDCWebView(
                        url: session.authURL,
                        redirectURI: session.redirectURI,
                        onCallback: { code in
                            oidcSession = nil
                            handleOIDCCallback(code: code)
                        },
                        onCancel: {
                            oidcSession = nil
                        }
                    )
                    #if os(iOS)
                    .navigationTitle("Sign In")
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                oidcSession = nil
                            }
                        }
                    }
                }
            }
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
        if !url.hasPrefix("http://"), !url.hasPrefix("https://") {
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

    private func isValidServerURL(_ urlString: String) -> Bool {
        #if DEBUG
        print("[mDone] isValidServerURL checking: '\(urlString)'")
        #endif
        var clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.hasPrefix("http://") && !clean.hasPrefix("https://") {
            clean = "https://" + clean
        }
        guard let url = URL(string: clean),
              let host = url.host,
              !host.isEmpty else {
            #if DEBUG
            print("[mDone] isValidServerURL: URL or host is empty/nil")
            #endif
            return false
        }
        
        // Allow localhost or loopback IP
        if host == "localhost" || host == "127.0.0.1" {
            #if DEBUG
            print("[mDone] isValidServerURL: Valid localhost/loopback!")
            #endif
            return true
        }
        
        let parts = host.split(separator: ".")
        
        // Allow IPv4 addresses (e.g. 192.168.1.100)
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) {
            #if DEBUG
            print("[mDone] isValidServerURL: Valid IPv4 address!")
            #endif
            return true
        }
        
        guard parts.count >= 2,
              let lastPart = parts.last,
              lastPart.count >= 2 else {
            #if DEBUG
            print("[mDone] isValidServerURL: Host parts count < 2 or lastPart < 2. Parts: \(parts)")
            #endif
            return false
        }
        
        #if DEBUG
        print("[mDone] isValidServerURL: Valid URL!")
        #endif
        return true
    }

    private func checkServerDebounced(_ url: String) {
        #if DEBUG
        print("[mDone] checkServerDebounced called for: '\(url)'")
        #endif
        checkTask?.cancel()
        guard isValidServerURL(url) else {
            #if DEBUG
            print("[mDone] checkServerDebounced: Invalid URL format, clearing providers")
            #endif
            self.oidcProviders = []
            self.isLocalAuthEnabled = true
            return
        }

        checkTask = Task {
            #if DEBUG
            print("[mDone] checkServerDebounced task started, sleeping for 2s")
            #endif
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                #if DEBUG
                print("[mDone] checkServerDebounced task cancelled during sleep")
                #endif
                return
            }

            isCheckingServer = true
            defer { isCheckingServer = false }

            #if DEBUG
            print("[mDone] checkServerDebounced sending request to info endpoint")
            #endif
            do {
                let info = try await APIClient.shared.fetchServerInfo(from: url)
                guard !Task.isCancelled else { return }
                
                if let local = info.auth?.local {
                    self.isLocalAuthEnabled = local.enabled
                } else {
                    self.isLocalAuthEnabled = true
                }
                
                if let openid = info.auth?.openidConnect, openid.enabled {
                    self.oidcProviders = openid.providers ?? []
                    #if DEBUG
                    print("[mDone] checkServerDebounced success! Enabled: \(openid.enabled), Providers: \(self.oidcProviders), Local Auth: \(self.isLocalAuthEnabled)")
                    #endif
                } else {
                    self.oidcProviders = []
                    #if DEBUG
                    print("[mDone] checkServerDebounced success but OIDC is disabled, Local Auth: \(self.isLocalAuthEnabled)")
                    #endif
                }
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("[mDone] Error checking server for OIDC/Local: \(error)")
                #endif
                self.oidcProviders = []
                self.isLocalAuthEnabled = true
            }
        }
    }

    private func checkServerImmediately(_ url: String) {
        #if DEBUG
        print("[mDone] checkServerImmediately called for: '\(url)'")
        #endif
        checkTask?.cancel()
        guard isValidServerURL(url) else {
            #if DEBUG
            print("[mDone] checkServerImmediately: Invalid URL format, clearing providers")
            #endif
            self.oidcProviders = []
            self.isLocalAuthEnabled = true
            return
        }

        checkTask = Task {
            isCheckingServer = true
            defer { isCheckingServer = false }

            #if DEBUG
            print("[mDone] checkServerImmediately sending request to info endpoint")
            #endif
            do {
                let info = try await APIClient.shared.fetchServerInfo(from: url)
                guard !Task.isCancelled else { return }
                
                if let local = info.auth?.local {
                    self.isLocalAuthEnabled = local.enabled
                } else {
                    self.isLocalAuthEnabled = true
                }
                
                if let openid = info.auth?.openidConnect, openid.enabled {
                    self.oidcProviders = openid.providers ?? []
                    #if DEBUG
                    print("[mDone] checkServerImmediately success! Enabled: \(openid.enabled), Providers: \(self.oidcProviders), Local Auth: \(self.isLocalAuthEnabled)")
                    #endif
                } else {
                    self.oidcProviders = []
                    #if DEBUG
                    print("[mDone] checkServerImmediately success but OIDC is disabled, Local Auth: \(self.isLocalAuthEnabled)")
                    #endif
                }
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("[mDone] Error checking server for OIDC/Local: \(error)")
                #endif
                self.oidcProviders = []
                self.isLocalAuthEnabled = true
            }
        }
    }




    private func startOIDCLogin(provider: InfoResponse.Auth.OpenID.Provider) {
        var cleanURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.hasPrefix("http://"), !cleanURL.hasPrefix("https://") {
            cleanURL = "https://" + cleanURL
        }
        cleanURL = cleanURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let redirectURI = "\(cleanURL)/auth/openid/\(provider.key)"
        self.oidcRedirectURI = redirectURI
        self.selectedProviderKey = provider.key

        var components = URLComponents(string: provider.authUrl)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: provider.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: provider.scope ?? "openid profile email"),
            URLQueryItem(name: "state", value: UUID().uuidString.lowercased())
        ]

        if let finalURL = components?.url {
            self.oidcSession = OIDCLoginSession(
                authURL: finalURL,
                redirectURI: redirectURI,
                providerKey: provider.key
            )
        }
    }

    private func handleOIDCCallback(code: String) {
        isConnecting = true
        errorMessage = nil

        var cleanURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanURL.hasPrefix("http://"), !cleanURL.hasPrefix("https://") {
            cleanURL = "https://" + cleanURL
        }
        cleanURL = cleanURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        Task {
            do {
                try await appState.loginWithOIDC(
                    serverURL: cleanURL,
                    providerKey: selectedProviderKey,
                    code: code,
                    redirectURL: oidcRedirectURI
                )
            } catch {
                #if DEBUG
                print("[mDone] OIDC Login error: \(error)")
                #endif
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

