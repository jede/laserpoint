import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private var panelController: SearchPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = SearchPanelController()
        panelController = controller

        // ⌥Space toggles the launcher.
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak controller] in
            controller?.toggle()
        }

        setupStatusItem()

        // Show once on launch so it's obvious the app is running.
        controller.show()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "scope",
            accessibilityDescription: "Laserpoint"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Open Laserpoint  (⌥Space)",
            action: #selector(openLauncher),
            keyEquivalent: ""
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

    @objc private func openLauncher() {
        panelController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
