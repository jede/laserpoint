import Foundation

/// Discovers `.app` bundles in the directories we care about.
///
/// Targets `/Applications` and `/System/Applications` (each plus their
/// immediate subfolders, e.g. `Utilities`), which together hold both
/// user-installed apps and Apple's bundled ones like Safari & System Settings.
enum AppScanner {
    static let searchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true)
    ]

    /// Alternate names that should match an app, keyed by its display name.
    /// e.g. the old "System Preferences" name still finds "System Settings".
    static let aliases: [String: [String]] = [
        "System Settings": ["System Preferences"]
    ]

    /// Scans the search roots and returns a de-duplicated, name-sorted list.
    /// Safe to call off the main thread.
    static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var results: [AppEntry] = []

        for root in searchRoots {
            for url in appBundles(in: root, fileManager: fm) {
                let path = url.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let name = url.deletingPathExtension().lastPathComponent
                results.append(AppEntry(id: path, name: name, url: url, aliases: aliases[name] ?? []))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns `.app` bundles directly inside `root` and one level deep
    /// (to catch `/Applications/Utilities/*.app` and similar).
    private static func appBundles(in root: URL, fileManager fm: FileManager) -> [URL] {
        // Note: we do NOT pass `.skipsHiddenFiles`. Some real apps (notably
        // Safari) ship as hidden-flagged symlinks and would be dropped. Instead
        // we filter only dot-prefixed junk (.DS_Store, .localized, …) below.
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var apps: [URL] = []
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            if entry.pathExtension == "app" {
                apps.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                // One level down — but don't descend into app bundles themselves.
                if let nested = try? fm.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: nil,
                    options: []
                ) {
                    apps.append(contentsOf: nested.filter {
                        $0.pathExtension == "app" && !$0.lastPathComponent.hasPrefix(".")
                    })
                }
            }
        }
        return apps
    }
}
