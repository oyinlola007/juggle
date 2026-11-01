import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@main
struct JuggleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app window is owned by AppDelegate: an agent app's popover can't reliably
        // open a SwiftUI scene. This scene supplies the standard main menu,
        // which is what makes ⌘C/⌘V work in text fields.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.openWindow(tab: .settings) }
                    .keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var store: TimerStore!
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private let labelView = MenuBarLabelView()
    private var lastPopoverClose = Date.distantPast
    private var keyMonitor: Any?
    private var mainWindow: NSWindow?
    private let hubstaff = HubstaffMonitor(cliPath: HubstaffMonitor.installedCLIPath)
    private let hubstaffQueue = DispatchQueue(label: "Juggle.hubstaff")
    private var isReadingHubstaff = false
    private let icons = MenuBarIcons()
    private var shortcutTaskCount = 0
    private var frontMenuRightEdge: CGFloat?
    private let menuQueue = DispatchQueue(label: "Juggle.menus")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app and must not touch the real state or menu bar.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        SettingsKey.registerDefaults()
        let persistence = Persistence.standard
        store = TimerStore(state: persistence.load(), persist: persistence.save)
        store.reconcileAfterLaunch(
            lastSleep: SystemClock.lastSleep,
            lastBoot: SystemClock.lastBoot,
            pauseOnSleep: pauseOnSleep,
            resumeAfterWake: shouldResume
        )
        store.onChange = { [weak self] in
            self?.refreshStatusItem()
            self?.syncShortcuts()
        }

        setUpStatusItem()
        setUpPopover()
        syncShortcuts()
        setUpSystemObservers()
        startTimers()
        refreshStatusItem()
        pollHubstaff()
        updateFrontMenuEdge()
        LoginItem.applySettingAtLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveNow()
    }

    // MARK: - Settings

    private var pauseOnSleep: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.pauseOnSleep)
    }

    private var followsHubstaff: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.followHubstaff) && HubstaffMonitor.isInstalled
    }

    /// Whether a task paused by sleep or lock restarts afterwards. If Hubstaff kept
    /// tracking through a lock, the timer has to catch back up with it.
    private var shouldResume: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.resumeAfterWake)
            || (followsHubstaff && store.state.hubstaffWasTracking == true)
    }

    // MARK: - App window

    /// Starts on Tasks unless told otherwise, whichever tab was open last.
    func openWindow(tab: MainTab = .tasks) {
        guard store != nil else { return }
        let view = MainWindowView(store: store, exportCSV: { [weak self] in self?.exportCSV() }, tab: tab)
        let controller = NSHostingController(rootView: view)
        if let mainWindow {
            mainWindow.contentViewController = controller
        } else {
            let window = NSWindow(contentViewController: controller)
            window.title = "Juggle"
            window.titlebarSeparatorStyle = .none
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            mainWindow = window
        }
        NSApp.unhide(nil)
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        popover.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        labelView.frame = button.bounds
        labelView.autoresizingMask = [.width, .height]
        button.addSubview(labelView)
    }

    private func refreshStatusItem(now: Date = Date()) {
        let task = store.currentTask
        let isRunning = store.isRunning(task.id)
        let available = measureAvailableWidth()
        let label = MenuBarLabel(
            task: task,
            seconds: store.displayedTime(of: task.id, now: now),
            isRunning: isRunning,
            availableWidth: available
        )
        updateVisibility(label: label, available: available)
        guard label != labelView.label else { return }
        labelView.label = label

        if statusItem.length != label.width {
            statusItem.length = label.width
        }
        statusItem.button?.toolTip = label.fullName
        statusItem.button?.setAccessibilityTitle("\(label.fullName), \(label.time), \(isRunning ? "running" : "paused")")
    }

    /// When even the timer doesn't fit, this item steps aside rather than letting macOS hide
    /// another app's icon.
    private func updateVisibility(label: MenuBarLabel, available: CGFloat) {
        guard !popover.isShown else { return }
        let shouldShow = label.shouldShow(availableWidth: available, isVisible: statusItem.isVisible)
        if statusItem.isVisible != shouldShow {
            statusItem.isVisible = shouldShow
        }
    }

    /// Worked out from what's in the bar right now, so the same bar always gives the same answer.
    private func measureAvailableWidth() -> CGFloat {
        let ownWindow = statusItem.isVisible ? statusItem.button?.window : nil
        guard let screen = ownWindow?.screen ?? NSScreen.main, let notchEdge = screen.auxiliaryTopRightArea?.minX else {
            return .greatestFiniteMagnitude
        }
        let windows = MenuBarSpace.windows(on: screen)
        return MenuBarSpace.compute(
            otherIcons: icons.occupiedWindows(in: windows, ownFrame: ownWindow?.frame),
            barEnd: windows.filter(\.isOnScreen).map(\.frame.maxX).max() ?? notchEdge,
            notchEdge: notchEdge,
            menuRightEdge: frontMenuRightEdge
        ).availableWidth
    }

    /// Reads where the frontmost app's menus end. Juggle itself is skipped: it only comes
    /// forward for the dropdown or window, and the app underneath returns right after.
    private func updateFrontMenuEdge() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        menuQueue.async { [weak self] in
            let edge = MenuBarSpace.menuRightEdge(of: app)
            DispatchQueue.main.async {
                guard let self, self.frontMenuRightEdge != edge else { return }
                self.frontMenuRightEdge = edge
                self.refreshStatusItem()
            }
        }
    }

    @objc private func appQuit() {
        icons.appQuit()
    }

    @objc private func appActivated() {
        updateFrontMenuEdge()
        // Some apps fill in their menus just after coming forward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updateFrontMenuEdge() }
    }

    @objc private func statusItemClicked() {
        // A transient popover closes itself on mouse-down, before this mouse-up arrives.
        // Without this check, clicking to close it would immediately reopen it.
        guard Date().timeIntervalSince(lastPopoverClose) > 0.3 else { return }
        togglePopover()
    }

    // MARK: - Popover

    private func setUpPopover() {
        let actions = PopoverActions(
            close: { [weak self] in self?.popover.performClose(nil) },
            openWindow: { [weak self] in self?.openWindow() }
        )
        let controller = NSHostingController(rootView: PopoverView(store: store, actions: actions))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // The shortcut can open the list while this item has stepped aside.
        guard statusItem.isVisible else {
            statusItem.isVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.showPopover() }
            return
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        labelView.isHighlighted = true
        installKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClose = Date()
        labelView.isHighlighted = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        // Opening the popover activated this app; hand the keyboard back to the previous one.
        if mainWindow?.isVisible != true {
            NSApp.hide(nil)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, event.window == self.popover.contentViewController?.view.window else {
                return event
            }
            return self.handlePopoverKey(event) ? nil : event
        }
    }

    /// Inside the open popover: 1–9 start a task, Space pauses all, Esc closes.
    private func handlePopoverKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if event.keyCode == 53 {
            popover.performClose(nil)
            return true
        }
        guard let key = event.charactersIgnoringModifiers else { return false }
        if key == " " {
            store.pauseAll()
        } else if let number = Int(key), number >= 1 {
            store.selectTask(at: number - 1)
        } else {
            return false
        }
        popover.performClose(nil)
        return true
    }

    // MARK: - Export

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Juggle history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let tasks = store.state.tasks + (store.state.archivedTasks ?? [])
        let csv = CSVExport.csv(history: store.historyIncludingLive(), tasks: tasks)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Shortcuts

    /// Called whenever tasks change. Only positions with a task respond; a shortcut on any
    /// other position stays saved for the next task to reach it.
    private func syncShortcuts() {
        let count = store.state.tasks.count
        guard count != shortcutTaskCount else { return }
        shortcutTaskCount = count

        KeyboardShortcuts.removeAllHandlers()
        for index in 0..<count {
            KeyboardShortcuts.onKeyDown(for: .taskPosition(index)) { [weak self] in self?.store.toggleTask(at: index) }
        }
        KeyboardShortcuts.onKeyDown(for: .pauseAllTasks) { [weak self] in self?.store.pauseAll() }
        KeyboardShortcuts.onKeyDown(for: .undoLastAction) { [weak self] in self?.store.undo() }
        KeyboardShortcuts.onKeyDown(for: .toggleTaskList) { [weak self] in self?.togglePopover() }
    }

    // MARK: - Hubstaff

    private func pollHubstaff() {
        guard followsHubstaff else {
            store.forgetHubstaffState()
            return
        }
        // No process is started while Hubstaff is closed, and closed means not tracking.
        guard HubstaffMonitor.isRunning else {
            store.hubstaffStateChanged(isTracking: false)
            return
        }
        guard !isReadingHubstaff else { return }
        isReadingHubstaff = true
        let hubstaff = self.hubstaff
        hubstaffQueue.async { [weak self] in
            let tracking = hubstaff.readTracking()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReadingHubstaff = false
                // No usable answer changes nothing: a hiccup shouldn't pause the timer.
                if let tracking, self.followsHubstaff {
                    self.store.hubstaffStateChanged(isTracking: tracking)
                }
            }
        }
    }

    // MARK: - Sleep, lock and timers

    private func setUpSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appQuit), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately)
        distributed.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately)
    }

    @objc private func willSleep() { handle(.sleep) }
    @objc private func didWake() { handle(.wake) }
    @objc private func screenLocked() { handle(.lock) }
    @objc private func screenUnlocked() { handle(.unlock) }

    private func handle(_ event: SystemEvent) {
        store.handle(event, pauseOnSleep: pauseOnSleep, resumeAfterWake: shouldResume)
    }

    private func startTimers() {
        // Rule 8: this only redraws labels; it never adds time.
        let redraw = Timer(timeInterval: 1, target: self, selector: #selector(redrawTick), userInfo: nil, repeats: true)
        redraw.tolerance = 0.1
        RunLoop.main.add(redraw, forMode: .common)

        let save = Timer(timeInterval: 30, target: self, selector: #selector(saveTick), userInfo: nil, repeats: true)
        save.tolerance = 1
        RunLoop.main.add(save, forMode: .common)

        let hubstaffPoll = Timer(timeInterval: 3, target: self, selector: #selector(hubstaffTick), userInfo: nil, repeats: true)
        hubstaffPoll.tolerance = 0.5
        RunLoop.main.add(hubstaffPoll, forMode: .common)

        let menuCheck = Timer(timeInterval: 5, target: self, selector: #selector(menuTick), userInfo: nil, repeats: true)
        menuCheck.tolerance = 1
        RunLoop.main.add(menuCheck, forMode: .common)
    }

    @objc private func redrawTick() { refreshStatusItem() }
    @objc private func saveTick() { store.heartbeat() }
    @objc private func hubstaffTick() { pollHubstaff() }
    @objc private func menuTick() { updateFrontMenuEdge() }
}
