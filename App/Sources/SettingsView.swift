import SwiftUI

struct LaunchAtLoginToggle: View {
    @State private var enabled = LaunchAtLogin.isEnabled

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { enabled },
            set: { newValue in
                do {
                    try LaunchAtLogin.setEnabled(newValue)
                } catch {
                    NSLog("Ufuq: launch at login failed: \(error)")
                }
                enabled = LaunchAtLogin.isEnabled
            }))
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.hoverKey) private var hoverToOpen = false
    @AppStorage(AppSettings.syncKey) private var shareWithPhone = false

    var body: some View {
        Form {
            Toggle("Open the panel when the pointer enters the notch", isOn: $hoverToOpen)
            LaunchAtLoginToggle()
            Toggle("Share with phone on this network", isOn: $shareWithPhone)
                .onChange(of: shareWithPhone) { _, _ in SyncService.shared.apply() }
            Text("Off by default. Choose Pair phone… in the menu bar to link a phone; data is encrypted and never leaves your network.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The hotkey ⌥Space always opens the panel.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
