import AppKit
import PanelCore
import SwiftUI

enum Reaction {
    case idle, alert, lost
}

enum BadgeStyle: String, CaseIterable, Identifiable {
    case count, dot, icon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .count: return "Icon and count"
        case .dot: return "Icon and dot"
        case .icon: return "Icon only"
        }
    }
}

/// A global hotkey as Carbon wants it, plus a label for the UI.
struct HotKeyBinding: Equatable, Codable {
    var keyCode: Int
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: Int

    static let `default` = HotKeyBinding(keyCode: 37, modifiers: 4096 | 2048) // ⌃⌥L

    var label: String {
        var text = ""
        if modifiers & 4096 != 0 { text += "⌃" }
        if modifiers & 2048 != 0 { text += "⌥" }
        if modifiers & 512 != 0 { text += "⇧" }
        if modifiers & 256 != 0 { text += "⌘" }
        return text + KeyNames.name(for: keyCode)
    }
}

/// A server we stopped, remembered so it can be started again.
struct StoppedServer: Codable, Identifiable, Equatable {
    var id: String { "\(port):\(stoppedAt.timeIntervalSince1970)" }
    let port: Int
    let projectName: String
    let commandLine: String
    let cwd: String?
    let stoppedAt: Date
}

@MainActor
final class ServerStore: ObservableObject {
    static let shared = ServerStore()

    @Published private(set) var entries: [ServerEntry] = []
    @Published private(set) var hasScanned = false
    @Published private(set) var pinnedPorts: Set<Int>
    @Published private(set) var hiddenPorts: Set<Int>
    /// Hidden by process name, because apps like Discord or Spotify get a new port every launch.
    @Published private(set) var hiddenProcesses: Set<String>
    @Published private(set) var reaction: Reaction = .idle
    @Published private(set) var lastArrival: ServerEntry?
    @Published private(set) var lastArrivalDate: Date?
    @Published private(set) var pingDate: Date?
    /// True while at least one of our windows is actually on screen.
    @Published private(set) var isActive = false
    /// Highlight link between radar blips and list rows.
    @Published var radarHover: String?
    @Published var rowHover: String?
    @Published var showMascot: Bool {
        didSet { UserDefaults.standard.set(showMascot, forKey: "showMascot") }
    }
    @Published var showAll = false
    @Published var message: String?
    /// When true the floating panel stays open after focus moves elsewhere.
    @Published var keepPanelOpen = false
    /// Servers we have signalled, keyed by entry id, with the time of the signal.
    /// Cleared when the server disappears from a scan.
    @Published private(set) var stopping: [String: Date] = [:]
    /// Servers that vanished recently, so the radar can fade their blips out.
    @Published private(set) var departed: [(entry: ServerEntry, at: Date)] = []
    /// Type-to-filter text for the list.
    @Published var filter = ""
    /// Bumped when the filter field should take keyboard focus (⌘F).
    @Published var filterFocusRequest = 0
    /// Keyboard selection in the list.
    @Published var selectedID: String?
    /// Row whose details popover is open.
    @Published var detailsID: String?
    /// When the last scan finished, so uptimes can tick between scans.
    @Published private(set) var lastScanDate = Date()
    /// Servers stopped from here, newest first, so they can be started again.
    @Published private(set) var recentlyStopped: [StoppedServer] {
        didSet {
            if let data = try? JSONEncoder().encode(recentlyStopped) {
                UserDefaults.standard.set(data, forKey: "recentlyStopped")
            }
        }
    }
    @Published var badgeStyle: BadgeStyle {
        didSet { UserDefaults.standard.set(badgeStyle.rawValue, forKey: "badgeStyle") }
    }
    /// Single click on a row opens the browser instead of the details.
    @Published var rowClickOpens: Bool {
        didSet { UserDefaults.standard.set(rowClickOpens, forKey: "rowClickOpens") }
    }
    @Published var rememberPanelPosition: Bool {
        didSet { UserDefaults.standard.set(rememberPanelPosition, forKey: "rememberPanelPosition") }
    }
    @Published var hotKey: HotKeyBinding {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) { UserDefaults.standard.set(data, forKey: "hotKey") }
        }
    }
    /// Seconds between scans while a window is showing.
    @Published var activeRefreshInterval: Double {
        didSet { UserDefaults.standard.set(activeRefreshInterval, forKey: "activeRefreshInterval") }
    }

    private let scanner = ServerScanner()
    private var loop: Task<Void, Never>?
    private var visibleWindows: Set<ObjectIdentifier> = []
    private var messageTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var knownIDs: Set<String> = []

    private init() {
        pinnedPorts = Set(UserDefaults.standard.array(forKey: "pinnedPorts") as? [Int] ?? [])
        hiddenPorts = Set(UserDefaults.standard.array(forKey: "hiddenPorts") as? [Int] ?? [])
        hiddenProcesses = Set(UserDefaults.standard.array(forKey: "hiddenProcesses") as? [String] ?? [])
        showMascot = UserDefaults.standard.object(forKey: "showMascot") as? Bool ?? true
        activeRefreshInterval = UserDefaults.standard.object(forKey: "activeRefreshInterval") as? Double ?? 2
        badgeStyle = BadgeStyle(rawValue: UserDefaults.standard.string(forKey: "badgeStyle") ?? "") ?? .count
        rememberPanelPosition = UserDefaults.standard.bool(forKey: "rememberPanelPosition")
        rowClickOpens = UserDefaults.standard.bool(forKey: "rowClickOpens")
        hotKey = UserDefaults.standard.data(forKey: "hotKey")
            .flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) } ?? .default
        recentlyStopped = UserDefaults.standard.data(forKey: "recentlyStopped")
            .flatMap { try? JSONDecoder().decode([StoppedServer].self, from: $0) } ?? []
    }

    // MARK: Derived state

    var visibleEntries: [ServerEntry] {
        let filtered = entries.filter { entry in
            guard showAll || isShownByDefault(entry) else { return false }
            return ListLogic.matches(
                needle: filter, port: entry.port, projectName: entry.projectName,
                processName: entry.processName, branch: entry.branch)
        }
        return filtered.sorted { lhs, rhs in
            let leftPinned = pinnedPorts.contains(lhs.port)
            let rightPinned = pinnedPorts.contains(rhs.port)
            if leftPinned != rightPinned { return leftPinned }
            return lhs.port < rhs.port
        }
    }

    var highlightedID: String? { radarHover ?? rowHover ?? selectedID }

    /// Rows grouped by project when several servers share a working directory.
    var groupedEntries: [ListLogic.Group<ServerEntry>] {
        ListLogic.grouped(
            visibleEntries, key: { $0.cwd }, title: { $0.projectName }, port: { $0.port },
            pinned: { pinnedPorts.contains($0.port) })
    }

    var badgeCount: Int {
        entries.filter { isShownByDefault($0) }.count
    }

    var hiddenCount: Int {
        entries.count - badgeCount
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

    /// Pinned always shows. Otherwise hidden if it looks like a system/app listener
    /// or you hid its port or its process name.
    func isShownByDefault(_ entry: ServerEntry) -> Bool {
        if pinnedPorts.contains(entry.port) { return true }
        return !entry.isSystemNoise
            && !hiddenPorts.contains(entry.port)
            && !hiddenProcesses.contains(entry.processName)
    }

    // MARK: Polling

    /// Poll fast while any window is showing, slowly (for the menu bar count) otherwise.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds: Double = (self?.isActive ?? false) ? (self?.activeRefreshInterval ?? 2) : 10
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func viewAppeared() {
        Task { await refresh() }
    }

    func owns(_ window: NSWindow) -> Bool {
        visibleWindows.contains(ObjectIdentifier(window))
    }

    func windowVisibilityChanged(_ window: NSWindow, visible: Bool) {
        let id = ObjectIdentifier(window)
        if visible { visibleWindows.insert(id) } else { visibleWindows.remove(id) }
        let active = !visibleWindows.isEmpty
        guard active != isActive else { return }
        isActive = active
        if active { Task { await refresh() } }
    }

    func refresh() async {
        let scanner = self.scanner
        let result = await Task.detached { await scanner.scan() }.value

        // React to servers that appeared since the last scan (not on the very first scan).
        let ids = Set(result.map(\.id))
        if hasScanned, let arrival = result.first(where: { !knownIDs.contains($0.id) && isShownByDefault($0) }) {
            lastArrival = arrival
            lastArrivalDate = Date()
            react(.alert, for: 1.8)
        }
        // Remember what vanished so the radar can fade it out, and drop finished stop attempts.
        let now = Date()
        let gone = entries.filter { !ids.contains($0.id) }
        departed = departed.filter { now.timeIntervalSince($0.at) < 1.5 } + gone.map { ($0, now) }
        for entry in gone { stopping[entry.id] = nil }
        knownIDs = ids

        withAnimation(.spring(duration: 0.35)) {
            entries = result
        }
        lastScanDate = now
        hasScanned = true
        if let selected = selectedID, !ids.contains(selected) { selectedID = nil }
        if let details = detailsID, !ids.contains(details) { detailsID = nil }
    }

    // MARK: Keyboard

    /// Handles a key press inside one of our windows. Returns true when consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125: moveSelection(by: 1); return true       // ↓
        case 126: moveSelection(by: -1); return true      // ↑
        case 36, 76:                                      // ⏎
            guard let entry = selectedEntry else { return false }
            if entry.speaksHTTP { open(entry) } else { toggleDetails(entry) }
            return true
        case 49:                                          // space
            guard let entry = selectedEntry else { return false }
            toggleDetails(entry)
            return true
        case 51, 117:                                     // ⌫ ⌦, with ⌘ to stop
            guard command, let entry = selectedEntry else { return false }
            terminate(entry, force: event.modifierFlags.contains(.option))
            return true
        case 3 where command:                             // ⌘F
            filterFocusRequest += 1
            return true
        case 53:                                          // Esc: details, filter, selection, then the window
            if detailsID != nil { detailsID = nil; return true }
            if !filter.isEmpty { filter = ""; return true }
            if selectedID != nil { selectedID = nil; return true }
            return false
        default:
            return false
        }
    }

    private var selectedEntry: ServerEntry? {
        entries.first { $0.id == selectedID }
    }

    private func moveSelection(by delta: Int) {
        let rows = groupedEntries.flatMap(\.entries)
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedID }
        let next = current.map { min(max($0 + delta, 0), rows.count - 1) } ?? (delta > 0 ? 0 : rows.count - 1)
        selectedID = rows[next].id
    }

    func toggleDetails(_ entry: ServerEntry) {
        detailsID = detailsID == entry.id ? nil : entry.id
    }

    // MARK: Actions

    func open(_ entry: ServerEntry) {
        guard let url = entry.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(_ entry: ServerEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(entry.port)", forType: .string)
        show("Copied http://localhost:\(entry.port)")
    }

    func revealWorkingDirectory(_ entry: ServerEntry) {
        guard let cwd = entry.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)])
    }

    /// Apps that can open a project folder, in menu order. Only installed ones are returned.
    struct EditorApp: Identifiable {
        let id: String
        let name: String
        let url: URL
    }

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

    lazy var installedEditors: [EditorApp] = Self.editorCandidates.compactMap { candidate in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) else { return nil }
        return EditorApp(id: candidate.bundleID, name: candidate.name, url: url)
    }

    func openWorkingDirectory(_ entry: ServerEntry, in editor: EditorApp) {
        guard let cwd = entry.cwd else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: editor.url, configuration: configuration) { _, error in
            if let error = error {
                Task { @MainActor in self.show("Could not open in \(editor.name): \(error.localizedDescription)") }
            }
        }
    }

    func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied \(label)")
    }

    // MARK: Launcher icons

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
    private var launcherIconCache: [String: NSImage?] = [:]

    /// The app icon for a launcher label, if that launcher is an installed app.
    func launcherIcon(for launcher: String) -> NSImage? {
        if let cached = launcherIconCache[launcher] { return cached }
        var icon: NSImage?
        if let bundleID = Self.launcherBundleIDs[launcher],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        launcherIconCache[launcher] = icon
        return icon
    }

    // MARK: Recently stopped

    private func remember(_ entry: ServerEntry) {
        let record = StoppedServer(
            port: entry.port, projectName: entry.projectName, commandLine: entry.commandLine,
            cwd: entry.cwd, stoppedAt: Date())
        recentlyStopped.removeAll { $0.port == entry.port && $0.commandLine == entry.commandLine }
        recentlyStopped.insert(record, at: 0)
        recentlyStopped = Array(recentlyStopped.prefix(5))
    }

    func forget(_ stopped: StoppedServer) {
        recentlyStopped.removeAll { $0.id == stopped.id }
    }

    /// Runs the saved command line again in its working directory, detached from this app.
    func startAgain(_ stopped: StoppedServer) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // A login shell so PATH matches the user's terminal; nohup + & so it outlives us.
        process.arguments = ["-lc", "nohup \(stopped.commandLine) >/dev/null 2>&1 &"]
        if let cwd = stopped.cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        do {
            try process.run()
            show("Starting \(stopped.projectName) on :\(stopped.port)…")
            forget(stopped)
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await refresh()
            }
        } catch {
            show("Could not start: \(error.localizedDescription)")
        }
    }

    func copyPort(_ entry: ServerEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(entry.port), forType: .string)
        show("Copied \(entry.port)")
    }

    func togglePin(_ entry: ServerEntry) {
        if pinnedPorts.contains(entry.port) { pinnedPorts.remove(entry.port) } else { pinnedPorts.insert(entry.port) }
        UserDefaults.standard.set(Array(pinnedPorts), forKey: "pinnedPorts")
    }

    func toggleHidden(_ entry: ServerEntry) {
        if hiddenPorts.contains(entry.port) { hiddenPorts.remove(entry.port) } else { hiddenPorts.insert(entry.port) }
        UserDefaults.standard.set(Array(hiddenPorts), forKey: "hiddenPorts")
    }

    func toggleHiddenProcess(_ entry: ServerEntry) {
        if hiddenProcesses.contains(entry.processName) {
            hiddenProcesses.remove(entry.processName)
        } else {
            hiddenProcesses.insert(entry.processName)
        }
        UserDefaults.standard.set(Array(hiddenProcesses), forKey: "hiddenProcesses")
    }

    /// Clicking the radar sends out a ping ring.
    func poke() {
        pingDate = Date()
    }

    private func react(_ newReaction: Reaction, for seconds: Double) {
        reaction = newReaction
        reactionTask?.cancel()
        reactionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.reaction = .idle }
        }
    }

    func terminate(_ entry: ServerEntry, force: Bool) {
        react(.lost, for: 1.2)
        Task {
            let pid = entry.pid
            let startTime = entry.startTime
            let result = await Task.detached {
                KillService.terminate(pid: pid, expectedStartTime: startTime, force: force)
            }.value

            switch result {
            case .signalled(let count):
                let extra = count > 1 ? " (+\(count - 1) child processes)" : ""
                show((force ? "Killed" : "Stopping") + " :\(entry.port)" + extra)
                if stopping[entry.id] == nil { stopping[entry.id] = Date() }
                remember(entry)
            case .notFound:
                show("Already stopped")
            case .pidReused:
                show("That process changed. Nothing was killed.")
            case .refused(let reason):
                show(reason)
            case .failed(let code):
                show("Could not signal process (errno \(code))")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
        }
    }

    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self?.message = nil }
        }
    }
}
