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

    /// A typed or pasted duration: `12` (minutes), `1:05`, `1:05:30`, `1h 5m`, `4m 32s`, or text
    /// holding one, such as "Worked for 4m 32s". Whole seconds, or nil if there's none.
    static func parseDuration(_ text: String) -> TimeInterval? {
        let text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var total: Double = 0
        let units = text.matches(of: /(\d+(?:\.\d+)?)\s*(hours|hour|hrs|hr|h|minutes|minute|mins|min|m|seconds|second|secs|sec|s)(?![a-z])/)
        if !units.isEmpty {
            for match in units {
                let value = Double(match.1) ?? 0
                switch match.2.first {
                case "h": total += value * 3600
                case "m": total += value * 60
                default: total += value
                }
            }
        } else if let clock = text.firstMatch(of: /(\d+):(\d{1,2})(?::(\d{1,2}))?/) {
            total = (Double(clock.1) ?? 0) * 3600 + (Double(clock.2) ?? 0) * 60 + (clock.3.flatMap { Double($0) } ?? 0)
        } else if text.wholeMatch(of: /\d+(?:\.\d+)?/) != nil, let minutes = Double(text) {
            total = minutes * 60
        }
        let seconds = total.rounded()
        return seconds >= 1 && seconds.isFinite ? seconds : nil
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
