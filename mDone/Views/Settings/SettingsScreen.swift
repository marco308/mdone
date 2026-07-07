import SwiftUI
import WidgetKit

struct SettingsScreen: View {
    @Environment(AppState.self) private var appState
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("reminderOffset") private var reminderOffset = 30
    @AppStorage(WeekStartPreference.storageKey) private var firstWeekday = WeekStartPreference.system.rawValue
    @AppStorage(DefaultDueTimePreference.storageKey) private var defaultDueTime = DefaultDueTimePreference
        .defaultRawValue
    @AppStorage("calmMode") private var calmMode = false
    @AppStorage("currentStallDays") private var currentStallDays = 7
    @State private var showLogoutConfirm = false
    @State private var showAbout = false

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
                            .accessibilityHidden(true)
                        Text(appState.isAuthenticated ? "Connected" : "Disconnected")
                            .font(.subheadline)
                    }
                }
            }

            Section("Appearance") {
                Picker("Start week on", selection: $firstWeekday) {
                    ForEach(WeekStartPreference.allCases) { preference in
                        Text(preference.label).tag(preference.rawValue)
                    }
                }
            }

            Section {
                Picker("Default due time", selection: $defaultDueTime) {
                    ForEach(DefaultDueTimePreference.allCases) { preference in
                        Text(preference.label).tag(preference.rawValue)
                    }
                }
            } header: {
                Text("Tasks")
            } footer: {
                Text(
                    "Time of day applied to tasks you add to Today without picking a time. Pick a time later in the day to avoid the task showing as overdue right away."
                )
            }

            Section {
                Toggle("Calm Mode", isOn: $calmMode)
                    .onChange(of: calmMode) { _, newValue in
                        SharedKeys.sharedDefaults.set(newValue, forKey: SharedKeys.calmModeKey)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
            } footer: {
                Text(
                    "Overdue tasks appear like any other — no red, no separate Overdue list or counts. They still show in your lists and widgets."
                )
            }

            Section {
                Stepper(
                    "Idle badge after \(currentStallDays) day\(currentStallDays == 1 ? "" : "s")",
                    value: $currentStallDays,
                    in: 1 ... 60
                )
            } header: {
                Text("Current Tasks")
            } footer: {
                Text(
                    "Tasks you mark as Current sit at the top of your list with a progress bar. An idle badge appears when one hasn't been touched for this many days."
                )
            }

            Section("Calendar") {
                NavigationLink {
                    CalendarSelectionView()
                } label: {
                    Label("Calendars in mDone", systemImage: "calendar")
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
                
                #if os(iOS)
                Button("Sync with Apple Watch") {
                    if let url = AuthService.shared.getServerURL(),
                       let token = AuthService.shared.getToken() {
                        WatchConnectivityManager.shared.syncCredentials(serverURL: url, token: token)
                    }
                }
                #endif
            }

            #if os(iOS)
            FocusSyncSettingsSection()
            #endif

            Section {
                Button {
                    showAbout = true
                } label: {
                    Label("About mDone", systemImage: "info.circle")
                }
            }

            Section {
                Button("Disconnect", role: .destructive) {
                    showLogoutConfirm = true
                }
            }

            Section {
                Button {
                    showAbout = true
                } label: {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("mDone")
                                .font(.caption.bold())
                            Text(Self.versionString)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.clear)
        }
        .sheet(isPresented: $showAbout) {
            AboutScreen()
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

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }
}
