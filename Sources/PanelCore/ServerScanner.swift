import Foundation

public struct ServerEntry: Identifiable, Equatable, Sendable {
    public var id: String { "\(pid):\(port)" }
    public let pid: Int32
    public let port: Int
    public let host: String
    public let loopbackOnly: Bool
    /// Short process name, e.g. "node".
    public let processName: String
    public let commandLine: String
    public let cwd: String?
    public let projectName: String
    public let branch: String?
    public let uptime: TimeInterval?
    /// Identity token for PID-reuse-safe kills.
    public let startTime: String
    public let launcher: String?
    public let isDetached: Bool
    public let speaksHTTP: Bool
    /// System listeners that are almost never what you are looking for.
    public let isSystemNoise: Bool

    public var url: URL? { URL(string: "http://localhost:\(port)") }
}

public enum NoiseFilter {
    // OS daemons; macOS listens on 5000/7000 for AirPlay Receiver (ControlCenter).
    private static let names: Set<String> = [
        "controlcenter", "rapportd", "sharingd", "identityservicesd", "wifiagent",
        "airportd", "remoted", "screensharingd", "apsd",
    ]

    /// True for listeners that are almost certainly not dev servers: OS daemons and
    /// desktop apps (Discord, Spotify, ...). A process whose working directory is inside
    /// your home folder (outside ~/Library) is treated as dev work even if it is an app
    /// bundle, so an Electron app you run from a project stays visible.
    public static func isSystemNoise(
        processName: String,
        commandLine: String,
        cwd: String?,
        home: String = NSHomeDirectory()
    ) -> Bool {
        if names.contains(processName.lowercased()) { return true }
        if let cwd = cwd, cwd.hasPrefix(home + "/"), !cwd.hasPrefix(home + "/Library/") {
            return false
        }
        if cwd == "/" { return true }
        return commandLine.contains(".app/Contents/")
            || commandLine.hasPrefix("/System/")
            || commandLine.hasPrefix("/usr/libexec/")
            || commandLine.hasPrefix("/usr/sbin/")
    }
}

public struct ServerScanner: Sendable {
    public init() {}

    public func scan() async -> [ServerEntry] {
        let uid = getuid()
        let listenOutput = ProcessRunner.run("/usr/sbin/lsof", LsofParser.listenerArguments) ?? ""
        let sockets = LsofParser.parseListeners(listenOutput).filter { $0.uid == uid }
        guard !sockets.isEmpty else { return [] }

        // One entry per (pid, port); IPv4 and IPv6 listeners for the same port merge.
        var merged: [String: (socket: ListeningSocket, loopbackOnly: Bool)] = [:]
        for socket in sockets {
            let key = "\(socket.pid):\(socket.port)"
            if let existing = merged[key] {
                merged[key] = (existing.socket, existing.loopbackOnly && socket.isLoopbackOnly)
            } else {
                merged[key] = (socket, socket.isLoopbackOnly)
            }
        }

        let table = ProcessTable.snapshot()
        let pids = Set(merged.values.map { $0.socket.pid }).sorted()
        let cwdOutput = ProcessRunner.run(
            "/usr/sbin/lsof",
            ["-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","), "-F", "pn"]) ?? ""
        let cwds = LsofParser.parseWorkingDirectories(cwdOutput)

        let probes = await withTaskGroup(of: (String, Bool).self) { group -> [String: Bool] in
            for (key, value) in merged {
                let host = value.socket.host
                let port = value.socket.port
                group.addTask {
                    let ok = await HTTPProbe.speaksHTTP(host: host, port: port)
                    return (key, ok)
                }
            }
            var results: [String: Bool] = [:]
            for await (key, ok) in group { results[key] = ok }
            return results
        }

        let now = Date()
        var entries: [ServerEntry] = []
        for (key, value) in merged {
            let socket = value.socket
            guard let record = table.records[socket.pid] else { continue }
            let cwd = cwds[socket.pid]
            let project = cwd.map { ProjectDetector.detect(cwd: $0) }
            let attribution = AttributionResolver.resolve(pid: socket.pid, in: table)
            let name = record.executableName.isEmpty ? socket.command : record.executableName

            entries.append(ServerEntry(
                pid: socket.pid,
                port: socket.port,
                host: socket.host,
                loopbackOnly: value.loopbackOnly,
                processName: name,
                commandLine: record.command,
                cwd: cwd,
                projectName: project?.name ?? name,
                branch: project?.branch,
                uptime: record.startDate.map { now.timeIntervalSince($0) },
                startTime: record.startTime,
                launcher: attribution.launcher,
                isDetached: attribution.isDetached,
                speaksHTTP: probes[key] ?? false,
                isSystemNoise: NoiseFilter.isSystemNoise(
                    processName: name, commandLine: record.command, cwd: cwd)))
        }
        return entries.sorted { $0.port < $1.port }
    }
}
