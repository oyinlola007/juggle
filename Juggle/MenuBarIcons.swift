import Foundation

/// Tracks other apps' menu bar icons, so an icon macOS has hidden keeps its space. A hidden
/// icon's space looks free, and taking it would keep the icon hidden for good.
final class MenuBarIcons {
    /// A closing app leaves its window behind, hidden. One that went hidden this close to an
    /// app quitting is treated as that leftover rather than as an icon waiting to return.
    static let leftoverWindow: TimeInterval = 3

    private var knownIDs: Set<Int>?
    private var waitingToReturn = Set<Int>()
    private var ownIDs = Set<Int>()
    private var leftoverIDs = Set<Int>()
    private var hiddenSince: [Int: Date] = [:]
    private var lastAppQuit = Date.distantPast

    /// Everything but our own item: icons on screen, and icons waiting to come back.
    func occupiedWindows(in windows: [MenuBarSpace.Window], ownFrame: CGRect?, now: Date = Date()) -> [CGRect] {
        if let ownFrame {
            for window in windows where window.isOnScreen && abs(window.frame.maxX - ownFrame.maxX) <= 1.5 {
                ownIDs.insert(window.id)
            }
        }
        let others = windows.filter { !ownIDs.contains($0.id) }

        // Windows already hidden at launch are leftovers. One first seen hidden later is a
        // new icon that didn't fit.
        let isFirstUpdate = knownIDs == nil
        var known = knownIDs ?? []
        for window in others {
            if window.isOnScreen {
                waitingToReturn.insert(window.id)
                leftoverIDs.remove(window.id)
                hiddenSince[window.id] = nil
            } else {
                if !known.contains(window.id), !isFirstUpdate {
                    waitingToReturn.insert(window.id)
                }
                let since = hiddenSince[window.id] ?? now
                hiddenSince[window.id] = since
                if abs(since.timeIntervalSince(lastAppQuit)) <= Self.leftoverWindow {
                    leftoverIDs.insert(window.id)
                }
            }
            known.insert(window.id)
        }
        knownIDs = known

        return others
            .filter { $0.isOnScreen || (waitingToReturn.contains($0.id) && !leftoverIDs.contains($0.id)) }
            .map(\.frame)
    }

    func appQuit(now: Date = Date()) {
        lastAppQuit = now
        for (id, since) in hiddenSince where abs(since.timeIntervalSince(now)) <= Self.leftoverWindow {
            leftoverIDs.insert(id)
        }
    }
}
