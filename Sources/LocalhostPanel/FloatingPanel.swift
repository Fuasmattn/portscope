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

    func toggle() {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> KeyablePanel {
        let root = ServerListView(store: ServerStore.shared, isPanel: true)
            .background(.regularMaterial)
            // The hidden title bar still reserves a safe area; the list should start at the very top.
            .ignoresSafeArea()
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = [.preferredContentSize]

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.contentViewController = controller
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.titlebarSeparatorStyle = .none
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard !ServerStore.shared.keepPanelOpen else { return }
                panel?.orderOut(nil)
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
