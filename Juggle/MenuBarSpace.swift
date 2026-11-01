import AppKit
import ApplicationServices

/// How much of the menu bar is free. The window server lists every app's menu bar item,
/// which needs no permission, so this sees icons on either side of ours. The frontmost
/// app's menus can also run past the notch, and reading those needs Accessibility access.
struct MenuBarSpace: Equatable {
    /// Measured on a MacBook: the bar overflows when items start less than about 20 pt past
    /// the notch. The rest of this gap is a safety margin.
    private static let clearance: CGFloat = 24
    /// A menu bar item's window is this much wider than the item's length.
    private static let windowOverhead: CGFloat = 16
    private static let statusWindowLayer = 25
    private static let maxBarHeight: CGFloat = 40

    struct Window: Equatable {
        let id: Int
        let frame: CGRect
        let isOnScreen: Bool
    }

    let availableWidth: CGFloat

    /// `otherIcons` are every other app's icons, including any waiting to come back.
    static func compute(otherIcons: [CGRect], barEnd: CGFloat, notchEdge: CGFloat, menuRightEdge: CGFloat? = nil) -> MenuBarSpace {
        let occupied = otherIcons.reduce(0) { $0 + $1.width }
        let leftLimit = max(notchEdge, menuRightEdge ?? notchEdge) + clearance
        return MenuBarSpace(availableWidth: barEnd - leftLimit - occupied - windowOverhead)
    }

    /// Every menu bar item window on `screen`, including hidden ones.
    static func windows(on screen: NSScreen) -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        // Window server coordinates start at the top of the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenTop = primaryHeight - screen.frame.maxY
        return list.compactMap { info -> Window? in
            guard info[kCGWindowLayer as String] as? Int == statusWindowLayer,
                  let id = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.height <= maxBarHeight, abs(rect.minY - screenTop) <= 2,
                  rect.minX >= screen.frame.minX, rect.minX < screen.frame.maxX else {
                return nil
            }
            return Window(id: id, frame: rect, isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }
    }

    // MARK: - Frontmost app's menus

    /// Either check can lag behind the other, depending on how the app was launched and
    /// whether access was granted while it was running, so either one counts.
    /// The Dock is a safe app to try a real read on: it is always running, and isn't this app.
    static var canReadMenus: Bool {
        if AXIsProcessTrusted() {
            return true
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return false
        }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success
    }

    /// Asks macOS for its permission dialog, whose own button leads to System Settings. macOS
    /// doesn't always show it, so the settings pane only opens here if no dialog appeared.
    static func requestMenuAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !canReadMenus, !isShowingAccessDialog(windowOwners: onScreenWindowOwners()) else { return }
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func isShowingAccessDialog(windowOwners: [String]) -> Bool {
        windowOwners.contains("universalAccessAuthWarn")
    }

    private static func onScreenWindowOwners() -> [String] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { $0[kCGWindowOwnerName as String] as? String }
    }

    /// Where an app's menus end, or nil without Accessibility access. Menus run left to right,
    /// so only the last one is read. Blocks, so call off the main thread.
    static func menuRightEdge(of app: NSRunningApplication) -> CGFloat? {
        guard canReadMenus else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)

        func value(_ source: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyAttributeValue(source, attribute as CFString, &result) == .success ? result : nil
        }
        guard let bar = value(element, kAXMenuBarAttribute),
              let items = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement],
              let last = items.last,
              let position = value(last, kAXPositionAttribute),
              let size = value(last, kAXSizeAttribute) else {
            return nil
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return origin.x + extent.width
    }
}
