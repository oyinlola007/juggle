import XCTest
@testable import Juggle

final class TimerStoreTests: XCTestCase {
    private var calendar: Calendar!
    private var saves: [AppState] = []
    private var store: TimerStore!

    private var a: UUID { store.state.tasks[0].id }
    private var b: UUID { store.state.tasks[1].id }
    private var c: UUID { store.state.tasks[2].id }

    /// 2026-03-10 12:00:00 UTC
    private let noon = Date(timeIntervalSince1970: 1_773_144_000)

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        saves = []
        var state = AppState.initial()
        state.tasks.append(TaskItem(id: UUID(), name: "Task 3", accumulated: 0))
        store = TimerStore(state: state, calendar: calendar) { [unowned self] in self.saves.append($0) }
    }

    private func at(_ seconds: TimeInterval) -> Date {
        noon.addingTimeInterval(seconds)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Switching

    func testOnlyOneTaskRunsAndSwitchBanksThePrevious() {
        store.toggle(a, now: at(0))
        store.toggle(b, now: at(60))

        XCTAssertFalse(store.isRunning(a))
        XCTAssertTrue(store.isRunning(b))
        XCTAssertEqual(store.state.tasks[0].accumulated, 60)
        XCTAssertEqual(store.displayedTime(of: a, now: at(500)), 60)
        XCTAssertEqual(store.displayedTime(of: b, now: at(90)), 30)
    }

    func testClickingTheRunningTaskPausesEverything() {
        store.toggle(a, now: at(0))
        store.toggle(a, now: at(30))

        XCTAssertNil(store.state.activeTaskID)
        XCTAssertNil(store.state.activeSince)
        XCTAssertEqual(store.state.tasks[0].accumulated, 30)
    }

    func testPauseAllBanksTheActiveTask() {
        store.toggle(b, now: at(0))
        store.pauseAll(now: at(45))

        XCTAssertFalse(store.isAnyRunning)
        XCTAssertEqual(store.state.tasks[1].accumulated, 45)
    }

    func testEveryStateChangeIsSaved() {
        store.toggle(a, now: at(0))
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.last?.activeTaskID, a)
        store.pauseAll(now: at(1))
        XCTAssertEqual(saves.count, 2)
    }

    // MARK: - Set time and reset

    func testStartingContinuesFromAnEditedTime() {
        store.setTime(of: c, to: 2 * 3600 + 15 * 60, now: at(0))
        store.toggle(c, now: at(0))
        XCTAssertEqual(store.displayedTime(of: c, now: at(10)), 8110)
    }

    func testEditingARunningTaskKeepsItRunningFromTheNewValue() {
        store.toggle(a, now: at(0))
        store.setTime(of: a, to: 3600, now: at(100))

        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.displayedTime(of: a, now: at(100)), 3600)
        XCTAssertEqual(store.displayedTime(of: a, now: at(130)), 3630)
    }

    func testEditingARunningTaskKeepsWorkedTimeInHistory() {
        store.toggle(a, now: at(0))
        store.setTime(of: a, to: 3600, now: at(100))
        XCTAssertEqual(store.todayTime(of: a, now: at(100)), 100)
    }

    func testResetDoesNotEraseHistory() {
        store.toggle(a, now: at(0))
        store.pauseAll(now: at(120))
        store.reset(a, now: at(130))

        XCTAssertEqual(store.displayedTime(of: a, now: at(130)), 0)
        XCTAssertEqual(store.todayTime(of: a, now: at(130)), 0)
        XCTAssertEqual(store.state.history["2026-03-10"]?[a], 120)
    }

    func testRenamesAreTruncatedAndBlankNamesFallBack() {
        store.rename(a, to: String(repeating: "x", count: 50))
        XCTAssertEqual(store.state.tasks[0].name.count, 30)
        store.rename(b, to: "   ")
        XCTAssertEqual(store.state.tasks[1].name, "Task 2")
    }

    // MARK: - Selecting

    func testSelectingStartsATaskAndPausesTheOthers() {
        store.select(a, now: at(0))
        store.select(b, now: at(60))
        XCTAssertTrue(store.isRunning(b))
        XCTAssertEqual(store.displayedTime(of: a, now: at(90)), 60)
    }

    func testSelectingTheRunningTaskDoesNothing() {
        store.select(a, now: at(0))
        let saved = saves.count
        store.select(a, now: at(60))

        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.state.activeSince, at(0))
        XCTAssertEqual(saves.count, saved)
    }

    // MARK: - Adding and deleting

    func testAddingManyTasksAndAllCanRun() {
        for number in 1...20 {
            store.addTask(name: "Extra \(number)")
        }
        XCTAssertEqual(store.state.tasks.count, 23)
        XCTAssertEqual(store.state.tasks[22].name, "Extra 20")
        store.selectTask(at: 22, now: at(0))
        XCTAssertTrue(store.isRunning(store.state.tasks[22].id))
    }

    func testBlankNewTaskGetsADefaultName() {
        store.addTask(name: "  ")
        XCTAssertEqual(store.state.tasks.last?.name, "Task 4")
    }

    func testDeletingTheRunningTaskBanksItAndKeepsItsHistory() {
        store.select(c, now: at(0))
        let id = c
        store.deleteTask(id, now: at(60))

        XCTAssertFalse(store.isAnyRunning)
        XCTAssertEqual(store.state.tasks.count, 2)
        XCTAssertEqual(store.state.archivedTasks?.first?.id, id)
        XCTAssertEqual(store.totalTime(now: at(60)), 0)
        XCTAssertTrue(CSVExport.csv(history: store.historyIncludingLive(now: at(60)), tasks: store.state.tasks + (store.state.archivedTasks ?? [])).contains("Task 3,60,"))
    }

    func testTheLastTaskCannotBeDeleted() {
        store.deleteTask(c)
        store.deleteTask(b)
        store.deleteTask(a)
        XCTAssertEqual(store.state.tasks.count, 1)
    }

    func testDeletingDiscardsUndo() {
        store.select(c, now: at(0))
        store.deleteTask(c, now: at(1))
        XCTAssertFalse(store.canUndo(now: at(2)))
    }

    // MARK: - Reset everything

    func testResetEverythingLeavesOnlyAnEmptyTask1() {
        store.rename(a, to: "Design")
        store.select(a, now: at(0))
        store.select(b, now: at(60))
        store.deleteTask(c, now: at(70))
        store.resetEverything()

        XCTAssertEqual(store.state.tasks.map(\.name), ["Task 1"])
        XCTAssertEqual(store.state.tasks[0].accumulated, 0)
        XCTAssertFalse(store.isAnyRunning)
        XCTAssertTrue(store.state.history.isEmpty)
        XCTAssertNil(store.state.archivedTasks)
        XCTAssertEqual(store.totalToday(now: at(100)), 0)
        XCTAssertEqual(store.displayedTime(of: store.state.tasks[0].id, now: at(100)), 0)
        XCTAssertFalse(store.canUndo(now: at(61)))
        XCTAssertEqual(saves.last?.tasks.count, 1)
    }

    func testAfterResetTheNextTaskIsTask2AndHubstaffCanStartTask1() {
        store.hubstaffStateChanged(isTracking: false, now: at(0))
        store.resetEverything()
        store.addTask(name: "")
        XCTAssertEqual(store.state.tasks.map(\.name), ["Task 1", "Task 2"])

        store.hubstaffStateChanged(isTracking: true, now: at(10))
        XCTAssertTrue(store.isRunning(store.state.tasks[0].id))
    }

    func testResettingATaskResetsItsTodayAndItCountsUpAgain() {
        store.select(a, now: at(0))
        store.pauseAll(now: at(120))
        store.reset(a, now: at(130))
        XCTAssertEqual(store.todayTime(of: a, now: at(130)), 0)
        XCTAssertEqual(store.totalToday(now: at(130)), 0)

        store.select(a, now: at(200))
        XCTAssertEqual(store.todayTime(of: a, now: at(210)), 10)
        XCTAssertEqual(store.totalTime(now: at(210)), 10)
    }

    func testTaskTodayLabelOnlyShowsWhenItDiffersFromTheTaskTime() {
        store.select(a, now: at(0))
        XCTAssertNil(store.todayLabel(of: a, now: at(30)))
        XCTAssertNil(store.todayLabel(of: b, now: at(30)))

        store.setTime(of: b, to: 3600, now: at(30))
        XCTAssertNil(store.todayLabel(of: b, now: at(30)))
        store.select(b, now: at(30))
        XCTAssertEqual(store.todayLabel(of: b, now: at(90)), "today 0:01:00")
    }

    func testTaskTodayLabelAcrossMidnight() {
        store.select(a, now: date(10, 23, 50))
        XCTAssertNil(store.todayLabel(of: a, now: date(10, 23, 55)))
        XCTAssertEqual(store.todayLabel(of: a, now: date(11, 0, 10)), "today 0:10:00")
    }

    func testTotalAddsUpTheTasks() {
        store.setTime(of: a, to: 100, now: at(0))
        store.setTime(of: b, to: 20, now: at(0))
        store.select(c, now: at(0))
        XCTAssertEqual(store.totalTime(now: at(5)), 125)
    }

    func testSummaryHasNoBracketWhenAllTheTimeIsFromToday() {
        store.select(a, now: at(0))
        store.select(b, now: at(90))
        XCTAssertNil(store.todayLabelForTotal(now: at(120)))
    }

    func testSummaryShowsTodayWhenARunCrossesMidnight() {
        store.select(a, now: date(10, 23, 50))
        XCTAssertEqual(store.todayLabelForTotal(now: date(11, 0, 10)), "today 0:10:00")
        XCTAssertEqual(store.todayTime(of: a, now: date(11, 0, 10)), 600)
    }

    func testSummaryShowsTodayForTimeFromAnEarlierDay() {
        store.select(a, now: date(10, 10, 0))
        store.pauseAll(now: date(10, 11, 0))
        store.select(b, now: date(11, 9, 0))
        XCTAssertEqual(store.todayLabelForTotal(now: date(11, 9, 30)), "today 0:30:00")
    }

    func testTimeEnteredByHandWithNothingTodayShowsNoTodayLabel() {
        store.setTime(of: a, to: 3600, now: at(0))
        XCTAssertNil(store.todayLabelForTotal(now: at(0)))
    }

    func testBracketGoesAwayOnceOldTimeIsReset() {
        store.select(a, now: date(10, 10, 0))
        store.pauseAll(now: date(10, 11, 0))
        store.reset(a, now: date(11, 9, 0))
        XCTAssertNil(store.todayLabelForTotal(now: date(11, 9, 0)))
    }

    // MARK: - Current task

    func testCurrentTaskIsRunningThenLastThenFirst() {
        XCTAssertEqual(store.currentTask.id, a)
        store.select(b, now: at(0))
        XCTAssertEqual(store.currentTask.id, b)
        store.pauseAll(now: at(1))
        XCTAssertEqual(store.currentTask.id, b)
        store.deleteTask(b, now: at(2))
        XCTAssertEqual(store.currentTask.id, a)
    }

    func testTotalTodayCountsTheLiveRunOnce() {
        store.select(a, now: at(0))
        store.select(b, now: at(60))
        XCTAssertEqual(store.totalToday(now: at(90)), 90)
    }

    // MARK: - Hubstaff

    func testHubstaffStoppingPausesAndStartingContinuesTheLastTask() {
        store.hubstaffStateChanged(isTracking: true, now: at(0))
        store.select(b, now: at(0))
        store.hubstaffStateChanged(isTracking: false, now: at(60))
        XCTAssertFalse(store.isAnyRunning)
        XCTAssertEqual(store.displayedTime(of: b, now: at(100)), 60)

        store.hubstaffStateChanged(isTracking: true, now: at(100))
        XCTAssertTrue(store.isRunning(b))
        XCTAssertEqual(store.displayedTime(of: b, now: at(110)), 70)
    }

    func testFirstHubstaffReadingOnlyRecordsTheState() {
        store.select(a, now: at(0))
        store.hubstaffStateChanged(isTracking: false, now: at(10))
        XCTAssertTrue(store.isRunning(a))
        store.pauseAll(now: at(20))
        store.forgetHubstaffState()
        store.hubstaffStateChanged(isTracking: true, now: at(30))
        XCTAssertFalse(store.isAnyRunning)
    }

    func testManualChangesStandUntilHubstaffNextChanges() {
        store.hubstaffStateChanged(isTracking: true, now: at(0))
        store.select(a, now: at(0))
        store.pauseAll(now: at(10))
        store.hubstaffStateChanged(isTracking: true, now: at(20))
        XCTAssertFalse(store.isAnyRunning)

        store.hubstaffStateChanged(isTracking: false, now: at(30))
        store.select(b, now: at(40))
        store.hubstaffStateChanged(isTracking: false, now: at(50))
        XCTAssertTrue(store.isRunning(b))
    }

    func testHubstaffStartingWithNoLastTaskStartsNothing() {
        store.hubstaffStateChanged(isTracking: false, now: at(0))
        store.hubstaffStateChanged(isTracking: true, now: at(1))
        XCTAssertFalse(store.isAnyRunning)
    }

    func testHubstaffStartingWhileLockedWaitsForUnlock() {
        store.hubstaffStateChanged(isTracking: false, now: at(0))
        store.select(a, now: at(0))
        store.pauseAll(now: at(5))
        send(.lock, at: 10)
        store.hubstaffStateChanged(isTracking: true, now: at(20))
        XCTAssertFalse(store.isAnyRunning)
        send(.unlock, resume: true, at: 30)
        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.displayedTime(of: a, now: at(30)), 5)
    }

    func testHubstaffStoppingWhileLockedCancelsTheResume() {
        store.hubstaffStateChanged(isTracking: true, now: at(0))
        store.select(a, now: at(0))
        send(.lock, at: 10)
        store.hubstaffStateChanged(isTracking: false, now: at(20))
        send(.unlock, resume: true, at: 30)
        XCTAssertFalse(store.isAnyRunning)
    }

    // MARK: - History

    func testRunAcrossMidnightIsSplitBetweenDays() {
        store.toggle(a, now: date(10, 23, 50))
        store.pauseAll(now: date(11, 0, 10))

        XCTAssertEqual(store.state.history["2026-03-10"]?[a], 600)
        XCTAssertEqual(store.state.history["2026-03-11"]?[a], 600)
        XCTAssertEqual(store.state.tasks[0].accumulated, 1200)
    }

    func testRunAcrossSeveralMidnightsFillsEachDay() {
        store.toggle(a, now: date(10, 23, 0))
        store.pauseAll(now: date(12, 1, 0))

        XCTAssertEqual(store.state.history["2026-03-10"]?[a], 3600)
        XCTAssertEqual(store.state.history["2026-03-11"]?[a], 86400)
        XCTAssertEqual(store.state.history["2026-03-12"]?[a], 3600)
    }

    func testTodayOnlyCountsTheLivePortionSinceMidnight() {
        store.toggle(a, now: date(10, 23, 50))
        XCTAssertEqual(store.todayTime(of: a, now: date(11, 0, 10)), 600)
        XCTAssertEqual(store.displayedTime(of: a, now: date(11, 0, 10)), 1200)
    }

    func testTodayResetsAtMidnight() {
        store.toggle(a, now: date(10, 10, 0))
        store.pauseAll(now: date(10, 11, 0))
        XCTAssertEqual(store.todayTime(of: a, now: date(10, 12, 0)), 3600)
        XCTAssertEqual(store.todayTime(of: a, now: date(11, 0, 1)), 0)
    }

    func testClockMovingBackwardsNeverProducesNegativeTime() {
        store.toggle(a, now: at(100))
        XCTAssertEqual(store.displayedTime(of: a, now: at(50)), 0)
        store.pauseAll(now: at(50))
        XCTAssertEqual(store.state.tasks[0].accumulated, 0)
    }

    // MARK: - Relaunch

    func testRelaunchKeepsRunningAndCountsTheClosedPeriod() {
        store.toggle(a, now: at(0))
        let reopened = TimerStore(state: saves.last!, calendar: calendar) { _ in }
        reopened.reconcileAfterLaunch(lastSleep: at(-500), lastBoot: at(-900), pauseOnSleep: true, resumeAfterWake: false, now: at(120))

        XCTAssertTrue(reopened.isRunning(a))
        XCTAssertEqual(reopened.displayedTime(of: a, now: at(120)), 120)
    }

    func testRelaunchDoesNotCountSleepWhileClosed() {
        store.toggle(a, now: at(0))
        let reopened = TimerStore(state: saves.last!, calendar: calendar) { _ in }
        reopened.reconcileAfterLaunch(lastSleep: at(60), lastBoot: at(-900), pauseOnSleep: true, resumeAfterWake: false, now: at(3600))

        XCTAssertFalse(reopened.isAnyRunning)
        XCTAssertEqual(reopened.displayedTime(of: a, now: at(3600)), 60)
    }

    func testRelaunchAfterShutdownStopsAtTheLastSave() {
        var state = store.state
        state.activeTaskID = a
        state.activeSince = at(0)
        state.lastSavedAt = at(90)
        let reopened = TimerStore(state: state, calendar: calendar) { _ in }
        reopened.reconcileAfterLaunch(lastSleep: nil, lastBoot: at(500), pauseOnSleep: true, resumeAfterWake: false, now: at(600))

        XCTAssertFalse(reopened.isAnyRunning)
        XCTAssertEqual(reopened.displayedTime(of: a, now: at(600)), 90)
    }

    func testRelaunchResumesWhenResumeAfterWakeIsOn() {
        store.toggle(a, now: at(0))
        let reopened = TimerStore(state: saves.last!, calendar: calendar) { _ in }
        reopened.reconcileAfterLaunch(lastSleep: at(60), lastBoot: nil, pauseOnSleep: true, resumeAfterWake: true, now: at(3600))

        XCTAssertTrue(reopened.isRunning(a))
        XCTAssertEqual(reopened.displayedTime(of: a, now: at(3610)), 70)
    }

    func testRelaunchCountsSleepWhenPauseOnSleepIsOff() {
        store.toggle(a, now: at(0))
        let reopened = TimerStore(state: saves.last!, calendar: calendar) { _ in }
        reopened.reconcileAfterLaunch(lastSleep: at(60), lastBoot: nil, pauseOnSleep: false, resumeAfterWake: false, now: at(3600))

        XCTAssertEqual(reopened.displayedTime(of: a, now: at(3600)), 3600)
    }

    // MARK: - Sleep and lock

    private func send(_ event: SystemEvent, resume: Bool = false, pause: Bool = true, at seconds: TimeInterval) {
        store.handle(event, pauseOnSleep: pause, resumeAfterWake: resume, now: at(seconds))
    }

    func testSleepPausesAndDoesNotAutoResumeByDefault() {
        store.toggle(a, now: at(0))
        send(.sleep, at: 60)
        send(.wake, at: 360)

        XCTAssertFalse(store.isAnyRunning)
        XCTAssertEqual(store.displayedTime(of: a, now: at(400)), 60)
    }

    func testResumeAfterWakeRestartsTheTaskWithoutCountingSleep() {
        store.toggle(a, now: at(0))
        send(.sleep, resume: true, at: 60)
        send(.wake, resume: true, at: 360)

        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.displayedTime(of: a, now: at(370)), 70)
    }

    func testResumeWaitsUntilTheScreenIsUnlocked() {
        store.toggle(a, now: at(0))
        send(.lock, resume: true, at: 10)
        send(.sleep, resume: true, at: 20)
        send(.wake, resume: true, at: 100)
        XCTAssertFalse(store.isAnyRunning)

        send(.unlock, resume: true, at: 130)
        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.displayedTime(of: a, now: at(130)), 10)
    }

    func testSleepIsIgnoredWhenTheSettingIsOff() {
        store.toggle(a, now: at(0))
        send(.sleep, pause: false, at: 60)
        send(.wake, pause: false, at: 360)

        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.displayedTime(of: a, now: at(360)), 360)
    }

    func testManualStartWhilePausedCancelsTheResume() {
        store.toggle(a, now: at(0))
        send(.sleep, resume: true, at: 60)
        store.toggle(b, now: at(70))
        send(.wake, resume: true, at: 80)
        XCTAssertTrue(store.isRunning(b))
    }

    func testSleepDiscardsPendingUndo() {
        store.toggle(a, now: at(0))
        send(.sleep, at: 1)
        XCTAssertFalse(store.canUndo(now: at(2)))
    }

    // MARK: - Undo

    func testUndoSwitchCreditsTheOriginalTask() {
        store.toggle(a, now: at(0))
        store.toggle(b, now: at(60))
        store.undo(now: at(65))

        XCTAssertTrue(store.isRunning(a))
        XCTAssertEqual(store.displayedTime(of: a, now: at(65)), 65)
        XCTAssertEqual(store.displayedTime(of: b, now: at(65)), 0)
    }

    func testUndoRestoresAResetTime() {
        store.setTime(of: a, to: 500, now: at(0))
        store.reset(a, now: at(10))
        store.undo(now: at(15))
        XCTAssertEqual(store.displayedTime(of: a, now: at(15)), 500)
    }

    func testUndoExpiresAfterTenSeconds() {
        store.toggle(a, now: at(0))
        XCTAssertTrue(store.canUndo(now: at(9.9)))
        XCTAssertFalse(store.canUndo(now: at(10)))
        store.undo(now: at(11))
        XCTAssertTrue(store.isRunning(a))
    }

    func testUndoDoesNotDoubleCountHistory() {
        store.toggle(a, now: at(0))
        store.toggle(b, now: at(60))
        store.undo(now: at(65))
        store.pauseAll(now: at(70))

        XCTAssertEqual(store.todayTime(of: a, now: at(70)), 70)
        XCTAssertEqual(store.todayTime(of: b, now: at(70)), 0)
    }

    func testUndoKeepsANameEditedAfterTheAction() {
        store.toggle(a, now: at(0))
        store.rename(a, to: "Design")
        store.undo(now: at(5))
        XCTAssertEqual(store.state.tasks[0].name, "Design")
        XCTAssertFalse(store.isAnyRunning)
    }

    func testUndoIsSingleUse() {
        store.toggle(a, now: at(0))
        store.undo(now: at(1))
        XCTAssertFalse(store.canUndo(now: at(2)))
    }

    // MARK: - Compact mode

    // MARK: - Export

    func testExportIncludesTheLiveRun() {
        store.toggle(a, now: at(0))
        let history = store.historyIncludingLive(now: at(90))
        XCTAssertEqual(history["2026-03-10"]?[a], 90)
        XCTAssertNil(store.state.history["2026-03-10"])
    }
}

final class HubstaffMonitorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fakeCLI(_ script: String) throws -> String {
        let url = directory.appendingPathComponent("cli")
        try Data("#!/bin/sh\n\(script)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func testParsesTrackingAndIgnoresAnythingElse() {
        XCTAssertEqual(HubstaffMonitor.parseTracking(Data(#"{"tracking":true,"active_project":{"id":1}}"#.utf8)), true)
        XCTAssertEqual(HubstaffMonitor.parseTracking(Data(#"{"tracking":false}"#.utf8)), false)
        XCTAssertNil(HubstaffMonitor.parseTracking(Data(#"{"error":"not logged in"}"#.utf8)))
        XCTAssertNil(HubstaffMonitor.parseTracking(Data("garbage".utf8)))
    }

    func testAsksTheCLIForStatusOnly() throws {
        let log = directory.appendingPathComponent("args").path
        let cli = try fakeCLI(#"echo "$@" > "\#(log)"; echo '{"tracking":true}'; echo noise >&2"#)
        XCTAssertEqual(HubstaffMonitor(cliPath: cli).readTracking(), true)
        XCTAssertEqual(try String(contentsOfFile: log, encoding: .utf8), "status\n")
    }

    func testFailureAndHangGiveNoReading() throws {
        XCTAssertNil(HubstaffMonitor(cliPath: try fakeCLI("exit 1")).readTracking())
        XCTAssertNil(HubstaffMonitor(cliPath: directory.appendingPathComponent("missing").path).readTracking())
        let started = Date()
        XCTAssertNil(HubstaffMonitor(cliPath: try fakeCLI("sleep 30"), timeout: 0.3).readTracking())
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}

final class MenuBarSpaceTests: XCTestCase {
    private func item(_ x: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 33)
    }

    func testMatchesTheBarMeasuredOnARealMacBook() {
        let others = [item(1054, 116), item(1170, 38), item(1208, 42), item(1250, 38), item(1288, 32), item(1320, 42), item(1362, 152)]
        let space = MenuBarSpace.compute(otherIcons: others, barEnd: 1514, notchEdge: 848)
        XCTAssertEqual(space.availableWidth, 166)
    }

    func testEveryOtherIconTakesRoomWhereverItSits() {
        let right = [item(1054, 460)]
        let before = MenuBarSpace.compute(otherIcons: right, barEnd: 1514, notchEdge: 848)
        let after = MenuBarSpace.compute(otherIcons: right + [item(900, 78)], barEnd: 1514, notchEdge: 848)
        XCTAssertEqual(before.availableWidth - after.availableWidth, 78)
    }

    func testLongMenusPastTheNotchTakeRoomAndLeaveTooLittleForTheTimer() {
        let right = [item(1054, 460)]
        let free = MenuBarSpace.compute(otherIcons: right, barEnd: 1514, notchEdge: 848, menuRightEdge: 582)
        let xcode = MenuBarSpace.compute(otherIcons: right, barEnd: 1514, notchEdge: 848, menuRightEdge: 980)
        XCTAssertEqual(free.availableWidth, 166)
        XCTAssertEqual(xcode.availableWidth, 34)

        let task = TaskItem(id: UUID(), name: "Design", accumulated: 0)
        let label = MenuBarLabel(task: task, seconds: 5045, isRunning: true, availableWidth: xcode.availableWidth)
        XCTAssertNil(label.name)
        XCTAssertGreaterThan(label.width, xcode.availableWidth)
    }
}

final class MenuBarIconsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_773_144_000)
    private let own = CGRect(x: 900, y: 0, width: 154, height: 33)
    private let hubstaffFrame = CGRect(x: 1054, y: 0, width: 116, height: 33)
    private var icons: MenuBarIcons!

    override func setUp() {
        icons = MenuBarIcons()
    }

    private func occupied(_ seconds: TimeInterval, hubstaffOnScreen: Bool, ownShown: Bool = true, extra: [MenuBarSpace.Window] = []) -> CGFloat {
        var windows = [MenuBarSpace.Window(id: 7, frame: hubstaffFrame, isOnScreen: hubstaffOnScreen)] + extra
        if ownShown { windows.append(.init(id: 1, frame: own, isOnScreen: true)) }
        return icons.occupiedWindows(in: windows, ownFrame: ownShown ? own : nil, now: start.addingTimeInterval(seconds)).reduce(0) { $0 + $1.width }
    }

    func testOurOwnItemIsNeverCounted() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: true), 116)
    }

    func testAHiddenIconKeepsItsSpaceSoTheWidthStaysSteady() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: true), 116)
        for second in stride(from: TimeInterval(1), through: 600, by: 37) {
            XCTAssertEqual(occupied(second, hubstaffOnScreen: false), 116)
        }
        XCTAssertEqual(occupied(601, hubstaffOnScreen: true), 116)
    }

    func testOurOwnHiddenWindowIsNotCounted() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: true), 116)
        let hiddenSelf = MenuBarSpace.Window(id: 1, frame: own, isOnScreen: false)
        XCTAssertEqual(occupied(1, hubstaffOnScreen: true, ownShown: false, extra: [hiddenSelf]), 116)
    }

    func testAWindowHiddenAtLaunchIsALeftover() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: false), 0)
        XCTAssertEqual(occupied(5, hubstaffOnScreen: false), 0)
    }

    func testANewIconThatArrivesHiddenIsCounted() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: true), 116)
        let newIcon = MenuBarSpace.Window(id: 9, frame: CGRect(x: 800, y: 0, width: 60, height: 33), isOnScreen: false)
        XCTAssertEqual(occupied(1, hubstaffOnScreen: true, extra: [newIcon]), 176)
    }

    func testAnIconGoneBecauseItsAppQuitGivesBackItsSpace() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: true), 116)
        icons.appQuit(now: start.addingTimeInterval(10))
        XCTAssertEqual(occupied(11, hubstaffOnScreen: false), 0)
        XCTAssertEqual(occupied(60, hubstaffOnScreen: false), 0)
    }

    func testAnUnrelatedAppQuittingDoesNotForgetAHiddenIcon() {
        XCTAssertEqual(occupied(0, hubstaffOnScreen: true), 116)
        XCTAssertEqual(occupied(1, hubstaffOnScreen: false), 116)
        icons.appQuit(now: start.addingTimeInterval(100))
        XCTAssertEqual(occupied(101, hubstaffOnScreen: false), 116)
    }

    func testALeftoverWindowThatComesBackCountsAgain() {
        _ = occupied(0, hubstaffOnScreen: true)
        icons.appQuit(now: start.addingTimeInterval(1))
        XCTAssertEqual(occupied(2, hubstaffOnScreen: false), 0)
        XCTAssertEqual(occupied(30, hubstaffOnScreen: true), 116)
    }
}

final class AccessDialogTests: XCTestCase {
    func testRecognisesTheSystemPermissionDialog() {
        XCTAssertTrue(MenuBarSpace.isShowingAccessDialog(windowOwners: ["Code", "universalAccessAuthWarn", "Dock"]))
        XCTAssertFalse(MenuBarSpace.isShowingAccessDialog(windowOwners: ["Code", "System Settings", "Dock"]))
    }
}

final class FormattingTests: XCTestCase {
    func testMenuBarNameUsesAllTheRoomOnOffer() {
        let fitted = MenuBarLabel.fittedName("Design system with a long name", time: "1:24:05", availableWidth: .greatestFiniteMagnitude)
        XCTAssertEqual(fitted, "Design system with a long name")
        XCTAssertEqual(MenuBarLabel.fittedName("Docs", time: "1:24:05", availableWidth: .greatestFiniteMagnitude), "Docs")
    }

    func testMenuBarNameShortensToFitAndNeverOverflows() throws {
        let task = TaskItem(id: UUID(), name: "Design system with a long name", accumulated: 0)
        var previous = 0
        for available in stride(from: CGFloat(200), through: 60, by: -10) {
            let label = MenuBarLabel(task: task, seconds: 5045, isRunning: true, availableWidth: available)
            if label.name != nil {
                XCTAssertLessThanOrEqual(label.width, available)
            }
            XCTAssertEqual(label.time, "1:24:05")
            if previous > 0 { XCTAssertLessThanOrEqual(label.name?.count ?? 0, previous) }
            previous = label.name?.count ?? 0
        }
        XCTAssertNil(MenuBarLabel(task: task, seconds: 5045, isRunning: true, availableWidth: 60).name)
    }

    func testAHiddenItemReturnsEvenWhenItsNameFillsAllTheRoom() {
        let task = TaskItem(id: UUID(), name: "Design system with a long name", accumulated: 0)
        for available in stride(from: CGFloat(100), through: 300, by: 1) {
            let label = MenuBarLabel(task: task, seconds: 5045, isRunning: true, availableWidth: available)
            XCTAssertTrue(label.shouldShow(availableWidth: available, isVisible: false), "\(available)")
        }
    }

    func testAnItemStepsAsideOnlyWhenTheTimerItselfDoesNotFit() {
        let task = TaskItem(id: UUID(), name: "Design", accumulated: 0)
        let label = MenuBarLabel(task: task, seconds: 5045, isRunning: true, availableWidth: 34)
        XCTAssertFalse(label.shouldShow(availableWidth: 34, isVisible: true))
        XCTAssertTrue(label.shouldShow(availableWidth: label.width, isVisible: true))
        XCTAssertFalse(label.shouldShow(availableWidth: label.width, isVisible: false))
    }

    func testMenuBarWidthDoesNotDependOnRunningState() {
        let task = TaskItem(id: UUID(), name: "Design", accumulated: 0)
        let running = MenuBarLabel(task: task, seconds: 60, isRunning: true, availableWidth: 200)
        let paused = MenuBarLabel(task: task, seconds: 60, isRunning: false, availableWidth: 200)
        XCTAssertEqual(running.width, paused.width)
    }

    func testClockFormats() {
        XCTAssertEqual(Formatting.clock(0, showSeconds: false), "0:00")
        XCTAssertEqual(Formatting.clock(5040, showSeconds: false), "1:24")
        XCTAssertEqual(Formatting.clock(5045, showSeconds: true), "1:24:05")
        XCTAssertEqual(Formatting.clock(123 * 3600 + 4 * 60, showSeconds: false), "123:04")
        XCTAssertEqual(Formatting.clock(59.9, showSeconds: true), "0:00:59")
        XCTAssertEqual(Formatting.clock(-5, showSeconds: false), "0:00")
    }

}

final class CSVExportTests: XCTestCase {
    func testRowsAreNewestFirstSkipEmptyAndEscape() {
        let one = TaskItem(id: UUID(), name: "Design, \"v2\"", accumulated: 0)
        let two = TaskItem(id: UUID(), name: "Docs", accumulated: 0)
        let csv = CSVExport.csv(
            history: [
                "2026-03-11": [two.id: 3661, one.id: 0],
                "2026-03-10": [one.id: 60.7],
            ],
            tasks: [one, two]
        )
        let expected = [
            "\u{FEFF}date,task,seconds,hh:mm:ss",
            "2026-03-11,Docs,3661,01:01:01",
            #"2026-03-10,"Design, ""v2""",60,00:01:00"#,
            "",
        ].joined(separator: "\n")
        XCTAssertEqual(csv, expected)
    }
}

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripsStateIncludingHistory() {
        let persistence = Persistence(url: directory.appendingPathComponent("nested/state.json"))
        var state = AppState.initial()
        state.activeTaskID = state.tasks[1].id
        state.activeSince = Date(timeIntervalSince1970: 1_773_144_000.25)
        state.history = ["2026-03-10": [state.tasks[0].id: 12.5]]

        persistence.save(state)
        XCTAssertEqual(persistence.load(), state)
    }

    func testMissingFileGivesDefaults() {
        let state = Persistence(url: directory.appendingPathComponent("state.json")).load()
        XCTAssertEqual(state.tasks.map(\.name), ["Task 1", "Task 2"])
    }

    func testCorruptFileIsKeptAsABackup() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("state.json")
        try Data("not json".utf8).write(to: url)

        let state = Persistence(url: url).load()
        XCTAssertEqual(state.tasks.count, 2)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].contains("corrupt"))
    }

    func testSanitizeRepairsAnOrphanedActiveTask() {
        var state = AppState.initial()
        state.activeTaskID = UUID()
        state.activeSince = Date()
        let repaired = state.sanitized()
        XCTAssertNil(repaired.activeTaskID)
        XCTAssertNil(repaired.activeSince)
    }

    func testStateWithNoTasksGetsDefaults() {
        var state = AppState.initial()
        state.tasks = []
        XCTAssertEqual(state.sanitized().tasks.count, 2)
    }
}
