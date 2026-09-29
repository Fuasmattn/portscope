import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The Settings window: hotkey, panel behaviour, menu bar badge, refresh rate, radar.
struct SettingsView: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Toggle panel") {
                    HotKeyRecorder(binding: $store.hotKey)
                }
                Toggle("Reopen panel where I left it", isOn: $store.rememberPanelPosition)
            }
            Section {
                Picker("Menu bar shows", selection: $store.badgeStyle) {
                    ForEach(BadgeStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Show the radar", isOn: $store.showMascot)
            }
            Section {
                Picker("Clicking a row", selection: $store.rowClickOpens) {
                    Text("Shows details").tag(false)
                    Text("Opens in browser").tag(true)
                }
                Text("↩ always opens, Space always shows details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Refresh while open", selection: $store.activeRefreshInterval) {
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 5 seconds").tag(5.0)
                }
                LabeledContent("Refresh in background", value: "Every 10 seconds")
            }
            Section("Keyboard") {
                Text("↑ ↓ select · ↩ open · Space details · ⌘⌫ stop (⌥ for SIGKILL) · ⌘F filter · ⎋ clear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = store.message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Click, then press a key combo with at least one of ⌘ ⌃ ⌥. Esc cancels.
struct HotKeyRecorder: View {
    @Binding var binding: HotKeyBinding
    @State private var recording = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording.toggle()
            } label: {
                Text(recording ? "Press keys…" : binding.label)
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .frame(minWidth: 72)
            }
            .buttonStyle(.bordered)
            .background(KeyCapture(active: recording) { keyCode, flags in
                let modifiers = KeyNames.carbonModifiers(flags)
                if keyCode == 53 { recording = false; return }
                guard modifiers & (cmdKey | controlKey | optionKey) != 0 else { return }
                binding = HotKeyBinding(keyCode: keyCode, modifiers: modifiers)
                recording = false
            })
            if binding != .default {
                Button("Reset") { binding = .default }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }
}

/// Grabs the next key press in the window while active.
private struct KeyCapture: NSViewRepresentable {
    let active: Bool
    let onKey: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.setActive(active)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onKey: ((Int, NSEvent.ModifierFlags) -> Void)?
        private var monitor: Any?

        func setActive(_ active: Bool) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.onKey?(Int(event.keyCode), event.modifierFlags.intersection(.deviceIndependentFlagsMask))
                    return nil
                }
            } else if !active, let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
