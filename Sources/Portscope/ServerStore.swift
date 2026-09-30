import AppKit
import Combine
import PortscopeCore
import SwiftUI

enum Reaction {
    case idle, alert, lost
}

/// The scan result and the live state around it: polling, arrivals and departures, stop attempts,
/// selection, hover, and the panel's transient message. Preferences, visibility rules, and stop
/// history live in their own objects; changes to them are forwarded so views observing the store
/// refresh.
@MainActor
final class ServerStore: ObservableObject {
    static let shared = ServerStore()

    let settings = PanelSettings()
    let rules = VisibilityRules()
    let history = StopHistory()

    @Published private(set) var entries: [ServerEntry] = []
    @Published private(set) var hasScanned = false
    /// When the last scan finished, so uptimes can tick between scans.
    @Published private(set) var lastScanDate = Date()
    /// True while at least one of our windows is actually on screen.
    @Published private(set) var isActive = false

    @Published private(set) var reaction: Reaction = .idle
    @Published private(set) var lastArrival: ServerEntry?
    @Published private(set) var lastArrivalDate: Date?
    @Published var pingDate: Date?
    /// Servers that vanished recently, so the radar can fade their blips out.
    @Published private(set) var departed: [(entry: ServerEntry, at: Date)] = []
    /// Servers we have signalled, keyed by entry id, with the time of the signal.
    /// Cleared when the server disappears from a scan.
    @Published var stopping: [String: Date] = [:]

    /// Highlight link between radar blips and list rows.
    @Published var radarHover: String?
    @Published var rowHover: String?
    /// Keyboard selection in the list.
    @Published var selectedID: String?
    /// Row whose details popover is open.
    @Published var detailsID: String?
    /// Type-to-filter text for the list.
    @Published var filter = ""
    /// Bumped when the filter field should take keyboard focus (⌘F).
    @Published var filterFocusRequest = 0
    @Published var message: String?
    /// When true the floating panel stays open after focus moves elsewhere.
    @Published var keepPanelOpen = false

    private let scanner = ServerScanner()
    private var loop: Task<Void, Never>?
    private var visibleWindows: Set<ObjectIdentifier> = []
    private var messageTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var knownIDs: Set<String> = []
    private var forwarding: Set<AnyCancellable> = []

    private init() {
        for child in [settings.objectWillChange.eraseToAnyPublisher(),
                      rules.objectWillChange.eraseToAnyPublisher(),
                      history.objectWillChange.eraseToAnyPublisher()] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &forwarding)
        }
    }

    // MARK: Polling

    /// Poll fast while any window is showing, slowly (for the menu bar count) otherwise.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds: Double = (self?.isActive ?? false) ? (self?.settings.activeRefreshInterval ?? 2) : 10
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

    // MARK: Feedback

    func react(_ newReaction: Reaction, for seconds: Double) {
        reaction = newReaction
        reactionTask?.cancel()
        reactionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.reaction = .idle }
        }
    }

    /// Shows a line in the footer for a few seconds.
    func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self?.message = nil }
        }
    }
}
