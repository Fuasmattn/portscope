import AppKit

/// Editors and terminals that can open a project folder, and app icons for launcher labels.
@MainActor
enum Launchers {
    struct EditorApp: Identifiable {
        let id: String
        let name: String
        let url: URL
    }

    /// In menu order. Only installed ones are returned by `installedEditors`.
    static let editorCandidates: [(bundleID: String, name: String)] = [
        ("com.microsoft.VSCode", "VS Code"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("dev.zed.Zed", "Zed"),
        ("com.jetbrains.intellij", "IntelliJ IDEA"),
        ("com.jetbrains.WebStorm", "WebStorm"),
        ("com.sublimetext.4", "Sublime Text"),
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm"),
        ("dev.warp.Warp-Stable", "Warp"),
        ("com.mitchellh.ghostty", "Ghostty"),
    ]

    static let installedEditors: [EditorApp] = editorCandidates.compactMap { candidate in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) else { return nil }
        return EditorApp(id: candidate.bundleID, name: candidate.name, url: url)
    }

    /// Attribution labels that correspond to an app, for showing its icon in the row.
    private static let launcherBundleIDs: [String: String] = [
        "Claude": "com.anthropic.claudefordesktop",
        "Cursor": "com.todesktop.230313mzl4w4u92",
        "VS Code": "com.microsoft.VSCode",
        "Zed": "dev.zed.Zed",
        "Warp": "dev.warp.Warp-Stable",
        "Ghostty": "com.mitchellh.ghostty",
        "iTerm2": "com.googlecode.iterm2",
        "WezTerm": "com.github.wez.wezterm",
        "Terminal": "com.apple.Terminal",
    ]
    private static var iconCache: [String: NSImage?] = [:]

    /// The app icon for a launcher label, if that launcher is an installed app.
    static func icon(for launcher: String) -> NSImage? {
        if let cached = iconCache[launcher] { return cached }
        var icon: NSImage?
        if let bundleID = launcherBundleIDs[launcher],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        iconCache[launcher] = icon
        return icon
    }
}
