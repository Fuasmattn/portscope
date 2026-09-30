import AppKit
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// A small floating window summoned by the global hotkey. Closes on Esc or when focus moves
/// away, unless the pin button in its header is on. Draggable by its background.
@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()

    private var panel: KeyablePanel?
    private var resignObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?

    /// When the panel last went away, so a status item click that closed it (by taking key) does not reopen it.
    private var lastHiddenAt: Date = .distantPast

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Hotkey: open near the mouse, or where it was left.
    func toggle() {
        toggle(anchor: nil)
    }

    /// Status item: open under the icon, or where it was left.
    func toggle(anchor: NSRect?) {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
        } else if Date().timeIntervalSince(lastHiddenAt) < 0.3 {
            // The click that reached us already closed the panel by taking key. Leave it closed.
            return
        } else {
            show(anchor: anchor)
        }
    }

    private func show(anchor: NSRect?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if ServerStore.shared.settings.rememberPanelPosition, let saved = savedOrigin, fits(saved, panel) {
            panel.setFrameOrigin(saved)
        } else if let anchor = anchor {
            position(panel, under: anchor)
        } else {
            position(panel)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    /// Centred under a menu bar item, clamped to that screen.
    private func position(_ panel: NSPanel, under anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = max(origin.y, visible.minY + 8)
        panel.setFrameOrigin(origin)
    }

    private var savedOrigin: NSPoint? {
        guard let values = UserDefaults.standard.array(forKey: "panelOrigin") as? [Double], values.count == 2 else { return nil }
        return NSPoint(x: values[0], y: values[1])
    }

    /// Only reuse a saved spot if it is still on some screen (monitors come and go).
    private func fits(_ origin: NSPoint, _ panel: NSPanel) -> Bool {
        let frame = NSRect(origin: origin, size: panel.frame.size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private func makePanel() -> KeyablePanel {
        // Borderless: no title bar, so the window is exactly the size of the list. Corners and
        // shadow are ours.
        let root = ServerListView(store: ServerStore.shared, isPanel: true)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // Milled edge: a dark outline and, just inside it, a highlight that fades toward the bottom.
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 13.5)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.06), Color.white.opacity(0.03)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5)
                    .padding(0.5))
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = [.preferredContentSize]

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.contentViewController = controller
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            guard let panel = panel else { return }
            UserDefaults.standard.set([panel.frame.origin.x, panel.frame.origin.y], forKey: "panelOrigin")
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard !ServerStore.shared.keepPanelOpen else { return }
                panel?.orderOut(nil)
                FloatingPanelController.shared.lastHiddenAt = Date()
            }
        }
        return panel
    }

    /// Opens near the mouse cursor, clamped to the visible area of that screen.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }
}

/// Transparent layer that drags the window when the mouse moves and reports a plain click otherwise.
/// Lets the radar card move the panel while still taking clicks for pings and blips.
struct WindowDragArea: NSViewRepresentable {
    var onClick: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onClick = onClick
    }

    final class DragView: NSView {
        var onClick: (() -> Void)?
        private var pressStart: NSPoint?

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            pressStart = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = pressStart else { return }
            let moved = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            if moved > 3 {
                pressStart = nil
                window?.performDrag(with: event)
            }
        }

        override func mouseUp(with event: NSEvent) {
            if pressStart != nil { onClick?() }
            pressStart = nil
        }

        override func rightMouseDown(with event: NSEvent) {
            // Leave context menus to SwiftUI.
            nextResponder?.rightMouseDown(with: event)
        }
    }
}
