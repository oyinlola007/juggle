import Foundation

struct Persistence {
    let url: URL

    static let standard = Persistence(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Juggle", isDirectory: true)
            .appendingPathComponent("state.json")
    )

    /// The app used to be called TaskTimer. Moves its data across once, never over newer data.
    static func moveDataFromOldName(in supportDirectory: URL) {
        let old = supportDirectory.appendingPathComponent("TaskTimer", isDirectory: true)
        let new = supportDirectory.appendingPathComponent("Juggle", isDirectory: true)
        let files = FileManager.default
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return }
        try? files.moveItem(at: old, to: new)
    }

    func load() -> AppState {
        guard let data = try? Data(contentsOf: url) else { return .initial() }
        do {
            return try JSONDecoder().decode(AppState.self, from: data).sanitized()
        } catch {
            // Keep the unreadable file so its time can still be recovered by hand.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("Juggle: could not read state (\(error)); moved it to \(backup.path)")
            return .initial()
        }
    }

    func save(_ state: AppState) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: url, options: .atomic)
        } catch {
            NSLog("Juggle: could not save state: \(error)")
        }
    }
}
