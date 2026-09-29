import Foundation

/// Pure helpers behind the list UI, kept here so they can be unit tested.
public enum ListLogic {
    /// Type-to-filter match: port digits, project, process, or branch, case-insensitive.
    public static func matches(
        needle: String, port: Int, projectName: String, processName: String, branch: String?
    ) -> Bool {
        let needle = needle.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return String(port).contains(needle)
            || projectName.lowercased().contains(needle)
            || processName.lowercased().contains(needle)
            || (branch?.lowercased().contains(needle) ?? false)
    }

    /// A stop signal is "stuck" once it has gone unanswered longer than the threshold.
    public static func isStuck(signalledAt: Date, now: Date, threshold: TimeInterval = 4) -> Bool {
        now.timeIntervalSince(signalledAt) > threshold
    }

    /// Groups entries by project when two or more share a working directory. Singles get no group.
    /// Order: groups and singles interleaved by their lowest port, pinned first.
    public struct Group<Entry>: Identifiable {
        public let id: String
        public let title: String?
        public let entries: [Entry]
    }

    public static func grouped<Entry>(
        _ entries: [Entry], key: (Entry) -> String?, title: (Entry) -> String, port: (Entry) -> Int, pinned: (Entry) -> Bool
    ) -> [Group<Entry>] {
        var buckets: [String: [Entry]] = [:]
        var order: [String] = []
        for entry in entries {
            let bucketKey = key(entry) ?? "single:\(port(entry))"
            if buckets[bucketKey] == nil { order.append(bucketKey) }
            buckets[bucketKey, default: []].append(entry)
        }
        var groups: [Group<Entry>] = []
        for bucketKey in order {
            let members = buckets[bucketKey]!
            if members.count >= 2 {
                groups.append(Group(id: bucketKey, title: title(members[0]), entries: members))
            } else {
                for member in members {
                    groups.append(Group(id: "single:\(port(member))", title: nil, entries: [member]))
                }
            }
        }
        return groups.sorted { lhs, rhs in
            let leftPinned = lhs.entries.contains(where: pinned)
            let rightPinned = rhs.entries.contains(where: pinned)
            if leftPinned != rightPinned { return leftPinned }
            return (lhs.entries.map(port).min() ?? 0) < (rhs.entries.map(port).min() ?? 0)
        }
    }

    /// Result of folding same-port, same-folder processes onto one row.
    public struct PortMerge<Entry> {
        /// Entries with duplicates removed; the survivor of each group is the lowest PID.
        public let collapsed: [Entry]
        /// Absorbed entries, keyed by the id of the survivor they were folded into.
        public let siblings: [String: [Entry]]
    }

    /// Same port and same folder is almost always one app listening on IPv4 and IPv6 from two
    /// processes, or a parent and its worker. Entries without a folder never merge.
    public static func mergeByPort<Entry>(
        _ entries: [Entry], id: (Entry) -> String, port: (Entry) -> Int, folder: (Entry) -> String?, pid: (Entry) -> Int32
    ) -> PortMerge<Entry> {
        var buckets: [String: [Entry]] = [:]
        var order: [String] = []
        for entry in entries.sorted(by: { pid($0) < pid($1) }) {
            guard let folder = folder(entry) else { continue }
            let key = "\(port(entry))|\(folder)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        var siblings: [String: [Entry]] = [:]
        var absorbed: Set<String> = []
        for key in order {
            let group = buckets[key]!
            guard group.count > 1 else { continue }
            siblings[id(group[0])] = Array(group.dropFirst())
            for entry in group.dropFirst() { absorbed.insert(id(entry)) }
        }
        return PortMerge(collapsed: entries.filter { !absorbed.contains(id($0)) }, siblings: siblings)
    }

    /// True when another visible row also listens on this port: a real conflict, not a merge.
    public static func hasPortConflict<Entry>(
        _ entry: Entry, in collapsed: [Entry], id: (Entry) -> String, port: (Entry) -> Int, shown: (Entry) -> Bool
    ) -> Bool {
        collapsed.contains { port($0) == port(entry) && id($0) != id(entry) && shown($0) }
    }
}
