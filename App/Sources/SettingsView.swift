import AppKit
import SwiftUI
import UfuqCore

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
            AgentStatusSection()
            UpdateSettingsSection(updater: updater)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}

/// Installs or removes the Claude Code hooks that feed agent status, one button per account.
struct AgentStatusSection: View {
    @State private var dirs = ClaudeAccounts.configDirs()
    @State private var installed: [String: Bool] = [:]
    @State private var results: [String: String] = [:]

    private static var hookPath: String { Bundle.main.bundlePath + "/Contents/MacOS/ufuq-hook" }

    var body: some View {
        Section("Agent status") {
            if dirs.isEmpty {
                Text("No Claude Code account found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(dirs, id: \.self) { dir in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ClaudeAccounts.label(forConfigDir: dir))
                            Text(installed[dir] == true ? "Hooks installed" : "Hooks not installed")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if installed[dir] == true {
                            Button("Remove") { remove(dir) }
                        } else {
                            Button("Install") { install(dir) }
                        }
                    }
                    if let result = results[dir] {
                        Text(result).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .contain)
            }
            Text("Shows Claude Code sessions in the notch. Ufuq edits settings.json only when you press Install, and keeps a backup.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
    }

    private func settingsURL(_ dir: String) -> URL { URL(fileURLWithPath: dir).appendingPathComponent("settings.json") }

    private func refresh() {
        dirs = ClaudeAccounts.configDirs()
        for dir in dirs {
            let data = try? Data(contentsOf: settingsURL(dir))
            installed[dir] = data.map(ClaudeHookInstaller.isInstalled(in:)) ?? false
        }
    }

    private func install(_ dir: String) {
        let url = settingsURL(dir)
        let existing = try? Data(contentsOf: url)
        do {
            let backup = URL(fileURLWithPath: dir).appendingPathComponent("settings.json.ufuq-backup")
            if let existing, !FileManager.default.fileExists(atPath: backup.path) {
                try existing.write(to: backup, options: .atomic)
            }
            let updated = try ClaudeHookInstaller.install(into: existing, hookPath: Self.hookPath)
            try updated.write(to: url, options: .atomic)
            results[dir] = "Hooks installed. Restart running Claude Code sessions to pick them up."
        } catch let error as ClaudeHookInstallerError {
            results[dir] = message(for: error)
        } catch {
            results[dir] = "Could not write settings.json: \(error.localizedDescription)"
        }
        refresh()
    }

    private func remove(_ dir: String) {
        let url = settingsURL(dir)
        do {
            let existing = try Data(contentsOf: url)
            try ClaudeHookInstaller.uninstall(from: existing).write(to: url, options: .atomic)
            results[dir] = "Hooks removed."
        } catch let error as ClaudeHookInstallerError {
            results[dir] = message(for: error)
        } catch {
            results[dir] = "Could not update settings.json: \(error.localizedDescription)"
        }
        refresh()
    }

    private func message(for error: ClaudeHookInstallerError) -> String {
        switch error {
        case .invalidSettings: return "settings.json isn't valid JSON; nothing changed."
        case .invalidHookPath: return "The hook helper path is unexpected; nothing changed."
        }
    }
}
