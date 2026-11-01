import Foundation

/// Reads when the Mac last slept and booted, so a relaunch can tell what happened while closed.
enum SystemClock {
    static var lastSleep: Date? { date(sysctl: "kern.sleeptime") }
    static var lastBoot: Date? { date(sysctl: "kern.boottime") }

    private static func date(sysctl name: String) -> Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
    }
}
