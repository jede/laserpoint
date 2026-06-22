import AppKit

/// A single launchable application discovered on disk.
struct AppEntry: Identifiable, Hashable {
    let id: String          // bundle path, stable & unique
    let name: String        // display name (no ".app")
    let url: URL
    var aliases: [String] = []   // alternate names that should also match

    /// All strings a query may match against: the display name plus any aliases.
    var searchTerms: [String] { [name] + aliases }

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The app's icon. Fetched lazily via the shared workspace.
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
