import Foundation
import Observation

enum SystemEvent {
    case sleep, wake, lock, unlock
}

/// All timing logic. Time is always derived from timestamps, never by counting ticks.
@Observable
final class TimerStore {
    static let undoWindow: TimeInterval = 10

    private(set) var state: AppState

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let persist: (AppState) -> Void
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let dayKeys: DateFormatter

    private var undoSnapshot: AppState?
    private var undoExpiry: Date?

    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var isLocked = false
    @ObservationIgnored private var taskToResume: UUID?

    init(state: AppState, calendar: Calendar = .current, persist: @escaping (AppState) -> Void) {
        self.state = state
        self.calendar = calendar
        self.persist = persist
        self.dayKeys = Formatting.dayKeyFormatter(calendar: calendar)
    }

    // MARK: - Reading

    var isAnyRunning: Bool {
        state.activeTaskID != nil
    }

    func isRunning(_ id: UUID) -> Bool {
        state.activeTaskID == id
    }

    /// Rule 1: `accumulated` + (if active) `now − activeSince`.
    func displayedTime(of id: UUID, now: Date = Date()) -> TimeInterval {
        guard let task = task(id) else { return 0 }
        return task.accumulated + liveSeconds(of: id, now: now)
    }

    /// Time counted today for this task: banked today + the live portion since midnight.
    /// Never more than the task's time, so resetting a task resets its today as well, while
    /// history keeps the record for export.
    func todayTime(of id: UUID, now: Date = Date()) -> TimeInterval {
        var today = state.history[dayKey(now)]?[id] ?? 0
        if isRunning(id), let since = state.activeSince {
            today += max(now.timeIntervalSince(max(since, calendar.startOfDay(for: now))), 0)
        }
        return min(today, displayedTime(of: id, now: now))
    }

    func totalTime(now: Date = Date()) -> TimeInterval {
        state.tasks.reduce(0) { $0 + displayedTime(of: $1.id, now: now) }
    }

    func totalToday(now: Date = Date()) -> TimeInterval {
        state.tasks.reduce(0) { $0 + todayTime(of: $1.id, now: now) }
    }

    /// `today 0:08:20`, or nil when it would say nothing new: no time today, or only today's.
    func todayLabel(of id: UUID, now: Date = Date()) -> String? {
        Self.todayLabel(today: todayTime(of: id, now: now), total: displayedTime(of: id, now: now))
    }

    /// The same for the total: nil unless the total includes other days' time.
    func todayLabelForTotal(now: Date = Date()) -> String? {
        Self.todayLabel(today: totalToday(now: now), total: totalTime(now: now))
    }

    private static func todayLabel(today: TimeInterval, total: TimeInterval) -> String? {
        today >= 1 && total - today >= 1 ? "today \(Formatting.clock(today, showSeconds: true))" : nil
    }

    /// The task the menu bar shows: the running one, else the last one that ran.
    var currentTask: TaskItem {
        state.tasks.first { $0.id == state.activeTaskID }
            ?? state.tasks.first { $0.id == state.lastActiveTaskID }
            ?? state.tasks[0]
    }

    func canUndo(now: Date = Date()) -> Bool {
        guard undoSnapshot != nil, let undoExpiry else { return false }
        return now < undoExpiry
    }

    /// History including the unbanked part of the current run, for export.
    func historyIncludingLive(now: Date = Date()) -> [String: [UUID: TimeInterval]] {
        var history = state.history
        if let id = state.activeTaskID, let since = state.activeSince {
            add(taskID: id, from: since, to: now, into: &history)
        }
        return history
    }

    // MARK: - Actions

    /// Starts a task and pauses the others. A task that is already running is left alone.
    func select(_ id: UUID, now: Date = Date()) {
        guard !isRunning(id) else { return }
        toggle(id, now: now)
    }

    func selectTask(at index: Int, now: Date = Date()) {
        guard state.tasks.indices.contains(index) else { return }
        select(state.tasks[index].id, now: now)
    }

    /// Rules 2 and 3, for the global shortcuts: like `select`, but the running task pauses.
    func toggle(_ id: UUID, now: Date = Date()) {
        guard state.tasks.contains(where: { $0.id == id }) else { return }
        takeUndoSnapshot(now: now)
        taskToResume = nil
        let wasRunning = isRunning(id)
        bankActive(now: now)
        if !wasRunning {
            start(id, now: now)
        }
        didChange()
    }

    func toggleTask(at index: Int, now: Date = Date()) {
        guard state.tasks.indices.contains(index) else { return }
        toggle(state.tasks[index].id, now: now)
    }

    /// Rule 4.
    func pauseAll(now: Date = Date()) {
        guard isAnyRunning else { return }
        takeUndoSnapshot(now: now)
        taskToResume = nil
        bankActive(now: now)
        didChange()
    }

    /// Rule 5. Time already worked in the current run still goes to history.
    func setTime(of id: UUID, to seconds: TimeInterval, now: Date = Date()) {
        guard let index = index(of: id) else { return }
        takeUndoSnapshot(now: now)
        if isRunning(id) {
            bankActive(now: now)
            start(id, now: now)
        }
        state.tasks[index].accumulated = max(seconds, 0)
        didChange()
    }

    /// Rule 6: history is deliberately left alone.
    func reset(_ id: UUID, now: Date = Date()) {
        setTime(of: id, to: 0, now: now)
    }

    /// A fresh start: everything goes, including history, leaving one empty "Task 1".
    /// Hubstaff's last state stays, so following it carries on as normal.
    func resetEverything() {
        let task = TaskItem(id: UUID(), name: "Task 1", accumulated: 0)
        state.tasks = [task]
        state.archivedTasks = nil
        state.history = [:]
        state.activeTaskID = nil
        state.activeSince = nil
        state.lastActiveTaskID = task.id
        taskToResume = nil
        clearUndo()
        didChange()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = index(of: id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Task \(index + 1)"
        state.tasks[index].name = trimmed.isEmpty ? fallback : String(trimmed.prefix(TaskItem.maxNameLength))
        didChange()
    }

    func addTask(name: String) {
        let number = state.tasks.count + 1
        let task = TaskItem(id: UUID(), name: "Task \(number)", accumulated: 0)
        state.tasks.append(task)
        rename(task.id, to: name)
    }

    /// The last task can't be deleted. A deleted task's history is kept for export.
    func deleteTask(_ id: UUID, now: Date = Date()) {
        guard state.tasks.count > 1, let index = index(of: id) else { return }
        if isRunning(id) {
            bankActive(now: now)
        }
        state.archivedTasks = (state.archivedTasks ?? []) + [state.tasks.remove(at: index)]
        if state.lastActiveTaskID == id {
            state.lastActiveTaskID = nil
        }
        clearUndo()
        didChange()
    }

    /// Rule 11. Restoring the snapshot's `activeSince` credits the seconds since the action
    /// to the task that was running. Names and colors edited in the meantime are kept.
    func undo(now: Date = Date()) {
        guard canUndo(now: now), let snapshot = undoSnapshot else { return }
        for task in snapshot.tasks {
            if let index = index(of: task.id) {
                state.tasks[index].accumulated = task.accumulated
            }
        }
        state.activeTaskID = snapshot.activeTaskID
        state.activeSince = snapshot.activeSince
        state.lastActiveTaskID = snapshot.lastActiveTaskID
        state.history = snapshot.history
        taskToResume = nil
        clearUndo()
        didChange()
    }

    // MARK: - System events

    /// Rule 10. Resuming waits until the Mac is both awake and unlocked.
    func handle(_ event: SystemEvent, pauseOnSleep: Bool, resumeAfterWake: Bool, now: Date = Date()) {
        switch event {
        case .sleep: isAsleep = true
        case .lock: isLocked = true
        case .wake: isAsleep = false
        case .unlock: isLocked = false
        }

        switch event {
        case .sleep, .lock:
            guard pauseOnSleep, let id = state.activeTaskID else { return }
            taskToResume = id
            bankActive(now: now)
            clearUndo()
            didChange()
        case .wake, .unlock:
            guard !isAsleep, !isLocked, let id = taskToResume else { return }
            taskToResume = nil
            guard resumeAfterWake, !isAnyRunning, state.tasks.contains(where: { $0.id == id }) else { return }
            start(id, now: now)
            didChange()
        }
    }

    /// Follows Hubstaff by reacting only when its state changes, so a task started or paused
    /// by hand stays that way until Hubstaff next starts or stops.
    func hubstaffStateChanged(isTracking: Bool, now: Date = Date()) {
        let previous = state.hubstaffWasTracking
        guard previous != isTracking else { return }
        state.hubstaffWasTracking = isTracking
        defer { didChange() }
        guard previous != nil else { return }

        clearUndo()
        if isTracking {
            guard !isAnyRunning, let id = state.lastActiveTaskID else { return }
            if isAsleep || isLocked {
                taskToResume = id
            } else {
                start(id, now: now)
            }
        } else {
            taskToResume = nil
            bankActive(now: now)
        }
    }

    func forgetHubstaffState() {
        guard state.hubstaffWasTracking != nil else { return }
        state.hubstaffWasTracking = nil
        persist(state)
    }

    /// Rule 9. A task stays running across a relaunch, but sleep or a shutdown that happened
    /// while the app was closed must not count. The kernel only reports the most recent sleep.
    func reconcileAfterLaunch(
        lastSleep: Date?,
        lastBoot: Date?,
        pauseOnSleep: Bool,
        resumeAfterWake: Bool,
        now: Date = Date()
    ) {
        guard pauseOnSleep, let id = state.activeTaskID, let since = state.activeSince else { return }
        var end: Date?
        if let lastBoot, lastBoot > since {
            end = state.lastSavedAt ?? since
        }
        if let lastSleep, lastSleep > since {
            end = min(end ?? lastSleep, lastSleep)
        }
        guard let end else { return }
        bankActive(now: min(max(end, since), now))
        if resumeAfterWake {
            start(id, now: now)
        }
        didChange()
    }

    /// Saves every 30 seconds while running so a crash or power loss costs little.
    func heartbeat(now: Date = Date()) {
        guard isAnyRunning else { return }
        state.lastSavedAt = now
        persist(state)
    }

    func saveNow(now: Date = Date()) {
        state.lastSavedAt = now
        persist(state)
    }

    // MARK: - Internals

    private func task(_ id: UUID) -> TaskItem? {
        state.tasks.first { $0.id == id }
    }

    private func index(of id: UUID) -> Int? {
        state.tasks.firstIndex { $0.id == id }
    }

    private func liveSeconds(of id: UUID, now: Date) -> TimeInterval {
        guard isRunning(id), let since = state.activeSince else { return 0 }
        return max(now.timeIntervalSince(since), 0)
    }

    private func start(_ id: UUID, now: Date) {
        state.activeTaskID = id
        state.activeSince = now
        state.lastActiveTaskID = id
    }

    private func bankActive(now: Date) {
        guard let id = state.activeTaskID, let since = state.activeSince, let index = index(of: id) else {
            state.activeTaskID = nil
            state.activeSince = nil
            return
        }
        state.tasks[index].accumulated += max(now.timeIntervalSince(since), 0)
        add(taskID: id, from: since, to: now, into: &state.history)
        state.activeTaskID = nil
        state.activeSince = nil
    }

    /// Rule 7: a run that crosses midnight is split between the days it touches.
    private func add(taskID: UUID, from start: Date, to end: Date, into history: inout [String: [UUID: TimeInterval]]) {
        var cursor = start
        while cursor < end {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) ?? end
            let segmentEnd = min(midnight, end)
            history[dayKey(cursor), default: [:]][taskID, default: 0] += segmentEnd.timeIntervalSince(cursor)
            cursor = segmentEnd
        }
    }

    private func dayKey(_ date: Date) -> String {
        dayKeys.string(from: date)
    }

    private func takeUndoSnapshot(now: Date) {
        undoSnapshot = state
        undoExpiry = now.addingTimeInterval(Self.undoWindow)
    }

    private func clearUndo() {
        undoSnapshot = nil
        undoExpiry = nil
    }

    private func didChange() {
        state.lastSavedAt = Date()
        persist(state)
        onChange?()
    }
}
