import KeyboardShortcuts
import SwiftUI

enum SettingsKey {
    static let pauseOnSleep = "pauseOnSleep"
    static let resumeAfterWake = "resumeAfterWake"
    static let launchAtLogin = "launchAtLogin"
    static let followHubstaff = "followHubstaff"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pauseOnSleep: true,
            resumeAfterWake: false,
            launchAtLogin: true,
            followHubstaff: true,
        ])
    }
}

enum MainTab: String, CaseIterable, Identifiable {
    case tasks = "Tasks"
    case settings = "Settings"
    var id: Self { self }
}

/// The app window: everything that isn't starting a task or pausing.
struct MainWindowView: View {
    private static let settingsHeight: CGFloat = 560

    let store: TimerStore
    let exportCSV: () -> Void
    @State var tab = MainTab.tasks

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                ForEach(MainTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 10)

            Divider()

            switch tab {
            case .tasks:
                TasksTab(store: store, exportCSV: exportCSV)
                    .frame(height: TasksTab.height(taskCount: store.state.tasks.count))
            case .settings:
                SettingsTab(store: store)
                    .frame(height: Self.settingsHeight)
            }
        }
        .frame(width: 460)
    }
}

// MARK: - Tasks

private struct TasksTab: View {
    private static let headerHeight: CGFloat = 56
    private static let footerHeight: CGFloat = 52
    private static let listPadding: CGFloat = 6
    private static let maxVisibleRows = 12

    /// The window fits its tasks, plus the new-task row, and scrolls beyond that.
    static func height(taskCount: Int) -> CGFloat {
        let rows = CGFloat(min(taskCount + 1, maxVisibleRows))
        return headerHeight + footerHeight + rows * TaskRow.height + listPadding * 2 + 2
    }

    let store: TimerStore
    let exportCSV: () -> Void

    @State private var newTaskName = ""
    @State private var editingTask: TaskItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.state.tasks) { task in
                        TaskRow(store: store, task: task) { editingTask = task }
                    }
                    newTaskRow
                }
                .padding(.horizontal, 8)
                .padding(.vertical, Self.listPadding)
            }
            Divider()
            footer
        }
        .sheet(item: $editingTask) { task in
            EditTaskView(store: store, task: task) { editingTask = nil }
        }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date()
            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let today = store.todayLabelForTotal(now: now) {
                    Text(today)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(Formatting.clock(store.totalTime(now: now), showSeconds: true))
                    .font(.system(size: 26))
            }
            .monospacedDigit()
            .padding(.leading, 16)
            // Lines the total up with the column of task times, not the edit buttons.
            .padding(.trailing, 40)
            .frame(height: Self.headerHeight)
        }
    }

    private var newTaskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 8)
            TextField("New task", text: $newTaskName, prompt: Text("New Task"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .onSubmit(addTask)
            if !newTaskName.isEmpty {
                Button("Add Task", action: addTask)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: TaskRow.height)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Export CSV…", action: exportCSV)
            Spacer()
            Button("Pause All") { store.pauseAll() }
                .disabled(!store.isAnyRunning)
            Button("Reset All…", action: confirmResetEverything)
        }
        .padding(.horizontal, 16)
        .frame(height: Self.footerHeight)
    }

    private func addTask() {
        guard !newTaskName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addTask(name: newTaskName)
        newTaskName = ""
    }

    private func confirmResetEverything() {
        let alert = NSAlert()
        alert.messageText = "Reset everything?"
        alert.informativeText = "This deletes all your tasks and daily history, and leaves only Task 1 at 0:00. You can't undo this."
        let reset = alert.addButton(withTitle: "Reset Everything")
        reset.hasDestructiveAction = true
        reset.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        if alert.runModal() == .alertFirstButtonReturn {
            store.resetEverything()
        }
    }
}

private struct TaskRow: View {
    static let height: CGFloat = 30

    let store: TimerStore
    let task: TaskItem
    let onEdit: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(isRunning: store.isRunning(task.id))
                .frame(width: 8)
            Text(task.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(task.name)
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let now = Date()
                HStack(spacing: 10) {
                    if let today = store.todayLabel(of: task.id, now: now) {
                        Text(today)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(Formatting.clock(store.displayedTime(of: task.id, now: now), showSeconds: true))
                }
                .monospacedDigit()
                .fixedSize()
            }
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Edit")
            .accessibilityLabel("Edit \(task.name)")
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings

private struct SettingsTab: View {
    let store: TimerStore

    @AppStorage(SettingsKey.pauseOnSleep) private var pauseOnSleep = true
    @AppStorage(SettingsKey.resumeAfterWake) private var resumeAfterWake = false
    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(SettingsKey.followHubstaff) private var followHubstaff = true

    @State private var loginItemError: String?
    @State private var hasMenuAccess = MenuBarSpace.canReadMenus

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if hasMenuAccess {
                        HStack(spacing: 10) {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("Manage…") { MenuBarSpace.openAccessibilitySettings() }
                        }
                        .fixedSize()
                    } else {
                        Button("Allow…") { MenuBarSpace.requestMenuAccess() }
                    }
                } label: {
                    Text("Make room for long app menus")
                    Text("Lets the timer step aside before an icon gets hidden. Accessibility access is used only to read where an app's menus end. If Juggle is listed in System Settings but this still says Allow, remove it with the − button, then click Allow again.")
                }
            }

            if HubstaffMonitor.isInstalled {
                Section {
                    Toggle(isOn: $followHubstaff) {
                        Text("Follow Hubstaff")
                        Text("Pauses when Hubstaff stops, and continues the last task when it starts. Juggle never starts or stops Hubstaff.")
                    }
                }
            }

            Section {
                Toggle("Pause when Mac sleeps or the screen locks", isOn: $pauseOnSleep)
                Toggle("Resume after wake", isOn: $resumeAfterWake)
                    .disabled(!pauseOnSleep)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        applyLaunchAtLogin(enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if LoginItem.needsApproval {
                    Button("Approve in Login Items…") {
                        LoginItem.openSystemSettings()
                    }
                }
            }

            Section("Keyboard Shortcuts") {
                ForEach(Array(store.state.tasks.enumerated()), id: \.offset) { index, task in
                    KeyboardShortcuts.Recorder("Start or pause \(task.name)", name: .taskPosition(index))
                }
                KeyboardShortcuts.Recorder("Pause all", name: .pauseAllTasks)
                KeyboardShortcuts.Recorder("Open or close the task list", name: .toggleTaskList)
                KeyboardShortcuts.Recorder("Undo last action", name: .undoLastAction)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit Juggle") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Rechecked on return from System Settings, and regularly while this tab is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasMenuAccess = MenuBarSpace.canReadMenus
        }
        .task {
            while !Task.isCancelled {
                hasMenuAccess = MenuBarSpace.canReadMenus
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}
