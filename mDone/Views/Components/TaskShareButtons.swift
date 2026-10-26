import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Share and Copy Link for a task's web link (`TaskLink`), for handing a task
/// to an agent or a person. Shows nothing when there is no server URL to build
/// the link from, which only happens signed out.
struct TaskShareButtons: View {
    let task: VTask

    var body: some View {
        if let url = TaskLink.url(for: task) {
            ShareLink(item: url, subject: Text(task.title)) {
                Label("Share Link", systemImage: "square.and.arrow.up")
            }

            Button {
                Self.copy(url)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
    }

    static func copy(_ url: URL) {
        #if os(iOS)
        UIPasteboard.general.url = url
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
    }
}

/// A single toolbar button that opens `TaskShareButtons` as a menu, for the
/// detail views where there is room for one icon rather than two.
struct TaskShareMenu: View {
    let task: VTask

    var body: some View {
        if TaskLink.url(for: task) != nil {
            Menu {
                TaskShareButtons(task: task)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share task link")
        }
    }
}
