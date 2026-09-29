import Foundation

public struct ProcessRecord: Equatable, Sendable {
    public let pid: Int32
    public let ppid: Int32
    public let uid: UInt32
    /// `ps lstart` normalized to single spaces, e.g. "Tue Sep 29 13:22:38 2026".
    /// Together with the PID this identifies a process instance; used to detect PID reuse.
    public let startTime: String
    public let startDate: Date?
    /// Full command line as printed by `ps`.
    public let command: String

    public init(pid: Int32, ppid: Int32, uid: UInt32, startTime: String, startDate: Date?, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.startTime = startTime
        self.startDate = startDate
        self.command = command
    }

    /// A short readable name: the .app name for app bundles, otherwise the executable's basename.
    public var executableName: String {
        if let range = command.range(of: ".app/") {
            let prefix = command[..<range.lowerBound]
            if let slash = prefix.lastIndex(of: "/") {
                return String(prefix[prefix.index(after: slash)...])
            }
        }
        let firstToken = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        return (firstToken as NSString).lastPathComponent
    }
}

public struct ProcessTable: Sendable {
    public let records: [Int32: ProcessRecord]

    public init(records: [ProcessRecord]) {
        var map: [Int32: ProcessRecord] = [:]
        for record in records { map[record.pid] = record }
        self.records = map
    }

    public static let psArguments = ["-axo", "pid=,ppid=,uid=,lstart=,command="]

    public static func snapshot() -> ProcessTable {
        let output = ProcessRunner.run("/bin/ps", psArguments) ?? ""
        return ProcessTable(records: parse(output))
    }

    public static func parse(_ output: String) -> [ProcessRecord] {
        output.split(whereSeparator: \.isNewline).compactMap { parseLine($0) }
    }

    /// One line: `pid ppid uid <5 lstart tokens> command...`
    static func parseLine(_ line: Substring) -> ProcessRecord? {
        guard let (tokens, rest) = takeTokens(line, count: 8) else { return nil }
        guard let pid = Int32(tokens[0]), let ppid = Int32(tokens[1]), let uid = UInt32(tokens[2]) else {
            return nil
        }
        let startTime = tokens[3...7].joined(separator: " ")
        return ProcessRecord(
            pid: pid, ppid: ppid, uid: uid,
            startTime: startTime,
            startDate: startDateFormatter.date(from: tokens[4...7].joined(separator: " ")),
            command: String(rest))
    }

    /// Splits off `count` whitespace-delimited tokens, returning them and the untouched remainder.
    static func takeTokens(_ line: Substring, count: Int) -> ([String], Substring)? {
        var tokens: [String] = []
        var index = line.startIndex
        while tokens.count < count {
            while index < line.endIndex, line[index] == " " || line[index] == "\t" {
                index = line.index(after: index)
            }
            guard index < line.endIndex else { return nil }
            let start = index
            while index < line.endIndex, line[index] != " ", line[index] != "\t" {
                index = line.index(after: index)
            }
            tokens.append(String(line[start..<index]))
        }
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        return (tokens, line[index...])
    }

    private static let startDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy"
        return formatter
    }()

    /// Ancestors of `pid`, nearest first, stopping at PID 1, a missing parent, or a cycle.
    public func ancestors(of pid: Int32) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var seen: Set<Int32> = [pid]
        var current = records[pid]?.ppid ?? 0
        while current > 1, !seen.contains(current), let record = records[current], result.count < 40 {
            result.append(record)
            seen.insert(current)
            current = record.ppid
        }
        return result
    }

    /// All descendants of `pid` (children, grandchildren, ...).
    public func descendants(of pid: Int32) -> [ProcessRecord] {
        var children: [Int32: [ProcessRecord]] = [:]
        for record in records.values { children[record.ppid, default: []].append(record) }
        var result: [ProcessRecord] = []
        var queue: [Int32] = [pid]
        var seen: Set<Int32> = [pid]
        while let next = queue.popLast() {
            for child in children[next] ?? [] where !seen.contains(child.pid) {
                seen.insert(child.pid)
                result.append(child)
                queue.append(child.pid)
            }
        }
        return result
    }
}
