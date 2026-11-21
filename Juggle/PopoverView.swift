import SwiftUI

struct PopoverActions {
    let close: () -> Void
    let openWindow: () -> Void
    /// Starts a task; the delegate decides whether to offer adding time or close.
    let start: (UUID) -> Void
    let submitTime: () -> Void
    /// The user is typing in the add-time field, so it shouldn't close by itself.
    let keepOpen: () -> Void
}

/// The add-time field shown under a task just after switching to it.
@Observable
final class AddTimePrompt {
    var taskID: UUID?
    var text = ""
}

/// Green while a task runs, grey otherwise, matching the menu bar.
struct StatusDot: View {
    let isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 7, height: 7)
    }
}

/// One line of the dropdown, highlighted on hover like a native menu item.
private struct MenuRow<Leading: View, Trailing: View>: View {
    static var height: CGFloat { 26 }

    let title: String
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading
                    .frame(width: 12)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered && isEnabled ? Color.primary.opacity(0.09) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

/// The dropdown: click a task to run it, or pause. Everything else is in the app window.
struct PopoverView: View {
    private static let padding: CGFloat = 5
    private static let maxVisibleRows: CGFloat = 10

    let store: TimerStore
    let prompt: AddTimePrompt
    let actions: PopoverActions

    var body: some View {
        // The timeline only redraws; all times are computed from timestamps.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = Date()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.state.tasks) { task in
                            taskRow(task, now: now)
                            if prompt.taskID == task.id {
                                AddTimeField(prompt: prompt, actions: actions)
                            }
                        }
                    }
                    .padding(Self.padding)
                }
                .frame(height: listHeight)

                Divider()

                VStack(spacing: 0) {
                    MenuRow(title: "Pause All", isEnabled: store.isAnyRunning, action: {
                        store.pauseAll()
                        actions.close()
                    }, leading: {
                        Image(systemName: "pause.fill").font(.system(size: 10))
                    }, trailing: {
                        EmptyView()
                    })
                    .foregroundStyle(store.isAnyRunning ? .primary : .tertiary)

                    MenuRow(title: "Open Juggle…", action: actions.openWindow, leading: {
                        Image(systemName: "macwindow").font(.system(size: 11))
                    }, trailing: {
                        EmptyView()
                    })
                }
                .padding(Self.padding)
            }
        }
        .frame(width: 250)
    }

    private var listHeight: CGFloat {
        let promptRows = prompt.taskID == nil ? 0 : 1
        let rows = min(CGFloat(store.state.tasks.count + promptRows), Self.maxVisibleRows)
        return rows * MenuRow<EmptyView, EmptyView>.height + Self.padding * 2
    }

    private func taskRow(_ task: TaskItem, now: Date) -> some View {
        let isRunning = store.isRunning(task.id)
        return MenuRow(title: task.name, action: {
            actions.start(task.id)
        }, leading: {
            StatusDot(isRunning: isRunning)
        }, trailing: {
            Text(Formatting.clock(store.displayedTime(of: task.id, now: now), showSeconds: true))
                .monospacedDigit()
                .foregroundStyle(isRunning ? .primary : .secondary)
                .fixedSize()
        })
        .help(task.name)
    }
}

/// Type `12`, `1:05` or `4m 32s` and press Return. Esc or clicking away adds nothing.
private struct AddTimeField: View {
    @Bindable var prompt: AddTimePrompt
    let actions: PopoverActions

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            TextField("Add time", text: $prompt.text)
                .textFieldStyle(.plain)
                .monospacedDigit()
                .focused($isFocused)
                .onSubmit(actions.submitTime)
                .onChange(of: prompt.text) { actions.keepOpen() }
        }
        .padding(.horizontal, 8)
        .frame(height: MenuRow<EmptyView, EmptyView>.height)
        // The field can't take focus until it's in the popover's window.
        .onAppear { DispatchQueue.main.async { isFocused = true } }
    }
}
