import Foundation

struct TaskItem: Codable, Identifiable, Equatable {
    static let maxNameLength = 30

    let id: UUID
    var name: String            // max 30 chars, default "Task 1/2/3"
    var accumulated: TimeInterval   // seconds banked while paused
}

struct AppState: Codable, Equatable {
    var tasks: [TaskItem]       // at least one
    var activeTaskID: UUID?     // nil = all paused
    var activeSince: Date?      // wall-clock time the active task started
    var history: [String: [UUID: TimeInterval]] // "yyyy-MM-dd" -> seconds per task
    var lastActiveTaskID: UUID? // shown when all are paused; Hubstaff continues it
    var lastSavedAt: Date?      // heartbeat; marks when a run ended if the Mac was shut down
    var archivedTasks: [TaskItem]? // deleted tasks, kept so their history still exports
    var hubstaffWasTracking: Bool? // last Hubstaff state seen; nil until the first reading

    static func initial() -> AppState {
        AppState(
            tasks: (0..<2).map { TaskItem(id: UUID(), name: "Task \($0 + 1)", accumulated: 0) },
            activeTaskID: nil,
            activeSince: nil,
            history: [:]
        )
    }

    /// Repairs a state file that was hand-edited or written by a different version.
    func sanitized() -> AppState {
        var copy = self
        if copy.tasks.isEmpty {
            copy.tasks = AppState.initial().tasks
        }
        for index in copy.tasks.indices {
            copy.tasks[index].name = String(copy.tasks[index].name.prefix(TaskItem.maxNameLength))
            copy.tasks[index].accumulated = max(copy.tasks[index].accumulated, 0)
        }
        if !copy.tasks.contains(where: { $0.id == copy.activeTaskID }) || copy.activeSince == nil {
            copy.activeTaskID = nil
            copy.activeSince = nil
        }
        return copy
    }
}
