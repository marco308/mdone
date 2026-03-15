import SwiftUI

struct NotificationListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appState.notifications.isEmpty {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell.slash",
                        description: Text("You're all caught up!")
                    )
                } else {
                    List {
                        ForEach(appState.notifications) { notification in
                            NotificationRow(notification: notification)
                                .swipeActions(edge: .trailing) {
                                    if notification.isUnread {
                                        Button {
                                            Task {
                                                await appState.markNotificationRead(notification.id)
                                            }
                                        } label: {
                                            Label("Read", systemImage: "envelope.open")
                                        }
                                        .tint(.blue)
                                    }
                                }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #endif
                }
            }
            .navigationTitle("Notifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                #endif

                ToolbarItem(placement: .primaryAction) {
                    if appState.unreadNotificationCount > 0 {
                        Button {
                            Task {
                                await appState.markAllNotificationsRead()
                            }
                        } label: {
                            Label("Mark All Read", systemImage: "envelope.open.fill")
                        }
                    }
                }
            }
            .task {
                await appState.fetchNotifications()
            }
        }
    }
}

struct NotificationRow: View {
    let notification: VNotification

    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(notification.isUnread ? Color.blue : Color.clear)
                .frame(width: 8, height: 8)

            // Icon
            Image(systemName: notification.iconName)
                .font(.title3)
                .foregroundStyle(notification.iconColor)
                .frame(width: 28)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.descriptionText)
                    .font(.subheadline)
                    .fontWeight(notification.isUnread ? .semibold : .regular)
                    .foregroundStyle(notification.isUnread ? .primary : .secondary)
                    .lineLimit(2)

                Text(notification.relativeTimeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(notification.isUnread ? 1.0 : 0.7)
    }
}
