import Foundation

enum CSVExport {
    /// `date,task,seconds,hh:mm:ss`, one row per day per task with time > 0, newest day first.
    /// Starts with a byte order mark so Excel reads non-ASCII task names correctly.
    static func csv(history: [String: [UUID: TimeInterval]], tasks: [TaskItem]) -> String {
        var lines = ["date,task,seconds,hh:mm:ss"]
        for date in history.keys.sorted().reversed() {
            for task in tasks {
                let seconds = Int(history[date]?[task.id] ?? 0)
                guard seconds > 0 else { continue }
                lines.append("\(date),\(escape(task.name)),\(seconds),\(Formatting.csvDuration(seconds))")
            }
        }
        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
