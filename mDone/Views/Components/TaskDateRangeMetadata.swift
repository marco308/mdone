import Foundation

private final class TaskDateRangeMetadataBundleToken {}

struct TaskDateRangeMetadata: Equatable {
    let compactText: String
    let accessibilityText: String

    static func make(
        startDate: Date?,
        endDate: Date?,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> TaskDateRangeMetadata? {
        guard startDate != nil || endDate != nil else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = locale
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.calendar = calendar
        accessibilityFormatter.locale = locale
        accessibilityFormatter.timeZone = calendar.timeZone
        accessibilityFormatter.dateStyle = .medium
        accessibilityFormatter.timeStyle = .short

        switch (startDate, endDate) {
        case let (start?, end?):
            let lowerBound = min(start, end)
            let upperBound = max(start, end)
            let intervalFormatter = DateIntervalFormatter()
            intervalFormatter.calendar = calendar
            intervalFormatter.locale = locale
            intervalFormatter.timeZone = calendar.timeZone
            intervalFormatter.dateStyle = .medium
            intervalFormatter.timeStyle = .none

            let compactText = intervalFormatter.string(from: lowerBound, to: upperBound)
            let accessibilityText: String
            if start <= end {
                let starts = String(localized: "starts", bundle: localizationBundle, locale: locale)
                let ends = String(localized: "ends", bundle: localizationBundle, locale: locale)
                accessibilityText = "\(starts) \(accessibilityFormatter.string(from: start)), \(ends) \(accessibilityFormatter.string(from: end))"
            } else {
                let dateRange = String(localized: "date range", bundle: localizationBundle, locale: locale)
                let to = String(localized: "to", bundle: localizationBundle, locale: locale)
                accessibilityText = "\(dateRange) \(accessibilityFormatter.string(from: lowerBound)) \(to) \(accessibilityFormatter.string(from: upperBound))"
            }
            return TaskDateRangeMetadata(
                compactText: compactText,
                accessibilityText: accessibilityText
            )

        case let (start?, nil):
            let starts = String(localized: "Starts", bundle: localizationBundle, locale: locale)
            let accessibilityStarts = String(localized: "starts", bundle: localizationBundle, locale: locale)
            return TaskDateRangeMetadata(
                compactText: "\(starts) \(dateFormatter.string(from: start))",
                accessibilityText: "\(accessibilityStarts) \(accessibilityFormatter.string(from: start))"
            )

        case let (nil, end?):
            let ends = String(localized: "Ends", bundle: localizationBundle, locale: locale)
            let accessibilityEnds = String(localized: "ends", bundle: localizationBundle, locale: locale)
            return TaskDateRangeMetadata(
                compactText: "\(ends) \(dateFormatter.string(from: end))",
                accessibilityText: "\(accessibilityEnds) \(accessibilityFormatter.string(from: end))"
            )

        case (nil, nil):
            return nil
        }
    }

    private static let localizationBundle = Bundle(for: TaskDateRangeMetadataBundleToken.self)
}
