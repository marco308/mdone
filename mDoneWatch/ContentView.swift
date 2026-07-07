import SwiftUI

struct ContentView: View {
    @StateObject private var syncManager = WatchConnectivityManager.shared
    
    var body: some View {
        if syncManager.syncedToken != nil || WidgetDataProvider.shared.isAuthenticated {
            WatchHomeView()
        } else {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("mDone Watch")
                    .font(.headline)
                
                Text("Open mDone on iPhone to sync your account")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }
}
