import Foundation
import PanelCore

// Read-only views over the scan result: merging, filtering, grouping, counts.
extension ServerStore {
    func isShownByDefault(_ entry: ServerEntry) -> Bool {
        rules.isShownByDefault(entry)
    }

    /// Same port, same folder: almost always one app listening on IPv4 and IPv6 from two processes,
    /// or a parent and its worker. Shown as one row; the others ride along for Stop.
    /// Keyed by the row's entry id, values include the row's own entry.
    var mergedByPort: [String: [ServerEntry]] {
        var buckets: [String: [ServerEntry]] = [:]
        for entry in entries.sorted(by: { $0.pid < $1.pid }) {
            let key = "\(entry.port)|\(entry.cwd ?? "?\(entry.pid)")"
            buckets[key, default: []].append(entry)
        }
        var merged: [String: [ServerEntry]] = [:]
        for group in buckets.values where group.count > 1 {
            merged[group[0].id] = group
        }
        return merged
    }

    /// Entries with port-and-folder duplicates collapsed onto their first process.
    var collapsedEntries: [ServerEntry] {
        let merged = mergedByPort
        let absorbed = Set(merged.values.flatMap { $0.dropFirst() }.map(\.id))
        return entries.filter { !absorbed.contains($0.id) }
    }

    /// Other processes folded into this row, if any.
    func siblings(of entry: ServerEntry) -> [ServerEntry] {
        Array(mergedByPort[entry.id]?.dropFirst() ?? [])
    }

    /// True when another project also listens on this port: a real conflict, not a merge.
    func hasPortConflict(_ entry: ServerEntry) -> Bool {
        collapsedEntries.contains { $0.port == entry.port && $0.id != entry.id && isShownByDefault($0) }
    }

    var visibleEntries: [ServerEntry] {
        let filtered = collapsedEntries.filter { entry in
            guard showAll || isShownByDefault(entry) else { return false }
            return ListLogic.matches(
                needle: filter, port: entry.port, projectName: entry.projectName,
                processName: entry.processName, branch: entry.branch)
        }
        return filtered.sorted { lhs, rhs in
            let leftPinned = rules.pinnedPorts.contains(lhs.port)
            let rightPinned = rules.pinnedPorts.contains(rhs.port)
            if leftPinned != rightPinned { return leftPinned }
            return lhs.port < rhs.port
        }
    }

    var highlightedID: String? { radarHover ?? rowHover ?? selectedID }

    /// Rows grouped by project when several servers share a working directory.
    var groupedEntries: [ListLogic.Group<ServerEntry>] {
        ListLogic.grouped(
            visibleEntries, key: { $0.cwd }, title: { $0.projectName }, port: { $0.port },
            pinned: { rules.pinnedPorts.contains($0.port) })
    }

    var badgeCount: Int {
        collapsedEntries.filter { isShownByDefault($0) }.count
    }

    var hiddenCount: Int {
        collapsedEntries.count - badgeCount
    }

    /// True once a stop signal has gone unanswered long enough to offer SIGKILL.
    func isStuck(_ entry: ServerEntry, now: Date = Date()) -> Bool {
        guard let since = stopping[entry.id] else { return false }
        return ListLogic.isStuck(signalledAt: since, now: now)
    }

    /// Uptime as of `now`, extrapolated from the last scan so it ticks between scans.
    func liveUptime(_ entry: ServerEntry, now: Date) -> TimeInterval? {
        entry.uptime.map { $0 + max(0, now.timeIntervalSince(lastScanDate)) }
    }
}
