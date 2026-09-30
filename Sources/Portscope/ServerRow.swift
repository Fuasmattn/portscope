import AppKit
import PortscopeCore
import SwiftUI

let rowHeight: CGFloat = 46

struct ServerRow: View {
    let entry: ServerEntry
    @ObservedObject var store: ServerStore
    var grouped = false
    @State private var confirmingKill = false

    private var hovered: Bool { store.highlightedID == entry.id }
    private var selected: Bool { store.selectedID == entry.id }
    private var isStopping: Bool { store.stopping[entry.id] != nil }
    private var showingDetails: Bool { store.detailsID == entry.id }
    private var siblings: [ServerEntry] { store.siblings(of: entry) }

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
                        if store.rules.pinnedPorts.contains(entry.port) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(grouped ? entry.processName : entry.projectName)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !siblings.isEmpty {
                            Text("×\(siblings.count + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .help("Also PID \(siblings.map { String($0.pid) }.joined(separator: ", ")). Stop signals all of them.")
                        }
                        if store.hasPortConflict(entry) {
                            Text("port conflict")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .help("Another project also listens on :\(entry.port)")
                        }
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
                if store.settings.rowClickOpens, entry.speaksHTTP { store.open(entry) } else { store.toggleDetails(entry) }
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
        if let icon = Launchers.icon(for: launcher) {
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
        if entry.speaksHTTP {
            Button("Copy as curl") { store.copyAsCurl(entry) }
        }
        if entry.cwd != nil {
            Divider()
            let editors = Launchers.installedEditors
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
        Button(store.rules.pinnedPorts.contains(entry.port) ? "Unpin" : "Pin (always show)") { store.rules.togglePin(entry) }
        Button(store.rules.hiddenProcesses.contains(entry.processName)
               ? "Unhide all \(entry.processName)" : "Hide all \(entry.processName)") {
            store.rules.toggleHiddenProcess(entry)
        }
        Button(store.rules.hiddenPorts.contains(entry.port) ? "Unhide port \(String(entry.port))" : "Hide port \(String(entry.port))") {
            store.rules.toggleHidden(entry)
        }
        if let cwd = entry.cwd {
            Button(store.rules.hiddenFolders.contains(cwd) ? "Unhide project \(entry.projectName)" : "Hide project \(entry.projectName)") {
                store.rules.toggleHiddenFolder(entry)
            }
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
struct DetailsPopover: View {
    let entry: ServerEntry
    @ObservedObject var store: ServerStore
    @State private var path: String

    init(entry: ServerEntry, store: ServerStore) {
        self.entry = entry
        self.store = store
        _path = State(initialValue: store.settings.openPath(for: entry.port))
    }

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
            if entry.speaksHTTP {
                HStack(spacing: 6) {
                    Text("Opens")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("localhost:\(String(entry.port))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("/", text: $path)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit { store.settings.setOpenPath(path, for: entry.port) }
                        .onChange(of: path) { _, value in store.settings.setOpenPath(value, for: entry.port) }
                }
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
