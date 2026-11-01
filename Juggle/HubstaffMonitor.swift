import AppKit

/// Reads whether Hubstaff is tracking, through the command-line tool it ships with.
/// Only ever asks for `status`: this app must never start or stop Hubstaff's timer.
struct HubstaffMonitor {
    static let bundleIdentifier = "com.netsoft.Hubstaff"
    static let installedCLIPath = "/Applications/Hubstaff.app/Contents/MacOS/HubstaffCLI"

    let cliPath: String
    var timeout: TimeInterval = 5

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: installedCLIPath)
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// True or false from Hubstaff, or nil if it gave no usable answer. Blocks, so call off the main thread.
    func readTracking() -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["status"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return Self.parseTracking(output.fileHandleForReading.readDataToEndOfFile())
    }

    static func parseTracking(_ data: Data) -> Bool? {
        struct Status: Decodable {
            let tracking: Bool
        }
        return (try? JSONDecoder().decode(Status.self, from: data))?.tracking
    }
}
