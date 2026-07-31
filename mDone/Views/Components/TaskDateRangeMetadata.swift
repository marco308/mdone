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
                let starts = localizedString("starts", locale: locale)
                let ends = localizedString("ends", locale: locale)
                accessibilityText = "\(starts) \(accessibilityFormatter.string(from: start)), \(ends) \(accessibilityFormatter.string(from: end))"
            } else {
                let dateRange = localizedString("date range", locale: locale)
                let to = localizedString("to", locale: locale)
                accessibilityText = "\(dateRange) \(accessibilityFormatter.string(from: lowerBound)) \(to) \(accessibilityFormatter.string(from: upperBound))"
            }
            return TaskDateRangeMetadata(
                compactText: compactText,
                accessibilityText: accessibilityText
            )

        case let (start?, nil):
            let starts = localizedString("Starts", locale: locale)
            let accessibilityStarts = localizedString("starts", locale: locale)
            return TaskDateRangeMetadata(
                compactText: "\(starts) \(dateFormatter.string(from: start))",
                accessibilityText: "\(accessibilityStarts) \(accessibilityFormatter.string(from: start))"
            )

        case let (nil, end?):
            let ends = localizedString("Ends", locale: locale)
            let accessibilityEnds = localizedString("ends", locale: locale)
            return TaskDateRangeMetadata(
                compactText: "\(ends) \(dateFormatter.string(from: end))",
                accessibilityText: "\(accessibilityEnds) \(accessibilityFormatter.string(from: end))"
            )

        case (nil, nil):
            return nil
        }
    }

    private static func localizedString(_ key: String, locale: Locale) -> String {
        let appBundle = Bundle(for: TaskDateRangeMetadataBundleToken.self)
        let localizationIdentifiers = [
            locale.identifier,
            locale.language.languageCode?.identifier
        ].compactMap { $0 }

        for identifier in localizationIdentifiers {
            guard let path = appBundle.path(forResource: identifier, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path) else { continue }
            return localizedBundle.localizedString(
                forKey: key,
                value: key,
                table: "Localizable"
            )
        }

        return appBundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}
