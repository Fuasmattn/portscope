import SwiftUI

/// The Settings window: launch at login, refresh rate, radar, and the (fixed) hotkey.
struct SettingsView: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }))
                Toggle("Show the radar", isOn: $store.showMascot)
            }
            Section {
                Picker("Refresh while open", selection: $store.activeRefreshInterval) {
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 5 seconds").tag(5.0)
                }
                LabeledContent("Refresh in background", value: "Every 10 seconds")
            }
            Section {
                LabeledContent("Toggle panel", value: "⌃⌥L")
                Text("Hotkey is fixed for now.")
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
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }
}
