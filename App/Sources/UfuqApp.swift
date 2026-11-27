import SwiftUI
import UfuqCore

@main
struct UfuqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = UpdaterController.shared
    @StateObject private var stayAwake = StayAwakeController.shared
    @StateObject private var transcriber = SpeechTranscriber.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Ufuq", systemImage: "moon.stars") {
            Button("Open panel  ⌥Space") {
                appDelegate.controller?.toggleExpanded()
            }
            Button("Capture Text (OCR)…") {
                TrayController.shared.captureScreenOCR()
            }
            Button(TimerControl.module?.snapshot() == nil ? "Start 25m Focus Timer" : "Stop Timer") {
                if TimerControl.module?.snapshot() == nil {
                    TimerControl.startFocus()
                } else {
                    TimerControl.stop()
                }
            }
            Button(stayAwake.isActive ? "Allow Mac to Sleep" : "Stay Awake") {
                stayAwake.toggle()
            }
            Button(transcriber.isRecording ? "Stop Voice Transcribe" : "Voice Transcribe…") {
                transcriber.toggleRecording()
            }
            Divider()
            LaunchAtLoginToggle()
            PairPhoneButton()
            Button("Setup Guide…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            OpenSettingsButton()
            CheckForUpdatesButton(updater: updater)
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        Window("Pair phone", id: "pair-phone") { PairingView() }
            .windowResizability(.contentSize)
        Window("Welcome to Ufuq", id: "onboarding") { OnboardingView() }
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
        let calendarModule = CalendarModule(
            source: EventKitCalendarSource.shared,
            isEnabled: AppSettings.calendarEnabled
        )
        try? registry.register(calendarModule)
        CalendarControl.refresh = {
            Task { try? await calendarModule.refresh() }
        }
        let timerModule = TimerModule()
        try? registry.register(timerModule)
        TimerControl.module = timerModule
        try? registry.register(DownloadsModule(
            scanner: { DownloadsMonitor.scan() },
            isEnabled: AppSettings.downloadsEnabled
        ))
        try? registry.register(AudioAccessoryModule(
            provider: { BluetoothAudioMonitor.connectedDevices() },
            isEnabled: AppSettings.audioAccessoryEnabled
        ))
        SyncService.shared.contentProvider = {
            SyncSnapshotContent(agents: agentModule.syncAgents(at: Date()))
        }
        let controller = NotchController(registry: registry)
        controller.start()
        self.controller = controller
        SyncService.shared.apply()
        if !AppSettings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "Welcome to Ufuq" {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}
