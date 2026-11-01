import Foundation
import ServiceManagement

enum LoginItem {
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Applies the default-ON setting, but only for an installed copy, so running from
    /// Xcode doesn't leave a login item pointing into DerivedData.
    static func applySettingAtLaunch() {
        guard UserDefaults.standard.bool(forKey: SettingsKey.launchAtLogin),
              isInstalled,
              SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
    }

    private static var isInstalled: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
}
