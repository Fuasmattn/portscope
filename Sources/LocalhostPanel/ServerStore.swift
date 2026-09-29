import AppKit
import PanelCore
import SwiftUI

enum Reaction {
    case idle, alert, lost
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
    }

    // MARK: Derived state

    var visibleEntries: [ServerEntry] {
        let filtered = entries.filter { showAll || isShownByDefault($0) }
        return filtered.sorted { lhs, rhs in
            let leftPinned = pinnedPorts.contains(lhs.port)
            let rightPinned = pinnedPorts.contains(rhs.port)
            if leftPinned != rightPinned { return leftPinned }
            return lhs.port < rhs.port
        }
    }

    var highlightedID: String? { radarHover ?? rowHover }

    var badgeCount: Int {
        entries.filter { isShownByDefault($0) }.count
    }

    var hiddenCount: Int {
        entries.count - badgeCount
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
                let seconds: Double = (self?.isActive ?? false) ? 2 : 10
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func viewAppeared() {
        Task { await refresh() }
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
        knownIDs = ids

        withAnimation(.spring(duration: 0.35)) {
            entries = result
        }
        hasScanned = true
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
                show((force ? "Killed" : "Stopped") + " :\(entry.port)" + extra)
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
