import Foundation

/// A Vikunja release number, parsed from the `version` string of `/info`.
///
/// Only the numeric core matters here. Vikunja reports `v2.4.0` for a release
/// and something like `v2.4.0-312-abcdef12` for an unstable build, and both
/// count as 2.4.0. A string with no leading number (`unstable`, `dev`) does not
/// parse, and callers treat that as "we do not know" rather than as old.
struct VikunjaVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    /// The first release with the v2 API, the oldest server mDone works with
    /// (#291).
    static let firstWithAPIv2 = VikunjaVersion(major: 2, minor: 4, patch: 0)

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(_ string: String) {
        var core = Substring(string.trimmingCharacters(in: .whitespaces))
        if core.first == "v" || core.first == "V" {
            core = core.dropFirst()
        }
        let numbers = core
            .prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) }
        // Major and minor are required. A bare "2" says too little to act on.
        guard numbers.count >= 2, let major = numbers[0], let minor = numbers[1] else { return nil }
        self.major = major
        self.minor = minor
        patch = numbers.count > 2 ? numbers[2] ?? 0 : 0
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: VikunjaVersion, rhs: VikunjaVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The wording of the "your server is too old" message, shared by the sign-in
/// error, the alert for someone already signed in, and the row in Settings.
enum ServerUpdateNotice {
    /// `version` is nil when the server did not report one.
    static func message(for version: VikunjaVersion?) -> String {
        let required = VikunjaVersion.firstWithAPIv2.description
        guard let version else {
            return String(
                localized: "mDone needs Vikunja \(required) or newer, and this server looks older. Update your server to use mDone with it."
            )
        }
        // swiftformat:disable:next wrap
        return String(
            localized: "mDone needs Vikunja \(required) or newer, and your server runs Vikunja \(version.description). Update your server to use mDone with it."
        )
    }
}
