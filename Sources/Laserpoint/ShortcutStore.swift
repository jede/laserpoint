import Foundation

/// A user-configured prefix shortcut: a trigger key, a display name, and what to
/// do with the argument the user types after it.
struct ShortcutDefinition: Codable, Identifiable, Hashable {
    /// What committing the shortcut does with its argument.
    enum Action: Codable, Hashable {
        /// Smart browser behaviour: open the argument as a URL when it looks like
        /// one, otherwise run it as a web search — like a browser's omnibar.
        case webSearch
        /// Open a URL built from a template, substituting `{query}` with the
        /// URL-encoded argument (e.g. `claude://claude.ai/new?q={query}`).
        case urlTemplate(String)
    }

    var id: UUID
    var key: String
    var name: String
    var systemImage: String
    var action: Action

    init(id: UUID = UUID(), key: String, name: String, systemImage: String, action: Action) {
        self.id = id
        self.key = key
        self.name = name
        self.systemImage = systemImage
        self.action = action
    }

    /// The shortcuts shipped out of the box.
    static let defaults: [ShortcutDefinition] = [
        .init(key: "w", name: "Search the web", systemImage: "magnifyingglass", action: .webSearch),
        .init(key: "c", name: "Ask Claude", systemImage: "sparkles",
              action: .urlTemplate("claude://claude.ai/new?q={query}")),
    ]
}

/// Persists the user's shortcut definitions in `UserDefaults`. A single shared
/// instance backs both the launcher (which reads) and Settings (which edits), so
/// edits take effect the next time the launcher opens.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published var definitions: [ShortcutDefinition] {
        didSet { save() }
    }

    private let defaultsKey = "shortcutDefinitions"

    private init() {
        let stored = UserDefaults.standard.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode([ShortcutDefinition].self, from: $0) }
        definitions = stored ?? ShortcutDefinition.defaults
    }

    func addDefault() {
        definitions.append(
            .init(key: "", name: "New shortcut", systemImage: "link",
                  action: .urlTemplate("https://example.com/?q={query}"))
        )
    }

    func remove(_ definition: ShortcutDefinition) {
        definitions.removeAll { $0.id == definition.id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(definitions) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
