import AppKit
import Combine

/// Owns the launcher's state: the full app catalog, the current query, the
/// ranked results, and which result is selected.
@MainActor
final class SearchModel: ObservableObject {
    @Published var query: String = "" {
        didSet { recompute() }
    }
    @Published private(set) var results: [SearchResult] = []
    @Published var selection: Int = 0

    /// Non-nil while a launch is pending (during the grace window). Drives the
    /// "Launching…" confirmation animation in the view.
    @Published var launchingApp: AppEntry?

    /// Bumped on every open so the view can re-focus the search field — the
    /// field is removed from the hierarchy during the launch animation, so
    /// focus must be re-asserted rather than relying on a one-shot `onAppear`.
    @Published var focusRequest: Int = 0

    /// Fired when a non-empty query narrows to exactly one match, so the host
    /// can auto-launch it. The controller wires this to launch + close.
    var onSingleMatch: ((AppEntry) -> Void)?

    private var catalog: [AppEntry] = []
    private let usage = UsageStore()

    /// A query whose auto-launch the user cancelled (Esc). While the query stays
    /// equal to this, we won't auto-launch again; any change clears it.
    private var suppressedQuery: String?

    /// Clears the query and selection so the launcher opens in a fresh state.
    /// Setting `query` triggers `recompute()`, which also resets `selection`.
    func reset() {
        launchingApp = nil
        query = ""
        selection = 0
        focusRequest &+= 1
    }

    /// Rescan the disk for apps. Runs the file walk off the main thread.
    func reload() {
        Task.detached(priority: .userInitiated) {
            let apps = AppScanner.scan()
            await MainActor.run {
                self.catalog = apps
                self.recompute()
            }
        }
    }

    /// Suppresses auto-launch for the current query until it changes (Esc).
    func suppressAutoLaunch() {
        suppressedQuery = query.trimmingCharacters(in: .whitespaces)
    }

    private func recompute() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // Any change away from the cancelled query re-arms auto-launch.
        if suppressedQuery != trimmed { suppressedQuery = nil }

        let now = Date()

        // A prefix shortcut (e.g. `w …`, `c …`) leads the list when one matches.
        let shortcut = QueryShortcuts
            .result(for: trimmed, definitions: ShortcutStore.shared.definitions)
            .map { [SearchResult.shortcut($0)] } ?? []

        // Calculator actions lead the list whenever the query parses as math.
        let calc = Calculator.actions(for: trimmed).map(SearchResult.calc)

        let apps: [AppEntry]
        if trimmed.isEmpty {
            // No query: surface the most "frecent" apps first, then the rest
            // alphabetically — so common apps sit at the top of the list.
            apps = catalog.sorted { lhs, rhs in
                let fl = usage.frecency(for: lhs, now: now)
                let fr = usage.frecency(for: rhs, now: now)
                if fl != fr { return fl > fr }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } else {
            apps = catalog
                .compactMap { app -> (AppEntry, Int)? in
                    // Match against the display name and any aliases; keep the best.
                    guard let score = app.searchTerms
                        .compactMap({ FuzzyMatcher.score(query: trimmed, candidate: $0) })
                        .max()
                    else { return nil }
                    // Nudge frequently-used apps up, but cap the bonus so it
                    // can't float a weak match above a strong one.
                    let bonus = min(Int(usage.frecency(for: app, now: now)), 40)
                    return (app, score + bonus)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
                }
                .map(\.0)
        }

        results = shortcut + calc + apps.map(SearchResult.app)

        // Reset to the top whenever the query changes the result set.
        selection = 0

        // Auto-launch when the user has typed enough to leave exactly one app
        // match — but never when a shortcut/calculator row is present, nor when
        // the query is itself a valid expression (so "1" on the way to "1+1"
        // doesn't fire a single digit-matching app). Deferred to the next runloop
        // tick so we don't mutate UI while SwiftUI is still applying the edit.
        if !trimmed.isEmpty, shortcut.isEmpty, calc.isEmpty,
           !Calculator.isExpression(trimmed), results.count == 1,
           case .app(let only)? = results.first, suppressedQuery != trimmed {
            DispatchQueue.main.async { [weak self] in
                // Re-check: the user may have typed more (or cancelled) since.
                guard let self, self.results.count == 1,
                      case .app(let current)? = self.results.first, current == only,
                      self.suppressedQuery != self.query.trimmingCharacters(in: .whitespaces)
                else { return }
                self.onSingleMatch?(only)
            }
        }
    }

    // MARK: - Selection movement

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        selection = (selection + delta % count + count) % count
    }

    /// Selects a specific result (used by mouse clicks).
    func select(_ result: SearchResult) {
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            selection = index
        }
    }

    var selectedResult: SearchResult? {
        guard results.indices.contains(selection) else { return nil }
        return results[selection]
    }

    /// Commits the currently selected result. Returns true on success.
    @discardableResult
    func commitSelected() -> Bool {
        guard let result = selectedResult else { return false }
        commit(result)
        return true
    }

    /// Performs a result's action: open a shortcut, run a calculator action, or
    /// launch an app.
    func commit(_ result: SearchResult) {
        switch result {
        case .shortcut(let shortcut): NSWorkspace.shared.open(shortcut.url)
        case .calc(let calc):         perform(calc)
        case .app(let app):           launch(app)
        }
    }

    /// Launches a specific app and records the launch for frecency ranking.
    func launch(_ app: AppEntry) {
        usage.recordLaunch(app)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config)
    }

    private func perform(_ calc: CalcResult) {
        switch calc.kind {
        case .copyAnswer:       copyToPasteboard(calc.answer)
        case .copyExpression:   copyToPasteboard(calc.expression)
        case .openInCalculator: openCalculator(expression: calc.expression)
        }
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Opens the expression in a calculator via the `calc://` URL scheme (which a
    /// calculator app registers to prefill the expression). Falls back to plainly
    /// launching Calculator.app if nothing handles the scheme.
    private func openCalculator(expression: String) {
        // Strip whitespace so `calc://2 + 2` parses; percent-encode as a fallback
        // for any operator the URL initializer rejects.
        let compact = expression.replacingOccurrences(of: " ", with: "")
        let url = URL(string: "calc://\(compact)")
            ?? (compact.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed))
                .flatMap { URL(string: "calc://\($0)") }

        if let url, NSWorkspace.shared.open(url) { return }

        // No app handles calc:// — just open the system Calculator.
        if let calculator = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: "com.apple.calculator") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: calculator, configuration: config)
        }
    }
}
