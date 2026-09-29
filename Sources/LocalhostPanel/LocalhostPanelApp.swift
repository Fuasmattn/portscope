import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@main
struct LocalhostPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = ServerStore.shared

    var body: some Scene {
        // The floating panel is the only UI; the menu bar item just toggles it.
        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var keyMonitor: Any?
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry.
        NSApplication.shared.setActivationPolicy(.accessory)

        Task { @MainActor in
            let store = ServerStore.shared
            store.start()

            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = RadarGlyph.image
            item.button?.imagePosition = .imageLeading
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            statusItem = item
            store.objectWillChange
                .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.updateStatusItem() }
                .store(in: &subscriptions)
            updateStatusItem()

            registerHotKey(store.settings.hotKey)
            store.settings.$hotKey
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

    @objc private func statusItemClicked() {
        let anchor = statusItem?.button?.window?.frame
        Task { @MainActor in FloatingPanelController.shared.toggle(anchor: anchor) }
    }

    /// Count, dot, or nothing next to the glyph; an orange mark when a server has run past the stale threshold.
    @MainActor
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let store = ServerStore.shared
        let title = NSMutableAttributedString()
        switch store.settings.badgeStyle {
        case .count:
            title.append(NSAttributedString(
                string: " \(store.badgeCount)",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]))
        case .dot:
            if store.badgeCount > 0 { title.append(NSAttributedString(string: " •")) }
        case .icon:
            break
        }
        if store.hasStaleServer {
            title.append(NSAttributedString(string: " •", attributes: [.foregroundColor: NSColor.systemOrange]))
        }
        button.attributedTitle = title
        button.toolTip = store.hasStaleServer
            ? "A server has been running longer than \(store.settings.staleHours) hours"
            : "\(store.badgeCount) servers on localhost"
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

/// The menu bar icon: a corner scope with rings widening outward and one contact, rendered once as a template image.
@MainActor
enum RadarGlyph {
    static let image: NSImage = {
        let side: CGFloat = 18
        let renderer = ImageRenderer(content: Canvas { context, size in
            let origin = CGPoint(x: size.width - 1.5, y: 1.5)
            let reach = hypot(size.width, size.height) - 2
            func ring(_ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
            }
            for step in 1...3 {
                let fraction = pow(CGFloat(step) / 3.3, 1.5)
                let alpha = step == 3 ? 1.0 : 0.55 + 0.15 * Double(step)
                context.stroke(ring(reach * fraction), with: .color(.black.opacity(alpha)), lineWidth: step == 3 ? 1.6 : 1.1)
            }
            context.fill(ring(1.6), with: .color(.black))
            let dot = CGPoint(x: size.width * 0.42, y: size.height * 0.58)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 1.8, y: dot.y - 1.8, width: 3.6, height: 3.6)), with: .color(.black))
        }.frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 4)))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "network", accessibilityDescription: nil)!
        image.isTemplate = true
        image.size = NSSize(width: side, height: side)
        return image
    }()
}
