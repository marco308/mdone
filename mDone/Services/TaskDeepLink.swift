import Foundation

/// Public, read-only navigation contract: mdone://task/42?server=<encoded base URL>.
/// A server is an identity to compare, never an address to configure or request.
struct TaskDeepLink: Equatable {
    let taskID: Int64
    let server: URL

    static var scheme: String {
        Bundle.main.object(forInfoDictionaryKey: "MDoneURLScheme") as? String ?? "mdone"
    }

    init(url: URL, scheme: String = TaskDeepLink.scheme) throws {
        guard url.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == scheme.lowercased(), parts.host == "task",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              parts.percentEncodedPath == parts.path,
              parts.path.hasPrefix("/")
        else { throw TaskLinkFailure.invalidLink }
        let id = String(parts.path.dropFirst())
        guard id.first != "0", !id.isEmpty, id.utf8.allSatisfy({ (48 ... 57).contains($0) }),
              let taskID = Int64(id), taskID > 0,
              let query = parts.queryItems, query.count == 1,
              query[0].name == "server", let rawServer = query[0].value,
              let server = Self.serverIdentity(rawServer)
        else { throw TaskLinkFailure.invalidLink }
        self.taskID = taskID
        self.server = server
    }

    func matches(serverURL: String?) -> Bool {
        serverURL.flatMap(Self.serverIdentity) == server
    }

    /// Match scheme, host, effective port and the entire server base path.
    /// Reject ambiguous paths instead of guessing which installation they mean.
    static func serverIdentity(_ value: String) -> URL? {
        guard var parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.path.contains("\\"), !parts.path.contains("//"),
              !parts.percentEncodedPath.lowercased().contains("%2f"),
              !parts.percentEncodedPath.lowercased().contains("%5c"),
              !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              parts.port.map({ (1 ... 65535).contains($0) }) ?? true
        else { return nil }
        parts.scheme = scheme
        parts.host = host.lowercased()
        if parts.port == (scheme == "https" ? 443 : 80) {
            parts.port = nil
        }
        var path = parts.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        parts.path = path
        return parts.url
    }
}

enum TaskLinkFailure: LocalizedError {
    case invalidLink, wrongServer, signIn, unavailable, offline, changedSession

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            String(localized: "This task link is invalid. It must include a server and a positive task ID.")
        case .wrongServer:
            String(localized: "This task belongs to a different Vikunja server. Your connection has not been changed.")
        case .signIn:
            String(localized: "Sign in to the task's Vikunja server to continue opening it.")
        case .unavailable:
            String(localized: "This task was deleted or your account cannot access it.")
        case .offline:
            String(localized: "Could not load this task. Check your connection, then retry.")
        case .changedSession:
            String(localized: "Your connection changed while opening the task. Please open the link again.")
        }
    }
}
