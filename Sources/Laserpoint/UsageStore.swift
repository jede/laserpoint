import Foundation

/// Per-app launch history used to rank frequently/recently used apps higher —
/// an "autojump"/frecency-style signal. Persisted as JSON in Application Support
/// so it survives relaunches.
@MainActor
final class UsageStore {
    private struct Record: Codable {
        var count: Int
        var lastUsed: Date
    }

    private var records: [String: Record] = [:]   // keyed by AppEntry.id (bundle path)
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Laserpoint", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("usage.json")
        load()
    }

    /// Record that `app` was launched now.
    func recordLaunch(_ app: AppEntry, now: Date = Date()) {
        var record = records[app.id] ?? Record(count: 0, lastUsed: now)
        record.count += 1
        record.lastUsed = now
        records[app.id] = record
        save()
    }

    /// Frecency: launch count weighted by how recently the app was used, in the
    /// spirit of autojump's "frecent" ranking. Returns 0 for never-used apps.
    func frecency(for app: AppEntry, now: Date = Date()) -> Double {
        guard let record = records[app.id] else { return 0 }
        let age = now.timeIntervalSince(record.lastUsed)
        let recencyWeight: Double
        switch age {
        case ..<3_600:    recencyWeight = 4    // within the last hour
        case ..<86_400:   recencyWeight = 2    // within the last day
        case ..<604_800:  recencyWeight = 1    // within the last week
        default:          recencyWeight = 0.5  // older
        }
        return Double(record.count) * recencyWeight
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
