import SwiftUI
import UfuqCore

@main
struct UfuqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = UpdaterController.shared

    var body: some Scene {
        MenuBarExtra("Ufuq", systemImage: "moon.stars") {
            Button("Open panel  ⌥Space") {
                appDelegate.controller?.toggleExpanded()
            }
            LaunchAtLoginToggle()
            PairPhoneButton()
            OpenSettingsButton()
            CheckForUpdatesButton(updater: updater)
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        Window("Pair phone", id: "pair-phone") { PairingView() }
            .windowResizability(.contentSize)
        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests are hosted by the app; do not open a panel there.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        let registry = ModuleRegistry()
        try? registry.register(PrayerModule(location: AppSettings.defaultLocation))
        try? registry.register(AIUsageModule(
            claudeDirs: ClaudeAccounts.configDirs(),
            codexSessionsDir: CodexParser.defaultSessionsDir(),
            antigravityDir: AntigravityParser.defaultConfigDir()))
        let agentModule = AgentStatusModule(
            directory: AgentStateStore.resolveDirectory(environment: ProcessInfo.processInfo.environment))
        try? registry.register(agentModule)
        let autoStore = AutoRepoStore(sessions: { agentModule.sessions(at: Date()) })
        GitHubSupport.autoStore = autoStore
        try? registry.register(GitHubActionsModule(
            tokenSource: GitHubSupport.tokenSource(),
            makeClient: GitHubSupport.makeClient,
            autoRepos: { autoStore.repos() },
            manualRepos: { GitHubSupport.manualRepos }))
        let nowPlayingModule = NowPlayingModule(sources: [AdapterNowPlayingSource(), SpotifyNowPlayingSource()])
        try? registry.register(nowPlayingModule)
        NowPlayingControl.module = nowPlayingModule
        NowPlayingControl.send = { command in
            Task { await nowPlayingModule.send(command); try? await nowPlayingModule.refresh() }
        }
        SyncService.shared.contentProvider = {
            SyncSnapshotContent(agents: agentModule.syncAgents(at: Date()))
        }
        let controller = NotchController(registry: registry)
        controller.start()
        self.controller = controller
        SyncService.shared.apply()
    }
}
