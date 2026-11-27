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
            GitHubActionsSection()
            NowPlayingSection()
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

    /// Resolved so a symlinked settings.json (dotfile managers) is written through, not replaced.
    private func settingsURL(_ dir: String) -> URL {
        URL(fileURLWithPath: dir).appendingPathComponent("settings.json").resolvingSymlinksInPath()
    }

    /// Run from the DMG or Downloads, macOS moves the app to a random path that disappears;
    /// hooks pointing there would silently stop working.
    private static var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    private func refresh() {
        dirs = ClaudeAccounts.configDirs()
        for dir in dirs {
            let data = try? Data(contentsOf: settingsURL(dir))
            installed[dir] = data.map(ClaudeHookInstaller.isInstalled(in:)) ?? false
        }
    }

    private func install(_ dir: String) {
        guard !Self.isTranslocated else {
            results[dir] = "Move Ufuq to the Applications folder and reopen it first; nothing changed."
            return
        }
        let url = settingsURL(dir)
        let existing = try? Data(contentsOf: url)
        do {
            let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.ufuq-backup")
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

/// Token and watched repos for the GitHub Actions tile. The token is never displayed.
struct GitHubActionsSection: View {
    private enum Source: Equatable { case gh(login: String?), saved(login: String?), none }

    @State private var source: Source?
    @State private var tokenInput = ""
    @State private var saveError = false
    @State private var manual = GitHubSupport.manualRepos
    @State private var auto: [String] = []
    @State private var newRepo = ""
    @State private var addMessage: String?
    @State private var adding = false

    private static let tokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    private var statusText: String {
        switch source {
        case nil: return "Checking…"
        case .gh(let login)?: return login.map { "Using gh (\($0))" } ?? "Using gh"
        case .saved(let login)?: return login.map { "Using saved token (\($0))" } ?? "Using saved token"
        case .none?: return "No token"
        }
    }

    private var repoRows: [(repo: String, fromSession: Bool)] {
        var seen = Set<String>()
        var rows: [(String, Bool)] = []
        for repo in manual where seen.insert(repo.lowercased()).inserted { rows.append((repo, false)) }
        for repo in auto where seen.insert(repo.lowercased()).inserted { rows.append((repo, true)) }
        return rows
    }

    var body: some View {
        Section("GitHub Actions") {
            Text(statusText)
            HStack {
                SecureField("Personal access token", text: $tokenInput)
                    .textContentType(.password)
                Button("Save") { saveToken() }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if case .saved? = source {
                    Button("Remove") { removeToken() }
                }
            }
            if saveError {
                Text("Could not save the token.").font(.callout).foregroundStyle(.secondary)
            }
            Link("Create a fine-grained token (Actions: read)", destination: Self.tokenURL)
            Text("Ufuq uses the gh command when it is logged in. Otherwise paste a token; it is kept in a private file in Application Support and never shown again.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(repoRows, id: \.repo) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text(row.repo)
                        Text(row.fromSession ? "from a Claude session" : "added")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !row.fromSession {
                        Button("Remove") { removeRepo(row.repo) }
                            .accessibilityLabel("Remove \(row.repo)")
                    }
                }
                .accessibilityElement(children: .contain)
            }
            HStack {
                TextField("owner/repo", text: $newRepo)
                    .onSubmit { addRepo() }
                Button("Add") { addRepo() }
                    .disabled(adding || newRepo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addMessage {
                Text(addMessage).font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            auto = GitHubSupport.autoStore?.repos() ?? []
            Task { await loadSource() }
        }
    }

    private func loadSource() async {
        let found = await Task.detached { GitHubSupport.tokenSource().token() }.value
        guard let found else { source = Source.none; return }
        source = found.origin == .gh ? .gh(login: nil) : .saved(login: nil)
        let login = try? await GitHubSupport.makeClient(found.value).user()
        source = found.origin == .gh ? .gh(login: login) : .saved(login: login)
    }

    private func saveToken() {
        saveError = !GitHubSupport.saveToken(tokenInput)
        if !saveError { tokenInput = "" }
        Task { await loadSource() }
    }

    private func removeToken() {
        GitHubSupport.removeToken()
        Task { await loadSource() }
    }

    private func removeRepo(_ repo: String) {
        manual.removeAll { $0 == repo }
        UserDefaults.standard.set(manual, forKey: GitHubSupport.manualReposKey)
    }

    private func addRepo() {
        let repo = newRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard repo.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil else {
            addMessage = "Use the form owner/repo."
            return
        }
        guard !manual.contains(where: { $0.caseInsensitiveCompare(repo) == .orderedSame }) else {
            addMessage = "Already added."
            return
        }
        adding = true
        addMessage = "Checking…"
        Task {
            defer { adding = false }
            guard let token = await Task.detached(operation: { GitHubSupport.tokenSource().token() }).value else {
                addMessage = "Add a token first."
                return
            }
            do {
                if try await GitHubSupport.makeClient(token.value).repoExists(repo) {
                    manual.append(repo)
                    UserDefaults.standard.set(manual, forKey: GitHubSupport.manualReposKey)
                    newRepo = ""
                    addMessage = nil
                } else {
                    addMessage = "Not found or the token can't see it"
                }
            } catch GitHubError.unauthorized {
                addMessage = "GitHub rejected the token."
            } catch {
                addMessage = "Could not reach GitHub."
            }
        }
    }
}

/// Which Now Playing source works: the MediaRemote adapter, else Spotify.
struct NowPlayingSection: View {
    @State private var text = "Checking…"

    var body: some View {
        Section("Now Playing") {
            Text(text)
                .task { await load() }
        }
    }

    private func load() async {
        while !Task.isCancelled {
            text = NowPlayingControl.module?.activeSourceDescription ?? "Unavailable"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
