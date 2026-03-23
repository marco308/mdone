import SwiftUI

struct CalendarEventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 12) {
            // Calendar color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendarColor ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)))
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if event.isAllDay {
                        Text("All Day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "\(event.startDate, format: .dateTime.hour().minute()) - \(event.endDate, format: .dateTime.hour().minute())"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(event.calendarName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 8))
                        Text(location)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
