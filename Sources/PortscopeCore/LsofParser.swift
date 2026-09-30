import Foundation

public struct ListeningSocket: Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let uid: UInt32
    public let host: String
    public let port: Int

    public init(pid: Int32, command: String, uid: UInt32, host: String, port: Int) {
        self.pid = pid
        self.command = command
        self.uid = uid
        self.host = host
        self.port = port
    }

    public var isLoopbackOnly: Bool {
        host == "127.0.0.1" || host == "::1" || host == "localhost"
    }
}

public enum LsofParser {
    /// Arguments that produce the output `parseListeners` expects.
    /// `+c 0` asks for full command names instead of 9-character truncation.
    public static let listenerArguments = ["-nP", "+c", "0", "-iTCP", "-sTCP:LISTEN", "-F", "pcun"]

    /// Parses `lsof -F pcun` output: `p<pid>`, `c<command>`, `u<uid>`, `n<name>` lines.
    public static func parseListeners(_ output: String) -> [ListeningSocket] {
        var results: [ListeningSocket] = []
        var pid: Int32?
        var command = ""
        var uid: UInt32 = 0

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
                uid = 0
            case "c":
                command = decodeEscapes(value)
            case "u":
                uid = UInt32(value) ?? 0
            case "n":
                guard let pid = pid, let hostPort = splitHostPort(value) else { continue }
                results.append(ListeningSocket(
                    pid: pid, command: command, uid: uid,
                    host: hostPort.host, port: hostPort.port))
            default:
                break
            }
        }
        return results
    }

    /// Parses `lsof -a -d cwd -p ... -F pn` output into pid -> working directory.
    public static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            if tag == "p" {
                pid = Int32(value)
            } else if tag == "n", let pid = pid {
                result[pid] = value
            }
        }
        return result
    }

    /// "*:3000", "127.0.0.1:3000", "[::1]:3000" -> (host, port)
    static func splitHostPort(_ name: String) -> (host: String, port: Int)? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        let portText = name[name.index(after: colon)...]
        guard let port = Int(portText) else { return nil }
        var host = String(name[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return (host, port)
    }

    /// lsof escapes some bytes in command names as `\xNN`; only spaces matter in practice.
    static func decodeEscapes(_ text: String) -> String {
        text.replacingOccurrences(of: "\\x20", with: " ")
    }
}
