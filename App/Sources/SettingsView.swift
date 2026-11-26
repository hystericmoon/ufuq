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

    var body: some View {
        Form {
            Toggle("Open the panel when the pointer enters the notch", isOn: $hoverToOpen)
            LaunchAtLoginToggle()
            Text("The hotkey ⌥Space always opens the panel.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
