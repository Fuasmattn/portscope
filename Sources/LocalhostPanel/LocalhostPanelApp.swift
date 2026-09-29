import AppKit
import Carbon.HIToolbox
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
                Image(systemName: "network")
                    .symbolEffect(.bounce, value: store.badgeCount)
                Text("\(store.badgeCount)")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app switcher entry.
        NSApplication.shared.setActivationPolicy(.accessory)

        Task { @MainActor in
            ServerStore.shared.start()
        }

        // Control-Option-L toggles the floating panel.
        hotKey = GlobalHotKey(
            keyCode: kVK_ANSI_L,
            modifiers: controlKey | optionKey
        ) {
            Task { @MainActor in
                FloatingPanelController.shared.toggle()
            }
        }
    }
}
