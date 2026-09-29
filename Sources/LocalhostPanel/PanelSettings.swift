import Foundation

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

/// User preferences, persisted in UserDefaults. Owned by the store, observed through it.
@MainActor
final class PanelSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var showMascot: Bool { didSet { defaults.set(showMascot, forKey: "showMascot") } }
    @Published var badgeStyle: BadgeStyle { didSet { defaults.set(badgeStyle.rawValue, forKey: "badgeStyle") } }
    /// Single click on a row opens the browser instead of the details.
    @Published var rowClickOpens: Bool { didSet { defaults.set(rowClickOpens, forKey: "rowClickOpens") } }
    @Published var rememberPanelPosition: Bool { didSet { defaults.set(rememberPanelPosition, forKey: "rememberPanelPosition") } }
    @Published var hotKey: HotKeyBinding {
        didSet { if let data = try? JSONEncoder().encode(hotKey) { defaults.set(data, forKey: "hotKey") } }
    }
    /// Seconds between scans while a window is showing.
    @Published var activeRefreshInterval: Double { didSet { defaults.set(activeRefreshInterval, forKey: "activeRefreshInterval") } }
    /// Menu bar shows an orange mark when a server has run longer than this. 0 = off.
    @Published var staleHours: Int { didSet { defaults.set(staleHours, forKey: "staleHours") } }
    /// Include system noise and hidden servers in the list.
    @Published var showAll: Bool { didSet { defaults.set(showAll, forKey: "showAll") } }
    /// Path opened per port, e.g. "/docs" for 3000. Keyed by port as a string.
    @Published var openPaths: [String: String] { didSet { defaults.set(openPaths, forKey: "openPaths") } }

    func openPath(for port: Int) -> String {
        openPaths[String(port)] ?? "/"
    }

    func setOpenPath(_ path: String, for port: Int) {
        var cleaned = path.trimmingCharacters(in: .whitespaces)
        if !cleaned.hasPrefix("/") { cleaned = "/" + cleaned }
        if cleaned == "/" { openPaths[String(port)] = nil } else { openPaths[String(port)] = cleaned }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMascot = defaults.object(forKey: "showMascot") as? Bool ?? true
        badgeStyle = BadgeStyle(rawValue: defaults.string(forKey: "badgeStyle") ?? "") ?? .count
        rowClickOpens = defaults.bool(forKey: "rowClickOpens")
        rememberPanelPosition = defaults.bool(forKey: "rememberPanelPosition")
        hotKey = defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) } ?? .default
        activeRefreshInterval = defaults.object(forKey: "activeRefreshInterval") as? Double ?? 2
        staleHours = defaults.object(forKey: "staleHours") as? Int ?? 0
        showAll = defaults.bool(forKey: "showAll")
        openPaths = defaults.dictionary(forKey: "openPaths") as? [String: String] ?? [:]
    }
}
