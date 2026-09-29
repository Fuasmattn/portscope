import AppKit
import PanelCore
import SwiftUI

private let rowHeight: CGFloat = 58
private let maxListHeight: CGFloat = 440
/// Above this many rows a search field appears.
private let searchThreshold = 8

struct ServerListView: View {
    @ObservedObject var store: ServerStore
    var isPanel = false
    @State private var pointer: CGPoint?
    @State private var listHeight: CGFloat = rowHeight
    @State private var searchPinned = false
    @FocusState private var filterFocused: Bool

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
        .onChange(of: store.filterFocusRequest) { _, _ in
            searchPinned = true
            DispatchQueue.main.async { filterFocused = true }
        }
        .onChange(of: filterFocused) { _, focused in
            if !focused, store.filter.isEmpty { searchPinned = false }
        }
    }

    private var header: some View {
        WatcherHeader(store: store, pointer: pointer, isPanel: isPanel)
    }

    private var showsSearch: Bool {
        searchPinned || !store.filter.isEmpty
            || store.entries.filter { store.showAll || store.isShownByDefault($0) }.count > searchThreshold
    }

    @ViewBuilder
    private var content: some View {
        let groups = store.groupedEntries
        if !store.hasScanned {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            if showsSearch {
                searchField
            }
            if groups.isEmpty {
                Text(store.filter.isEmpty ? "No servers listening" : "No match for “\(store.filter)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            if let title = group.title {
                                GroupHeader(title: title)
                            }
                            ForEach(group.entries) { entry in
                                ServerRow(entry: entry, store: store, grouped: group.title != nil)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(listHeight, maxListHeight))
                .animation(.spring(duration: 0.35), value: groups.map(\.id))
            }
            if !store.recentlyStopped.isEmpty {
                Divider()
                RecentlyStoppedSection(store: store)
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
                .focused($filterFocused)
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

/// Section label for several servers from the same project.
private struct GroupHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption2)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct ServerRow: View {
    let entry: ServerEntry
    @ObservedObject var store: ServerStore
    var grouped = false
    @State private var confirmingKill = false

    private var hovered: Bool { store.highlightedID == entry.id }
    private var selected: Bool { store.selectedID == entry.id }
    private var isStopping: Bool { store.stopping[entry.id] != nil }
    private var showingDetails: Bool { store.detailsID == entry.id }

    var body: some View {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    statusDot
                    Text(":\(String(entry.port))")
                        .font(.system(.body, design: .monospaced).weight(.medium))
                }
                .frame(width: 68, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if store.pinnedPorts.contains(entry.port) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(grouped ? entry.processName : entry.projectName)
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
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        HStack(spacing: 4) {
                            Text(subtitle(now: timeline.date))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let launcher = entry.launcher {
                                launcherBadge(launcher)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                trailing
            }
            .frame(height: rowHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                if store.rowClickOpens, entry.speaksHTTP { store.open(entry) } else { store.toggleDetails(entry) }
            }
        .padding(.horizontal, 12)
        .background(background)
        .popover(
            isPresented: Binding(
                get: { showingDetails },
                set: { open in if !open, showingDetails { store.detailsID = nil } }),
            arrowEdge: .bottom
        ) {
            DetailsPopover(entry: entry, store: store)
        }
        .onHover { inside in
            if inside {
                store.rowHover = entry.id
            } else if store.rowHover == entry.id {
                store.rowHover = nil
                confirmingKill = false
            }
        }
        .opacity(isStopping ? 0.55 : (store.isShownByDefault(entry) ? 1 : 0.5))
        .contextMenu { menu }
    }

    private var background: some View {
        ZStack(alignment: .leading) {
            Color.accentColor.opacity(hovered ? 0.12 : 0)
            if selected {
                Rectangle().fill(Color.accentColor).frame(width: 3)
            }
        }
    }

    /// Green answered, amber client error, red server error, grey connected but silent.
    @ViewBuilder
    private var statusDot: some View {
        switch entry.http {
        case .status(let code):
            Circle().fill(code >= 500 ? Color.red : code >= 400 ? Color.yellow : Color.green)
                .frame(width: 6, height: 6)
                .help("HTTP \(code)")
        case .unresponsive:
            Circle().fill(Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
                .help("Port is open but did not answer")
        case .notHTTP:
            Circle().fill(Color.clear).frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private func launcherBadge(_ launcher: String) -> some View {
        if let icon = store.launcherIcon(for: launcher) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 13, height: 13)
                .help("Started from \(launcher)")
        } else {
            Text("via \(launcher)")
        }
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
                Button { store.toggleDetails(entry) } label: { Image(systemName: "info.circle") }
                    .buttonStyle(IconButtonStyle(active: showingDetails))
                    .help("Details")
                if entry.speaksHTTP {
                    Button { store.open(entry) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(IconButtonStyle())
                        .help("Open in browser")
                }
                Button { confirmingKill = true } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(IconButtonStyle())
                    .help("Stop process")
            }
            .opacity(hovered || showingDetails ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if entry.speaksHTTP {
            Button("Open in browser") { store.open(entry) }
        }
        Button("Details") { store.toggleDetails(entry) }
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

    private func subtitle(now: Date) -> String {
        var parts: [String] = []
        if let branch = entry.branch { parts.append(branch) }
        if !grouped { parts.append(entry.processName) }
        if let uptime = store.liveUptime(entry, now: now) { parts.append(Formatting.uptime(uptime)) }
        return parts.joined(separator: " · ")
    }
}

/// Command, folder, PID, interfaces for one server, with copy buttons. Branch and launcher are in the row.
private struct DetailsPopover: View {
    let entry: ServerEntry
    @ObservedObject var store: ServerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(":\(String(entry.port))")
                    .font(.system(.body, design: .monospaced).weight(.medium))
                Text(entry.projectName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
                row("Command", entry.commandLine, mono: true) { store.copy(entry.commandLine, label: "command") }
                if let cwd = entry.cwd {
                    row("Folder", cwd, mono: true) { store.copy(cwd, label: "path") }
                }
                row("PID", String(entry.pid), mono: true) { store.copy(String(entry.pid), label: "PID") }
                row("Listening", entry.loopbackOnly ? "localhost only" : "all interfaces (\(entry.host))", mono: false, copy: nil)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func row(_ label: String, _ value: String, mono: Bool, copy: (() -> Void)?) -> some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
                .padding(.top, 1)
            Text(value)
                .font(mono ? .system(size: 11, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let copy = copy {
                Button { copy() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(IconButtonStyle())
                    .help("Copy")
            } else {
                Color.clear.frame(width: 24, height: 1)
            }
        }
    }
}

/// Servers stopped from here, with a way to start them again.
private struct RecentlyStoppedSection: View {
    @ObservedObject var store: ServerStore
    @State private var open = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("Recently stopped")
                        .font(.caption.weight(.semibold))
                    Text("\(store.recentlyStopped.count)")
                        .font(.caption.monospacedDigit())
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                ForEach(store.recentlyStopped) { stopped in
                    StoppedRow(stopped: stopped, store: store)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: open)
    }
}

private struct StoppedRow: View {
    let stopped: StoppedServer
    @ObservedObject var store: ServerStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(":\(String(stopped.port))")
                .font(.system(.callout, design: .monospaced))
                .frame(width: 68, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(stopped.projectName)
                    .font(.callout)
                    .lineLimit(1)
                Text(stopped.commandLine)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Start again") { store.startAgain(stopped) }
                .buttonStyle(PillButtonStyle(role: .neutral))
                .help("Run the same command in \(stopped.cwd ?? "the same folder")")
            Button { store.forget(stopped) } label: { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle())
                .help("Forget")
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(hovering ? Color.accentColor.opacity(0.08) : Color.clear)
        .onHover { hovering = $0 }
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
                .background(Circle().fill(base.opacity(hovering ? 0.16 : (active ? 0.1 : 0))))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Circle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var base: Color { onDark ? .white : .primary }

        private var foreground: Color {
            if active { return base }
            return base.opacity(hovering ? 1 : (onDark ? 0.8 : 0.65))
        }
    }
}
