import AppKit
import SwiftUI

/// A borderless floating panel that can still become the key window so the
/// text field receives keystrokes.
final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosting view that resizes its window to fit the SwiftUI content from within
/// the same `layout()` pass that lays the content out. Because the frame change
/// and the content update commit together, the window never lags the content by
/// a frame — which is what would otherwise flicker the rounded corners. The
/// window is anchored to a fixed top edge and grows/shrinks downward.
private final class AutoSizingHostingView<Content: View>: NSHostingView<Content> {
    var fixedWidth: CGFloat = 640
    /// Returns the screen-space top edge to pin to, or nil before positioning.
    var topEdge: (() -> CGFloat?)?
    private var isAdjusting = false

    override func layout() {
        super.layout()
        guard !isAdjusting, let window, let topEdgeY = topEdge?() else { return }
        let height = fittingSize.height
        guard height > 0 else { return }
        let newFrame = NSRect(
            x: window.frame.origin.x,
            y: topEdgeY - height,
            width: fixedWidth,
            height: height
        )
        guard newFrame != window.frame else { return }
        isAdjusting = true            // guard against the re-entrant layout setFrame triggers
        window.setFrame(newFrame, display: true)
        isAdjusting = false
    }
}

/// Manages the lifecycle of the search panel: showing it centered near the top
/// of the active screen, intercepting navigation keys, and hiding it.
@MainActor
final class SearchPanelController {
    private let model = SearchModel()
    private var panel: SearchPanel?
    private var hosting: AutoSizingHostingView<SearchView>?
    private var keyMonitor: Any?
    private var resignObserver: Any?
    private var launchWorkItem: DispatchWorkItem?

    /// How long we hold the panel open — swallowing keystrokes and showing the
    /// launch animation — before actually opening an auto-matched app. Prevents
    /// fast trailing keystrokes from leaking into the launched app.
    private let launchGrace: TimeInterval = 0.32

    private let panelWidth: CGFloat = 640
    /// Screen-space y of the panel's top edge. Fixed on open; the panel grows
    /// downward from here as results appear (origin is bottom-left in AppKit).
    private var topEdgeY: CGFloat = 0
    /// Becomes true once `positionPanel` has run, so the hosting view knows the
    /// top edge is valid and may start sizing.
    private var isPositioned = false

    init() {
        model.reload()
        // When the query narrows to a single app, launch it after a short grace
        // window (with a confirmation animation) rather than instantly.
        model.onSingleMatch = { [weak self] app in
            self?.beginLaunch(app)
        }
        // The panel keeps itself sized to its content via AutoSizingHostingView's
        // layout() pass — no separate observer needed, and resizing stays in sync
        // with the content (no flicker).
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
        installDeactivationObserver()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        cancelPendingLaunch()
        removeKeyMonitor()
        removeDeactivationObserver()
        panel?.orderOut(nil)
    }

    /// Immediate commit (explicit action via Return or click): launches the
    /// selected app or runs the selected calculator action, then closes.
    private func launchAndHide() {
        model.commitSelected()
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
        let hosting = AutoSizingHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        hosting.fixedWidth = panelWidth
        // The hosting view sizes the window to its content (top-anchored) within
        // its own layout pass, so the frame never lags the content by a frame.
        hosting.topEdge = { [weak self] in
            guard let self, self.isPositioned else { return nil }
            return self.topEdgeY
        }
        panel.contentView = hosting
        self.hosting = hosting
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        // Pin the top edge in the upper third; the panel grows downward.
        topEdgeY = visible.midY + visible.height * 0.30
        isPositioned = true

        var frame = panel.frame
        frame.origin.x = visible.midX - panelWidth / 2
        panel.setFrame(frame, display: false)

        // Trigger an immediate sizing pass now that the top edge is known.
        hosting?.needsLayout = true
        hosting?.layoutSubtreeIfNeeded()
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

    /// Closes the launcher as soon as the app loses focus — most notably when
    /// the user presses ⌘Tab to switch apps, but also when they click into
    /// another app. Mirrors how Spotlight dismisses itself.
    private func installDeactivationObserver() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeDeactivationObserver() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
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
