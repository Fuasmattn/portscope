import AppKit
import PanelCore

// List navigation from the keyboard, dispatched by the app's local event monitor.
extension ServerStore {
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
}
