import SwiftUI

struct SettingsScreen: View {
    @Environment(AppState.self) private var appState
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("reminderOffset") private var reminderOffset = 30
    @State private var showLogoutConfirm = false

    private var serverURL: String {
        AuthService.shared.getServerURL() ?? "Not configured"
    }

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("URL", value: serverURL)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isAuthenticated ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.isAuthenticated ? "Connected" : "Disconnected")
                            .font(.subheadline)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Enable Reminders", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            Task {
                                let granted = await NotificationService.shared.requestPermission()
                                if !granted {
                                    notificationsEnabled = false
                                }
                            }
                        }
                    }

                if notificationsEnabled {
                    Picker("Remind before", selection: $reminderOffset) {
                        ForEach(NotificationService.ReminderOffset.allCases, id: \.rawValue) { offset in
                            Text(offset.label).tag(offset.rawValue)
                        }
                    }
                }
            }

            Section("Data") {
                LabeledContent("Tasks", value: "\(appState.tasks.count)")
                LabeledContent("Projects", value: "\(appState.projects.count)")

                Button("Refresh All Data") {
                    Task { await appState.refreshAll() }
                }
            }

            Section {
                Button("Disconnect", role: .destructive) {
                    showLogoutConfirm = true
                }
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("mDone")
                            .font(.caption.bold())
                        Text("Version 1.0.0")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Settings")
        .alert("Disconnect?", isPresented: $showLogoutConfirm) {
            Button("Disconnect", role: .destructive) {
                Task { await appState.logout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove your server configuration. You'll need to reconnect.")
        }
    }
}
