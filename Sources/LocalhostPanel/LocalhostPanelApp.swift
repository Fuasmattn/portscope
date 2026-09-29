import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@main
struct LocalhostPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = ServerStore.shared

    var body: some Scene {
        MenuBarExtra {
            ServerListView(store: store)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: RadarGlyph.image)
                    .symbolEffect(.bounce, value: store.badgeCount)
                switch store.badgeStyle {
                case .count:
                    Text("\(store.badgeCount)")
                        .monospacedDigit()
                case .dot:
                    if store.badgeCount > 0 {
                        Circle().frame(width: 5, height: 5)
                    }
                case .icon:
                    EmptyView()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var keyMonitor: Any?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry.
        NSApplication.shared.setActivationPolicy(.accessory)

        Task { @MainActor in
            let store = ServerStore.shared
            store.start()

            registerHotKey(store.hotKey)
            store.$hotKey
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] binding in self?.registerHotKey(binding) }
                .store(in: &subscriptions)

            // List navigation: arrows, return, space, ⌘⌫, ⌘F, Esc, only inside our windows.
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard let window = event.window, store.owns(window) else { return event }
                if window.firstResponder is NSTextView {
                    // Typing in the filter field: only Esc leaves it.
                    guard event.keyCode == 53 else { return event }
                    window.makeFirstResponder(nil)
                }
                return store.handleKey(event) ? nil : event
            }
        }
    }

    private func registerHotKey(_ binding: HotKeyBinding) {
        hotKey = nil
        hotKey = GlobalHotKey(keyCode: binding.keyCode, modifiers: binding.modifiers) {
            Task { @MainActor in
                FloatingPanelController.shared.toggle()
            }
        }
        if hotKey == nil {
            Task { @MainActor in ServerStore.shared.message = "Could not register \(binding.label). Try another key." }
        }
    }
}

/// The menu bar icon: a tiny scope with a beam, rendered once as a template image.
@MainActor
enum RadarGlyph {
    static let image: NSImage = {
        let side: CGFloat = 18
        let renderer = ImageRenderer(content: Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + 0.5)
            let radius = size.width / 2 - 1.5
            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(.black), lineWidth: 1.5)
            let inner = radius * 0.5
            context.stroke(
                Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)),
                with: .color(.black.opacity(0.55)), lineWidth: 1)
            var wedge = Path()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-20), clockwise: false)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(.black.opacity(0.85)))
            let dot = CGPoint(x: center.x - radius * 0.45, y: center.y + radius * 0.35)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 1.5, y: dot.y - 1.5, width: 3, height: 3)), with: .color(.black))
        }.frame(width: side, height: side))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "network", accessibilityDescription: nil)!
        image.isTemplate = true
        image.size = NSSize(width: side, height: side)
        return image
    }()
}
