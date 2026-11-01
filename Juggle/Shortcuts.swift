import KeyboardShortcuts

// All shortcuts start blank; people who want them set them in the app window.
extension KeyboardShortcuts.Name {
    static let pauseAllTasks = Self("pauseAllTasks")
    static let toggleTaskList = Self("toggleTaskList")
    static let undoLastAction = Self("undoAction")

    /// Tied to the position in the task list, so a shortcut outlives the task using it:
    /// the next task to take that position inherits it.
    static func taskPosition(_ index: Int) -> Self {
        Self("taskPosition-\(index)")
    }
}
