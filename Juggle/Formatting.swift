import Foundation

enum Formatting {
    /// `H:MM`, or `H:MM:SS` with `showSeconds`. Hours are unbounded, e.g. `123:04`.
    static func clock(_ seconds: TimeInterval, showSeconds: Bool) -> String {
        let total = Int(max(seconds, 0))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        if showSeconds {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", hours, minutes)
    }

    /// `hh:mm:ss` for the CSV column.
    static func csvDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }

    static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
