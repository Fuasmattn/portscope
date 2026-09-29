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

    func toggle() {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private var contentSize: CGSize = .zero
    private var shrink: DispatchWorkItem?

    /// The window is transparent, so it can be larger than the card without showing. Growing
    /// happens at once (the card animates inside); shrinking waits until the collapse animation
    /// has settled, so the window edge never fights SwiftUI's spring.
    fileprivate func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        guard let panel = panel else { return }
        panel.invalidateShadow()
        shrink?.cancel()
        if size.height > panel.frame.height + 0.5 || abs(size.width - panel.frame.width) > 0.5 {
            resize(panel, to: size)
        } else if size.height < panel.frame.height - 0.5 {
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let panel = self.panel else { return }
                self.resize(panel, to: self.contentSize)
            }
            shrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    /// Keeps the top-left corner where it is.
    private func resize(_ panel: NSPanel, to size: CGSize) {
        var frame = panel.frame
        frame.origin.y = frame.maxY - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = contentSize.height > 0 ? contentSize : (panel.contentView?.fittingSize ?? .zero)
        if size.height > 0 { panel.setContentSize(size) }
        if ServerStore.shared.rememberPanelPosition, let saved = savedOrigin, fits(saved, panel) {
            panel.setFrameOrigin(saved)
        } else {
            position(panel)
        }
        panel.makeKeyAndOrderFront(nil)
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
        // shadow are ours. The window is not auto-sized; it follows the content's measured size
        // every frame, so SwiftUI's spring drives the window edge too instead of a one-step jump.
        let root = ServerListView(store: ServerStore.shared, isPanel: true)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                // Off the layout pass: setting a window frame mid-layout would re-enter it.
                DispatchQueue.main.async { FloatingPanelController.shared.contentSizeChanged(size) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []

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
