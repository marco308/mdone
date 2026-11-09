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

    /// The first release with the v2 API, which a future mDone will need (#289).
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

/// The wording of the "your server is getting old" notice, shared by the
/// one-time alert and the row in Settings.
enum ServerUpdateNotice {
    static func message(for version: VikunjaVersion) -> String {
        let required = VikunjaVersion.firstWithAPIv2.description
        // swiftformat:disable:next wrap
        return String(
            localized: "Your server runs Vikunja \(version.description). A future version of mDone will need Vikunja \(required) or newer. mDone keeps working for now, but please update your server before then."
        )
    }
}
