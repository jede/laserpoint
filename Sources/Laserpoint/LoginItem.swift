import ServiceManagement

/// Wraps "launch at login" via `SMAppService.mainApp` (macOS 13+). The app
/// registers itself — no separate helper bundle required. The choice persists
/// across launches (the system remembers the login-item registration).
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Laserpoint: failed to update login item: \(error.localizedDescription)")
        }
    }
}
