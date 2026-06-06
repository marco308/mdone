import SwiftUI

/// Lightweight About screen reachable from Settings on both iOS and macOS.
/// Presented as a sheet so it behaves identically inside the iOS navigation
/// stack and the macOS NavigationSplitView content column.
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    private static let repoURL = URL(string: "https://github.com/marco308/mdone")!
    private static let issuesURL = URL(string: "https://github.com/marco308/mdone/issues/new/choose")!
    private static let sponsorURL = URL(string: "https://github.com/sponsors/marco308")!
    private static let coffeeURL = URL(string: "https://buymeacoffee.com/marcuslab")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("mDone")
                            .font(.title2.bold())
                        Text(Self.versionString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("A native task manager for Vikunja.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Feedback") {
                    Link(destination: Self.issuesURL) {
                        Label("Report a Bug or Request a Feature", systemImage: "ladybug")
                    }
                    Link(destination: Self.repoURL) {
                        Label("View Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Section {
                    Link(destination: Self.sponsorURL) {
                        Label("Sponsor on GitHub", systemImage: "heart")
                    }
                    Link(destination: Self.coffeeURL) {
                        Label("Buy Me a Coffee", systemImage: "cup.and.saucer")
                    }
                } header: {
                    Text("Support mDone")
                } footer: {
                    Text("mDone is built and maintained by one person. If it's useful to you, a tip or sponsorship helps keep it going.")
                }
            }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }
}

#Preview {
    AboutScreen()
}
