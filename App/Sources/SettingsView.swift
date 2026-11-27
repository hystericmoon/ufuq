import AppKit
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

/// "Settings…" in the menu-bar menu. A menu-bar app is not frontmost, so the Settings window
/// opened behind other apps (or only after a delay); bring Ufuq forward first, then open it.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

struct SettingsView: View {
    @AppStorage(AppSettings.hoverKey) private var hoverToOpen = false
    @AppStorage(AppSettings.syncKey) private var shareWithPhone = false
    @AppStorage(AppSettings.allDisplaysKey) private var allDisplays = true

    @ObservedObject private var updater = UpdaterController.shared
    @ObservedObject private var sync = SyncService.shared

    var body: some View {
        Form {
            Toggle("Open the panel when the pointer enters the notch", isOn: $hoverToOpen)
            Toggle("Show the island on every display", isOn: $allDisplays)
            LaunchAtLoginToggle()
            Toggle("Share with phone on this network", isOn: $shareWithPhone)
                .onChange(of: shareWithPhone) { _, _ in SyncService.shared.apply() }
            if shareWithPhone {
                PhoneStatusRow(service: sync)
            }
            Text("Off by default. Choose Pair phone… in the menu bar to link a phone; data is encrypted and never leaves your network.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("The hotkey ⌥Space always opens the panel.")
                .foregroundStyle(.secondary)
            UpdateSettingsSection(updater: updater)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
