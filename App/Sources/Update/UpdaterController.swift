import Combine
import SwiftUI
import Sparkle

/// Wraps Sparkle's standard updater. With no public key (dev/CI builds) the updater is never
/// started, so nothing contacts the network and nothing crashes.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    let isEnabled: Bool
    private let controller: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var canCheckForUpdates = false

    var versionText: String {
        let info = Bundle.main.infoDictionary
        return UpdatePolicy.versionString(
            short: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String)
    }

    /// Mirrors `SPUUpdater.automaticallyChecksForUpdates`.
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let enabled = UpdatePolicy.isEnabled(publicKey: key)
        // The unit tests are hosted by the app; never start Sparkle there.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        isEnabled = enabled
        controller = SPUStandardUpdaterController(
            startingUpdater: enabled && !underTest, updaterDelegate: nil, userDriverDelegate: nil)
        if enabled && !underTest {
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
                .store(in: &cancellables)
        }
    }

    func checkForUpdates() {
        guard isEnabled else { return }
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.isEnabled || !updater.canCheckForUpdates)
            .accessibilityLabel("Check for updates")
            .accessibilityHint(updater.isEnabled ? "" : UpdatePolicy.disabledMessage)
    }
}

struct UpdateSettingsSection: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Section("Updates") {
            if updater.isEnabled {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.automaticallyChecks = $0 }))
                    .accessibilityLabel("Check for updates automatically")
                Text(AppSettings.updateDisclosure)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(UpdatePolicy.disabledMessage)
                    .foregroundStyle(.secondary)
            }
            Text("Version \(updater.versionText)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
