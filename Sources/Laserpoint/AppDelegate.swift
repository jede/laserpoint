import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: SearchPanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = SearchPanelController()
        panelController = controller

        // Global hotkey (default ⌥Space, user-rebindable in Settings).
        KeyboardShortcuts.onKeyDown(for: .toggleLauncher) { [weak controller] in
            controller?.toggle()
        }

        setupStatusItem()

        // Show once on launch so it's obvious the app is running.
        controller.show()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarImage()
            ?? NSImage(systemSymbolName: "scope", accessibilityDescription: "Laserpoint")

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Laserpoint",
            action: #selector(openLauncher),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Laserpoint",
            action: #selector(quit),
            keyEquivalent: "q"
        ).target = self

        item.menu = menu
        statusItem = item
    }

    /// The menu-bar glyph, rendered as a template image so macOS tints it for
    /// light/dark menu bars. Sized to the standard status-item height.
    private func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "menubar", withExtension: "svg"),
              let image = NSImage(contentsOf: url), image.size.height > 0 else { return nil }
        let height: CGFloat = 18
        image.size = NSSize(width: height * image.size.width / image.size.height, height: height)
        image.isTemplate = true
        return image
    }

    @objc private func openLauncher() {
        panelController?.show()
    }

    @objc private func openSettings() {
        // Hide the launcher panel so it doesn't sit above the settings window.
        panelController?.hide()

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Laserpoint Settings"
            let hosting = NSHostingView(rootView: SettingsView())
            window.contentView = hosting
            window.setContentSize(hosting.fittingSize)   // fit the SwiftUI content
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
