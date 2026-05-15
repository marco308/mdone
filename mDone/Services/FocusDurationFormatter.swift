import Foundation

/// Abbreviated formatting for focus durations on the task detail screen.
///
/// - `< 60s` → seconds (e.g. `45s`)
/// - `60s … <1h` → minutes (e.g. `12m`)
/// - `>= 1h` → hours + minutes (e.g. `1h 30m`)
///
/// Capped at two units so long sessions stay readable.
enum FocusDurationFormatter {
    static func string(from seconds: TimeInterval) -> String {
        let safe = max(0, seconds)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = if safe < 60 {
            [.second]
        } else if safe >= 3600 {
            [.hour, .minute]
        } else {
            [.minute]
        }
        return formatter.string(from: safe) ?? "\(Int(safe))s"
    }
}
