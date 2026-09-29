import PanelCore
import SwiftUI

/// Servers stopped from here, with a way to start them again.
struct RecentlyStoppedSection: View {
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
                    Text("\(store.history.entries.count)")
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
                ForEach(store.history.entries) { stopped in
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
            Button { store.history.forget(stopped) } label: { Image(systemName: "xmark") }
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
