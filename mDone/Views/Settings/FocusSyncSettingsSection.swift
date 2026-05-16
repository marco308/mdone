#if os(iOS)
import SwiftData
import SwiftUI

/// Settings section for the focus-service outbox (mdone#62).
/// Configures the URL + token (Keychain) and exposes manual "Sync now" /
/// pending-count visibility. Blank URL means the feature is off.
struct FocusSyncSettingsSection: View {
    @Environment(FocusOutboxService.self) private var outbox

    @State private var serverURL: String = FocusSyncConfig.getServerURL() ?? ""
    @State private var token: String = FocusSyncConfig.getToken() ?? ""
    @State private var revealToken: Bool = false
    @State private var lastSyncMessage: String?

    @Query(filter: #Predicate<FocusRecord> { $0.deliveredAt == nil })
    private var pending: [FocusRecord]

    @Query(filter: #Predicate<FocusRecord> { $0.deliveredAt != nil })
    private var delivered: [FocusRecord]

    var body: some View {
        Section {
            TextField("https://focus.example.com", text: $serverURL)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit(persist)
                .onChange(of: serverURL) { _, _ in persist() }

            HStack {
                if revealToken {
                    TextField("Bearer token", text: $token)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } else {
                    SecureField("Bearer token", text: $token)
                }
                Button {
                    revealToken.toggle()
                } label: {
                    Image(systemName: revealToken ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(revealToken ? "Hide token" : "Show token")
            }
            .onChange(of: token) { _, _ in persist() }

            LabeledContent("Status") {
                statusRow
            }

            LabeledContent("Pending", value: "\(pending.count)")
            LabeledContent("Delivered", value: "\(delivered.count)")

            Button("Sync now") {
                lastSyncMessage = "Syncing…"
                Task {
                    await outbox.drain()
                    lastSyncMessage = "Sync triggered — check pending count"
                }
            }
            .disabled(!FocusSyncConfig.isConfigured() || pending.isEmpty)

            if let lastSyncMessage {
                Text(lastSyncMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Focus History Sync")
        } footer: {
            Text(footerText)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        let configured = FocusSyncConfig.isConfigured()
        HStack(spacing: 6) {
            Circle()
                .fill(configured ? .green : .secondary)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(configured ? "Configured" : "Not configured")
                .font(.subheadline)
        }
    }

    private var footerText: String {
        if !FocusSyncConfig.isConfigured() {
            return "Leave blank to keep focus history on-device only. When both fields are set, completed focus sessions are sent to your focus-service so they can be analysed across tasks (mdone#62)."
        }
        return "Focus sessions sync automatically when you complete a task. The server uses each session's client_id for idempotent retry — re-sending the same session never creates duplicates."
    }

    private func persist() {
        FocusSyncConfig.saveServerURL(serverURL)
        FocusSyncConfig.saveToken(token)
    }
}
#endif
