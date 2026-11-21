import SwiftUI

/// Rename, set tracked time, and change or remove time added by hand; with reset and delete.
struct EditTaskView: View {
    let store: TimerStore
    let task: TaskItem
    let onClose: () -> Void

    @State private var name: String
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var entries: [EntryDraft]
    @State private var newEntry = ""
    @FocusState private var isNameFocused: Bool
    @State private var isConfirmingReset = false
    @State private var isConfirmingDelete = false
    private let originalTracked: Int

    init(store: TimerStore, task: TaskItem, onClose: @escaping () -> Void) {
        self.store = store
        self.task = task
        self.onClose = onClose
        let tracked = Int(store.trackedTime(of: task.id))
        self.originalTracked = tracked
        _name = State(initialValue: task.name)
        _hours = State(initialValue: tracked / 3600)
        _minutes = State(initialValue: tracked % 3600 / 60)
        _seconds = State(initialValue: tracked % 60)
        _entries = State(initialValue: store.entries(of: task.id).map(EntryDraft.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Task")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onChange(of: name) { _, newValue in
                    if newValue.count > TaskItem.maxNameLength {
                        name = String(newValue.prefix(TaskItem.maxNameLength))
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tracked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    TimeField(title: "H", value: $hours, range: 0...9999)
                    TimeField(title: "M", value: $minutes, range: 0...59)
                    TimeField(title: "S", value: $seconds, range: 0...59)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Added")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !entries.isEmpty {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach($entries) { $entry in
                                EntryRow(entry: $entry) {
                                    entries.removeAll { $0.id == entry.id }
                                }
                            }
                        }
                        // Room for the fields' borders, which the scroll view would clip.
                        .padding(3)
                    }
                    .padding(-3)
                    .frame(maxHeight: 150)
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Add time", text: $newEntry, prompt: Text("Add time, e.g. 12m, 1:05, 1h 5m or 4m 32s"))
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(isNewEntryValid ? .primary : Color.red)
                }
            }

            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Formatting.clock(total, showSeconds: true))
                    .monospacedDigit()
            }

            HStack {
                Button("Reset…") { isConfirmingReset = true }
                Button("Delete…", role: .destructive) { isConfirmingDelete = true }
                    .disabled(store.state.tasks.count <= 1)
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 380)
        .alert("Reset \(task.name) to 0:00?", isPresented: $isConfirmingReset) {
            Button("Reset", role: .destructive) {
                store.reset(task.id)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Daily history is kept.")
        }
        .alert("Delete \(task.name)?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                store.deleteTask(task.id)
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It leaves your task list, but its past time stays in the CSV export. This can't be undone.")
        }
        .onAppear {
            // The field can't take focus until the panel has been installed in the window.
            DispatchQueue.main.async { isNameFocused = true }
        }
    }

    private var trackedSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }

    private var newEntrySeconds: TimeInterval? {
        Formatting.parseDuration(newEntry)
    }

    private var isNewEntryValid: Bool {
        newEntry.trimmingCharacters(in: .whitespaces).isEmpty || newEntrySeconds != nil
    }

    private var canSave: Bool {
        isNewEntryValid && entries.allSatisfy { $0.seconds != nil }
    }

    private var total: TimeInterval {
        TimeInterval(trackedSeconds) + entries.compactMap(\.seconds).reduce(0, +) + (newEntrySeconds ?? 0)
    }

    private func save() {
        guard canSave else { return }
        var saved = entries.compactMap { draft in
            draft.seconds.map { TimeEntry(id: draft.id, taskID: task.id, seconds: $0, addedAt: draft.addedAt) }
        }
        if let newEntrySeconds {
            saved.append(TimeEntry(id: UUID(), taskID: task.id, seconds: newEntrySeconds, addedAt: Date()))
        }
        // Comparing to the time when the panel opened means a rename doesn't rewind a running task.
        let tracked = trackedSeconds != originalTracked ? TimeInterval(trackedSeconds) : nil
        store.edit(task.id, name: name, tracked: tracked, entries: saved)
        onClose()
    }
}

/// An added-time entry being edited: its amount as typed, read back on Save.
private struct EntryDraft: Identifiable {
    let id: UUID
    let addedAt: Date
    var text: String

    init(_ entry: TimeEntry) {
        id = entry.id
        addedAt = entry.addedAt
        text = Formatting.clock(entry.seconds, showSeconds: true)
    }

    var seconds: TimeInterval? {
        Formatting.parseDuration(text)
    }
}

private struct EntryRow: View {
    @Binding var entry: EntryDraft
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Time", text: $entry.text)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .labelsHidden()
                .foregroundStyle(entry.seconds == nil ? Color.red : .primary)
                .frame(width: 96)
            Text(addedLabel)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(entry.text)")
        }
    }

    private var addedLabel: String {
        Calendar.current.isDateInToday(entry.addedAt)
            ? entry.addedAt.formatted(date: .omitted, time: .shortened)
            : entry.addedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

/// A number field and stepper. The field writes on every keystroke, so clicking Save without
/// leaving the field still uses what was typed.
private struct TimeField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .labelsHidden()
                Stepper(title, value: $value, in: range)
                    .labelsHidden()
            }
        }
    }

    private var text: Binding<String> {
        Binding(
            get: { String(value) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                value = min(max(Int(digits) ?? 0, range.lowerBound), range.upperBound)
            }
        )
    }
}
