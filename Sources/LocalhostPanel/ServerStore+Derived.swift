import Foundation
import PanelCore

// Read-only views over the scan result: merging, filtering, grouping, counts.
extension ServerStore {
    func isShownByDefault(_ entry: ServerEntry) -> Bool {
        rules.isShownByDefault(entry)
    }

    /// Same port, same folder folded onto one row (see `ListLogic.mergeByPort`).
    var portMerge: ListLogic.PortMerge<ServerEntry> {
        ListLogic.mergeByPort(entries, id: \.id, port: \.port, folder: \.cwd, pid: \.pid)
    }

    /// Entries with port-and-folder duplicates collapsed onto their first process.
    var collapsedEntries: [ServerEntry] { portMerge.collapsed }

    /// Other processes folded into this row, if any.
    func siblings(of entry: ServerEntry) -> [ServerEntry] {
        portMerge.siblings[entry.id] ?? []
    }

    /// True when another project also listens on this port: a real conflict, not a merge.
    func hasPortConflict(_ entry: ServerEntry) -> Bool {
        ListLogic.hasPortConflict(entry, in: collapsedEntries, id: \.id, port: \.port, shown: isShownByDefault)
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
