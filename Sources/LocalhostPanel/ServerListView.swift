import AppKit
import PanelCore
import SwiftUI

private let rowHeight: CGFloat = 58
private let maxListHeight: CGFloat = 420
/// Above this many rows a search field appears.
private let searchThreshold = 8

struct ServerListView: View {
    @ObservedObject var store: ServerStore
    var isPanel = false
    @State private var pointer: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .coordinateSpace(.named("panel"))
        .onContinuousHover(coordinateSpace: .named("panel")) { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
        .background(WindowVisibilityProbe { window, visible in
            store.windowVisibilityChanged(window, visible: visible)
        })
        .onAppear { store.viewAppeared() }
    }

    private var header: some View {
        WatcherHeader(store: store, pointer: pointer, isPanel: isPanel)
    }

    private var showsSearch: Bool {
        store.entries.filter { store.showAll || store.isShownByDefault($0) }.count > searchThreshold
            || !store.filter.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        let rows = store.visibleEntries
        if !store.hasScanned {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            if showsSearch {
                searchField
            }
            if rows.isEmpty {
                Text(store.filter.isEmpty ? "No servers listening" : "No match for “\(store.filter)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { entry in
                            ServerRow(entry: entry, store: store)
                                .frame(height: rowHeight)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .frame(height: min(CGFloat(rows.count) * (rowHeight + 1), maxListHeight))
                .animation(.spring(duration: 0.35), value: rows.map(\.id))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Filter by port, project, or branch", text: $store.filter)
                .textFieldStyle(.plain)
                .font(.callout)
            if !store.filter.isEmpty {
                Button { store.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(IconButtonStyle())
                    .help("Clear filter")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private var footer: some View {
        HStack {
            if let message = store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if store.hiddenCount > 0 || store.showAll {
                Toggle(isOn: $store.showAll) {
                    Text(store.showAll ? "Showing all" : "\(store.hiddenCount) hidden")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            Spacer()
            if isPanel {
                Button {
                    store.keepPanelOpen.toggle()
                } label: {
                    Image(systemName: store.keepPanelOpen ? "pin.fill" : "pin")
                }
                .buttonStyle(IconButtonStyle(active: store.keepPanelOpen))
                .help(store.keepPanelOpen ? "Panel stays open" : "Keep panel open")
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                // Accessory apps are not active, so the window would open behind everything.
                NSApplication.shared.activate(ignoringOtherApps: true)
            })
            .help("Settings")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ServerRow: View {
    let entry: ServerEntry
    @ObservedObject var store: ServerStore
    @State private var confirmingKill = false

    private var hovered: Bool { store.highlightedID == entry.id }
    private var isStopping: Bool { store.stopping[entry.id] != nil }

    var body: some View {
        HStack(spacing: 10) {
            Text(":\(String(entry.port))")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if store.pinnedPorts.contains(entry.port) {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.projectName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.isDetached {
                        Text("detached")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if !entry.loopbackOnly {
                        Image(systemName: "network")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Listening on all interfaces, reachable from your network")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            trailing
        }
        .padding(.horizontal, 12)
        .background(hovered ? Color.accentColor.opacity(0.12) : Color.clear)
        .onHover { inside in
            if inside {
                store.rowHover = entry.id
            } else if store.rowHover == entry.id {
                store.rowHover = nil
                confirmingKill = false
            }
        }
        .opacity(isStopping ? 0.55 : (store.isShownByDefault(entry) ? 1 : 0.5))
        .contentShape(Rectangle())
        .contextMenu { menu }
    }

    @ViewBuilder
    private var trailing: some View {
        if isStopping {
            // Re-evaluates once a second so the force-kill offer shows up when the process ignores SIGTERM.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                if store.isStuck(entry, now: timeline.date) {
                    Button("Force kill") { store.terminate(entry, force: true) }
                        .buttonStyle(PillButtonStyle(role: .destructive))
                        .help("Process ignored SIGTERM. Send SIGKILL")
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("stopping…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if confirmingKill {
            Button("Cancel") { confirmingKill = false }
                .buttonStyle(PillButtonStyle(role: .neutral))
            Button("Stop") {
                // Option-click sends SIGKILL instead of SIGTERM.
                let force = NSEvent.modifierFlags.contains(.option)
                confirmingKill = false
                store.terminate(entry, force: force)
            }
            .buttonStyle(PillButtonStyle(role: .destructive))
            .help("Option-click to force kill")
        } else {
            HStack(spacing: 2) {
                if entry.speaksHTTP {
                    Button { store.open(entry) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(IconButtonStyle())
                        .help("Open in browser")
                }
                Button { confirmingKill = true } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(IconButtonStyle())
                    .help("Stop process")
            }
            .opacity(hovered ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if entry.speaksHTTP {
            Button("Open in browser") { store.open(entry) }
        }
        Button("Copy URL") { store.copyURL(entry) }
        Button("Copy port") { store.copyPort(entry) }
        if entry.cwd != nil {
            Divider()
            let editors = store.installedEditors
            if !editors.isEmpty {
                Menu("Open project in") {
                    ForEach(editors) { editor in
                        Button(editor.name) { store.openWorkingDirectory(entry, in: editor) }
                    }
                }
            }
            Button("Reveal working directory") { store.revealWorkingDirectory(entry) }
        }
        Divider()
        Button(store.pinnedPorts.contains(entry.port) ? "Unpin" : "Pin (always show)") { store.togglePin(entry) }
        Button(store.hiddenProcesses.contains(entry.processName)
               ? "Unhide all \(entry.processName)" : "Hide all \(entry.processName)") {
            store.toggleHiddenProcess(entry)
        }
        Button(store.hiddenPorts.contains(entry.port) ? "Unhide port \(String(entry.port))" : "Hide port \(String(entry.port))") {
            store.toggleHidden(entry)
        }
        Divider()
        Button("Stop (SIGTERM)") { store.terminate(entry, force: false) }
        Button("Force kill (SIGKILL)") { store.terminate(entry, force: true) }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let branch = entry.branch { parts.append(branch) }
        parts.append(entry.processName)
        if let uptime = entry.uptime { parts.append(Formatting.uptime(uptime)) }
        if let launcher = entry.launcher { parts.append("via \(launcher)") }
        return parts.joined(separator: " · ")
    }
}

/// Title, count, and running commentary over the radar scope, on a glass card.
struct WatcherHeader: View {
    @ObservedObject var store: ServerStore
    let pointer: CGPoint?
    let isPanel: Bool
    @State private var quipSeed = Int.random(in: 0..<100)

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Localhost")
                        .font(.headline)
                        .foregroundStyle(store.showMascot ? Color.white : Color.primary)
                    Text("\(store.badgeCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(store.showMascot ? Color.white.opacity(0.65) : Color.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: store.badgeCount)
                }
                if store.showMascot {
                    Text(quip)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(2)
                        .id(quip)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: quip)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: store.showMascot ? 80 : 0, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPanel { headerClicked() }
        }
        .overlay {
            // In the floating panel the card doubles as the drag handle.
            if isPanel {
                WindowDragArea(onClick: headerClicked)
            }
        }
        .background {
            if store.showMascot {
                RadarView(store: store, pointer: pointer)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .panelGlass(cornerRadius: 16)
        .padding(8)
        .contextMenu {
            Toggle("Show the radar", isOn: $store.showMascot)
        }
        .task {
            // Rotate the commentary every so often.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                quipSeed += 1
            }
        }
    }

    /// Clicking a blip opens that server; clicking empty scope sends a ping.
    private func headerClicked() {
        guard store.showMascot else { return }
        if let id = store.radarHover, let entry = store.entries.first(where: { $0.id == id }) {
            if entry.speaksHTTP { store.open(entry) } else { store.copyURL(entry) }
            return
        }
        quipSeed += 1
        store.poke()
    }

    private var quip: String {
        let lines = Quips.lines(for: store)
        return lines[quipSeed % lines.count]
    }
}

/// Compact capsule button that brightens on hover and dims while pressed.
struct PillButtonStyle: ButtonStyle {
    enum Role { case neutral, destructive }
    var role: Role

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, role: role)
    }

    private struct Pill: View {
        let configuration: Configuration
        let role: Role
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(role == .destructive ? Color.white : Color.primary)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(role == .neutral ? (hovering ? 0.3 : 0.18) : 0)))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }

        private var fill: Color {
            switch role {
            case .destructive: return Color.red.opacity(hovering ? 1 : 0.85)
            case .neutral: return Color.primary.opacity(hovering ? 0.18 : 0.08)
            }
        }
    }
}

/// Borderless icon button with a soft circular hover fill. `onDark` tunes it for the radar card.
struct IconButtonStyle: ButtonStyle {
    var onDark = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Icon(configuration: configuration, onDark: onDark, active: active)
    }

    private struct Icon: View {
        let configuration: Configuration
        let onDark: Bool
        let active: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.body)
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(Circle().fill(base.opacity(hovering ? 0.16 : 0)))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var base: Color { onDark ? .white : .primary }

        private var foreground: Color {
            if active { return onDark ? .white : .accentColor }
            return base.opacity(hovering ? 1 : (onDark ? 0.8 : 0.65))
        }
    }
}
