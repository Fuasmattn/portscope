import AppKit
import PanelCore
import SwiftUI

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
                                Hairline().padding(.leading, 90)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(listHeight, maxListHeight))
                .animation(.spring(duration: 0.35), value: groups.map(\.id))
            }
            if !store.history.entries.isEmpty {
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
                Button {
                    store.showAll.toggle()
                } label: {
                    Text(store.showAll ? "Hide \(store.hiddenCount) again" : "Show \(store.hiddenCount) hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .underline(true, color: Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(store.showAll ? "Back to the filtered list" : "Include system noise and hidden servers")
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
