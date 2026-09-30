import AppKit
import SwiftUI

/// Reports whether the hosting window is actually on screen, so animation and fast polling
/// can pause while the menu bar popover or floating panel is closed.
struct WindowVisibilityProbe: NSViewRepresentable {
    let onChange: (NSWindow, Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: ((NSWindow, Bool) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window = window else { return }
            report(window)
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self = self, let window = window else { return }
                    self.report(window)
                }
            }
        }

        private func report(_ window: NSWindow) {
            onChange?(window, window.isVisible && window.occlusionState.contains(.visible))
        }

        deinit {
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
