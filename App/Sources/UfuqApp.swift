import SwiftUI
import UfuqCore

@main
struct UfuqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Ufuq", systemImage: "moon.stars") {
            Button("Open panel  ⌥Space") {
                appDelegate.controller?.toggleExpanded()
            }
            LaunchAtLoginToggle()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
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
        let controller = NotchController(registry: registry)
        controller.start()
        self.controller = controller
    }
}
