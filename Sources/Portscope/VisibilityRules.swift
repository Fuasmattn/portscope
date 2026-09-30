import Foundation
import PortscopeCore

/// Which servers the list shows by default: pins always, hidden ports/processes/folders never,
/// system noise never. Persisted in UserDefaults.
@MainActor
final class VisibilityRules: ObservableObject {
    private let defaults: UserDefaults

    @Published private(set) var pinnedPorts: Set<Int>
    @Published private(set) var hiddenPorts: Set<Int>
    /// Hidden by process name, because apps like Discord or Spotify get a new port every launch.
    @Published private(set) var hiddenProcesses: Set<String>
    /// Hidden by working directory, for "never show this project".
    @Published private(set) var hiddenFolders: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinnedPorts = Set(defaults.array(forKey: "pinnedPorts") as? [Int] ?? [])
        hiddenPorts = Set(defaults.array(forKey: "hiddenPorts") as? [Int] ?? [])
        hiddenProcesses = Set(defaults.array(forKey: "hiddenProcesses") as? [String] ?? [])
        hiddenFolders = Set(defaults.array(forKey: "hiddenFolders") as? [String] ?? [])
    }

    func isShownByDefault(_ entry: ServerEntry) -> Bool {
        if pinnedPorts.contains(entry.port) { return true }
        return !entry.isSystemNoise
            && !hiddenPorts.contains(entry.port)
            && !hiddenProcesses.contains(entry.processName)
            && !(entry.cwd.map(hiddenFolders.contains) ?? false)
    }

    func togglePin(_ entry: ServerEntry) {
        toggle(&pinnedPorts, entry.port, key: "pinnedPorts")
    }

    func toggleHidden(_ entry: ServerEntry) {
        toggle(&hiddenPorts, entry.port, key: "hiddenPorts")
    }

    func toggleHiddenProcess(_ entry: ServerEntry) {
        toggle(&hiddenProcesses, entry.processName, key: "hiddenProcesses")
    }

    func toggleHiddenFolder(_ entry: ServerEntry) {
        guard let cwd = entry.cwd else { return }
        toggle(&hiddenFolders, cwd, key: "hiddenFolders")
    }

    /// Count of hide rules (pins are not rules you would want to reset).
    var hiddenRuleCount: Int { hiddenPorts.count + hiddenProcesses.count + hiddenFolders.count }

    func resetHidden() {
        hiddenPorts = []
        hiddenProcesses = []
        hiddenFolders = []
        for key in ["hiddenPorts", "hiddenProcesses", "hiddenFolders"] { defaults.removeObject(forKey: key) }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T, key: String) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        defaults.set(Array(set), forKey: key)
    }
}
