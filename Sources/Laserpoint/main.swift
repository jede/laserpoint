import AppKit

// Top-level code runs on the main thread; assert main-actor isolation so we can
// touch AppKit (which is @MainActor) without warnings.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // Background/menu-bar app: no Dock icon, no main menu bar entry of its own.
    app.setActivationPolicy(.accessory)

    app.run()
}
