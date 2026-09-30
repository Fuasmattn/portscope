import Foundation
import PortscopeCore

/// A server we stopped, remembered so it can be started again.
struct StoppedServer: Codable, Identifiable, Equatable {
    var id: String { "\(port):\(stoppedAt.timeIntervalSince1970)" }
    let port: Int
    let projectName: String
    let commandLine: String
    let cwd: String?
    let stoppedAt: Date
}

/// The last few servers stopped from the panel, newest first, persisted in UserDefaults.
@MainActor
final class StopHistory: ObservableObject {
    private let defaults: UserDefaults
    private let limit = 5

    @Published private(set) var entries: [StoppedServer] {
        didSet {
            if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: "recentlyStopped") }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: "recentlyStopped")
            .flatMap { try? JSONDecoder().decode([StoppedServer].self, from: $0) } ?? []
    }

    func remember(_ entry: ServerEntry) {
        let record = StoppedServer(
            port: entry.port, projectName: entry.projectName, commandLine: entry.commandLine,
            cwd: entry.cwd, stoppedAt: Date())
        entries.removeAll { $0.port == entry.port && $0.commandLine == entry.commandLine }
        entries.insert(record, at: 0)
        entries = Array(entries.prefix(limit))
    }

    func forget(_ stopped: StoppedServer) {
        entries.removeAll { $0.id == stopped.id }
    }
}
