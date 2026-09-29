import AppKit
import PanelCore
import SwiftUI

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
                        .foregroundStyle(store.settings.showMascot ? Color.white : Color.primary)
                    Text("\(store.badgeCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(store.settings.showMascot ? Color.white.opacity(0.65) : Color.secondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: store.badgeCount)
                }
                if store.settings.showMascot {
                    TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
                        let on = Int(timeline.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(quip)
                                .lineLimit(2)
                                .id(quip)
                                .transition(.opacity)
                            Text("▍")
                                .opacity(on ? 0.7 : 0)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.65))
                    }
                }
            }
            .animation(.default, value: quip)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: store.settings.showMascot ? 80 : 0, alignment: .leading)
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
            if store.settings.showMascot {
                RadarView(store: store, pointer: pointer)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .panelGlass(cornerRadius: 16)
        .padding(8)
        .contextMenu {
            Toggle("Show the radar", isOn: Binding(get: { store.settings.showMascot }, set: { store.settings.showMascot = $0 }))
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
        guard store.settings.showMascot else { return }
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
