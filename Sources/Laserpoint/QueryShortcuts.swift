import Foundation

/// A resolved prefix shortcut ready to show and open: the user typed a trigger
/// key, a space, then an argument (e.g. `w swift docs`, `c write a haiku`), and
/// this pairs that with the destination URL to open.
struct QueryShortcut: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let url: URL
}

/// Resolves a query against the user's configured shortcut definitions.
enum QueryShortcuts {
    /// Returns the shortcut for `query`, or nil when it isn't a `<key> <arg>`
    /// form whose key matches a definition.
    static func result(for query: String, definitions: [ShortcutDefinition]) -> QueryShortcut? {
        guard let spaceIndex = query.firstIndex(of: " ") else { return nil }
        let key = query[..<spaceIndex].lowercased()
        let argument = query[query.index(after: spaceIndex)...]
            .trimmingCharacters(in: .whitespaces)
        guard !argument.isEmpty else { return nil }

        guard let definition = definitions.first(where: {
            !$0.key.isEmpty && $0.key.lowercased() == key
        }) else { return nil }

        return resolve(definition, argument: argument)
    }

    private static func resolve(_ definition: ShortcutDefinition, argument: String) -> QueryShortcut? {
        switch definition.action {
        case .webSearch:
            return webSearch(definition, argument: argument)
        case .urlTemplate(let template):
            guard let url = url(from: template, argument: argument) else { return nil }
            return QueryShortcut(
                id: "shortcut.\(definition.id).\(argument)",
                title: "\(definition.name): \(argument)",
                subtitle: "Open \(url.host ?? "link")",
                systemImage: definition.systemImage,
                url: url
            )
        }
    }

    /// Smart browser behaviour: a URL-looking argument opens directly, anything
    /// else becomes a Google search.
    private static func webSearch(_ definition: ShortcutDefinition, argument: String) -> QueryShortcut {
        if isURL(argument) {
            let url = normalizedURL(argument)
            return QueryShortcut(
                id: "shortcut.\(definition.id).\(url.absoluteString)",
                title: "Open \(url.host ?? argument)",
                subtitle: definition.name,
                systemImage: "safari",
                url: url
            )
        }
        let url = URL(string: "https://www.google.com/search?q=\(encode(argument))")!
        return QueryShortcut(
            id: "shortcut.\(definition.id).\(argument)",
            title: "\(definition.name): \(argument)",
            subtitle: "Search the web",
            systemImage: definition.systemImage,
            url: url
        )
    }

    // MARK: - URL helpers

    /// Builds a URL from a template, replacing `{query}` with the encoded arg.
    private static func url(from template: String, argument: String) -> URL? {
        let filled = template.replacingOccurrences(of: "{query}", with: encode(argument))
        return URL(string: filled)
    }

    /// A cheap "did they mean a site?" test: no spaces and either an explicit
    /// http(s) scheme or a dotted host.
    private static func isURL(_ string: String) -> Bool {
        guard !string.contains(" ") else { return false }
        if string.hasPrefix("http://") || string.hasPrefix("https://") { return true }
        return string.contains(".")
    }

    private static func normalizedURL(_ string: String) -> URL {
        if string.hasPrefix("http://") || string.hasPrefix("https://"),
           let url = URL(string: string) {
            return url
        }
        return URL(string: "https://\(string)") ?? URL(string: "https://www.google.com")!
    }

    private static func encode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#/")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
