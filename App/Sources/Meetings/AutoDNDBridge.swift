import Foundation
import UfuqCore

/// Tracks meeting-driven Do Not Disturb state and invokes a user-configured macOS Focus Shortcut.
@MainActor
final class AutoDNDBridge: ObservableObject {
    static let shared = AutoDNDBridge()

    @Published private(set) var isDNDActive = false
    @Published private(set) var lastStatus: String?

    private var tracker = AutoDNDTracker()

    func update(ongoingMeeting: MeetingEvent?) {
        let transition = tracker.update(
            enabled: AppSettings.autoDNDEnabled,
            ongoingMeeting: ongoingMeeting,
            requireVideoLink: true
        )
        switch transition {
        case .none:
            break
        case .enable(let meeting):
            isDNDActive = true
            runShortcut(input: "on", reason: "Meeting started: \(meeting.title)")
        case .disable:
            isDNDActive = false
            runShortcut(input: "off", reason: "Meeting ended")
        }
    }

    func testShortcut(on: Bool) {
        runShortcut(input: on ? "on" : "off", reason: "Manual test")
    }

    private func runShortcut(input: String, reason: String) {
        let name = AppSettings.autoDNDShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            lastStatus = "\(reason) (set a Focus Shortcut name in Settings to automate macOS Focus)"
            return
        }
        Task {
            let status = await Task.detached(priority: .utility) {
                Self.executeShortcut(named: name, input: input)
            }.value
            self.lastStatus = status
        }
    }

    private nonisolated static func executeShortcut(named name: String, input: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = outPipe
        do {
            try process.run()
            if let data = input.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
            }
            inPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "Ran Focus shortcut \"\(name)\" (\(input))"
            }
            let text = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "Shortcut \"\(name)\" failed" : text
        } catch {
            return "Could not run Shortcuts: \(error.localizedDescription)"
        }
    }
}
