import SwiftUI

/// Rename / set time sheet, with reset and delete.
struct EditTaskView: View {
    let store: TimerStore
    let task: TaskItem
    let onClose: () -> Void

    @State private var name: String
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @FocusState private var isNameFocused: Bool
    @State private var isConfirmingReset = false
    @State private var isConfirmingDelete = false
    private let originalTime: Int

    init(store: TimerStore, task: TaskItem, onClose: @escaping () -> Void) {
        self.store = store
        self.task = task
        self.onClose = onClose
        let time = Int(store.displayedTime(of: task.id))
        self.originalTime = time
        _name = State(initialValue: task.name)
        _hours = State(initialValue: time / 3600)
        _minutes = State(initialValue: time % 3600 / 60)
        _seconds = State(initialValue: time % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            HStack(spacing: 10) {
                TimeField(title: "H", value: $hours, range: 0...9999)
                TimeField(title: "M", value: $minutes, range: 0...59)
                TimeField(title: "S", value: $seconds, range: 0...59)
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

    private func save() {
        store.rename(task.id, to: name)
        // Comparing to the time when the panel opened means a rename doesn't rewind a running task.
        let newTime = hours * 3600 + minutes * 60 + seconds
        if newTime != originalTime {
            store.setTime(of: task.id, to: TimeInterval(newTime))
        }
        onClose()
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
