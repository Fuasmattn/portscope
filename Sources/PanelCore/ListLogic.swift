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
}
