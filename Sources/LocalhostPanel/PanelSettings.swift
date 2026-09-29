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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showMascot = defaults.object(forKey: "showMascot") as? Bool ?? true
        badgeStyle = BadgeStyle(rawValue: defaults.string(forKey: "badgeStyle") ?? "") ?? .count
        rowClickOpens = defaults.bool(forKey: "rowClickOpens")
        rememberPanelPosition = defaults.bool(forKey: "rememberPanelPosition")
        hotKey = defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) } ?? .default
        activeRefreshInterval = defaults.object(forKey: "activeRefreshInterval") as? Double ?? 2
    }
}
