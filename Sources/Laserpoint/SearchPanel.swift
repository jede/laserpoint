import AppKit
import Combine
import SwiftUI

/// A borderless floating panel that can still become the key window so the
/// text field receives keystrokes.
final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Manages the lifecycle of the search panel: showing it centered near the top
/// of the active screen, intercepting navigation keys, and hiding it.
@MainActor
final class SearchPanelController {
    private let model = SearchModel()
    private var panel: SearchPanel?
    private var keyMonitor: Any?
    private var resultsObserver: AnyCancellable?
    private var launchWorkItem: DispatchWorkItem?

    /// How long we hold the panel open — swallowing keystrokes and showing the
    /// launch animation — before actually opening an auto-matched app. Prevents
    /// fast trailing keystrokes from leaking into the launched app.
    private let launchGrace: TimeInterval = 0.32

    private let panelWidth: CGFloat = 640
    /// Screen-space y of the panel's top edge. Fixed on open; the panel grows
    /// downward from here as results appear (origin is bottom-left in AppKit).
    private var topEdgeY: CGFloat = 0

    init() {
        model.reload()
        // When the query narrows to a single app, launch it after a short grace
        // window (with a confirmation animation) rather than instantly.
        model.onSingleMatch = { [weak self] app in
            self?.beginLaunch(app)
        }
        // Keep the panel sized to its content as the result count changes.
        // (Launching is reflected inline without changing size, so it doesn't
        // trigger a resize — that avoids the panel jumping.)
        resultsObserver = model.$results
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeToFit() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Fresh state every time the launcher opens.
        cancelPendingLaunch()
        model.reset()
        model.reload()

        positionPanel(panel)
        installKeyMonitor()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        cancelPendingLaunch()
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    /// Immediate launch (explicit commit via Return or click).
    private func launchAndHide() {
        model.launchSelected()
        hide()
    }

    /// Begins the grace window for an auto-matched app: shows the launching
    /// animation, swallows keystrokes (see `handle`), then launches + closes.
    private func beginLaunch(_ app: AppEntry) {
        guard model.launchingApp == nil else { return }   // already launching
        model.launchingApp = app

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.launch(app)
            self.model.launchingApp = nil
            self.hide()
        }
        launchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + launchGrace, execute: work)
    }

    /// Aborts a pending grace-window launch, leaving the panel as-is.
    private func cancelPendingLaunch() {
        launchWorkItem?.cancel()
        launchWorkItem = nil
        model.launchingApp = nil
    }

    // MARK: - Panel construction

    private func makePanel() -> SearchPanel {
        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = SearchView(
            model: model,
            onLaunch: { [weak self] in self?.launchAndHide() },
            onDismiss: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        // Make `fittingSize` report SwiftUI's intrinsic layout so we can size
        // the window to it. Without this a ScrollView reports a flexible size.
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Pin the top edge in the upper third; the panel grows downward.
        topEdgeY = visible.midY + visible.height * 0.30

        var frame = panel.frame
        frame.origin.x = visible.midX - panelWidth / 2
        panel.setFrame(frame, display: false)

        resizeToFit()
    }

    /// Resizes the panel to fit its SwiftUI content, keeping the top edge fixed.
    private func resizeToFit() {
        guard let panel, let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height
        guard height > 0 else { return }
        let frame = NSRect(
            x: panel.frame.origin.x,
            y: topEdgeY - height,
            width: panelWidth,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: - Keyboard handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Returns true if the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        // During the launch grace window, swallow every key so trailing
        // keystrokes can't leak into the app being launched. Esc cancels the
        // launch and returns to the search field (without dismissing).
        if model.launchingApp != nil {
            if Int(event.keyCode) == 53 { // esc
                cancelPendingLaunch()
                model.suppressAutoLaunch()  // don't re-launch this same query
                model.focusRequest &+= 1    // re-focus the restored text field
            }
            return true
        }

        switch Int(event.keyCode) {
        case 53: // esc
            hide()
            return true
        case 126: // up arrow
            model.moveSelection(by: -1)
            return true
        case 125: // down arrow
            model.moveSelection(by: 1)
            return true
        case 36, 76: // return, keypad enter
            launchAndHide()
            return true
        default:
            return false
        }
    }
}
