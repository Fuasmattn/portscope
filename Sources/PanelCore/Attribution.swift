import Foundation

public struct Attribution: Equatable, Sendable {
    /// Best guess at what started this server, e.g. "Claude Code", "Cursor", "Terminal".
    public let launcher: String?
    /// Parent is launchd (PID 1): whatever started this has exited. Also true for
    /// legitimate launchd services, so this is a candidate flag, not proof of an orphan.
    public let isDetached: Bool
}

public enum AttributionResolver {
    /// Checked per ancestor, nearest first; the first ancestor that matches wins.
    private static let rules: [(label: String, matches: (ProcessRecord) -> Bool)] = [
        ("Claude Code", { record in
            let name = record.executableName.lowercased()
            let command = record.command.lowercased()
            return name == "claude" || command.contains("claude-code") || command.contains("/bin/claude")
        }),
        ("Claude", { $0.command.contains("Claude.app") }),
        ("Codex", { $0.executableName.lowercased() == "codex" }),
        ("Cursor", { $0.command.lowercased().contains("cursor") && $0.command.contains(".app/") }),
        ("VS Code", { record in
            let command = record.command.lowercased()
            return command.contains("visual studio code") || command.contains("code helper")
        }),
        ("Zed", { $0.command.contains("Zed.app") }),
        ("Conductor", { $0.command.contains("Conductor.app") }),
        ("herdr", { $0.executableName.lowercased() == "herdr" }),
        ("tmux", { $0.executableName.lowercased().hasPrefix("tmux") }),
        ("Warp", { $0.command.contains("Warp.app") }),
        ("Ghostty", { $0.command.contains("Ghostty.app") }),
        ("iTerm2", { $0.command.contains("iTerm") }),
        ("WezTerm", { $0.command.lowercased().contains("wezterm") }),
        ("Terminal", { $0.command.contains("Terminal.app") }),
    ]

    public static func resolve(pid: Int32, in table: ProcessTable) -> Attribution {
        guard let record = table.records[pid] else {
            return Attribution(launcher: nil, isDetached: false)
        }
        if record.ppid == 1 {
            return Attribution(launcher: nil, isDetached: true)
        }
        for ancestor in table.ancestors(of: pid) {
            for rule in rules where rule.matches(ancestor) {
                return Attribution(launcher: rule.label, isDetached: false)
            }
        }
        return Attribution(launcher: nil, isDetached: false)
    }
}
