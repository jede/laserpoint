import AppKit

/// Process entry point. Declared as `@main` (rather than top-level code in
/// `main.swift`) so the target compiles into an importable module and can be
/// `@testable import`ed by the test target.
@main
enum LaserpointMain {
    static func main() {
        // Top-level code runs on the main thread; assert main-actor isolation so
        // we can touch AppKit (which is @MainActor) without warnings.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate

            // Background/menu-bar app: no Dock icon, no main menu bar entry.
            app.setActivationPolicy(.accessory)

            app.run()
        }
    }
}
