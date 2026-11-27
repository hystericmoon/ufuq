import AppKit
import Foundation
import UfuqCore

/// Spotify through AppleScript (the fallback when the adapter does not work). Scripts run on one
/// serial background queue, never on the main thread.
final class SpotifyNowPlayingSource: NowPlayingSource, @unchecked Sendable {
    let name = "Spotify"

    private let queue = DispatchQueue(label: "app.ufuq.spotify-applescript", qos: .utility)

    func selfTest() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    func snapshot() async throws -> NowPlaying? {
        let output = try await run(SpotifyAppleScriptParser.script)
        return SpotifyAppleScriptParser.parse(output ?? "")
    }

    func send(_ command: NowPlayingCommand) async throws {
        let line: String
        switch command {
        case .playPause: line = "playpause"
        case .next: line = "next track"
        case .previous: line = "previous track"
        case .seek(let seconds): line = "set player position to \(Int(max(0, seconds)))"
        }
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to \(line)
        end if
        """
        _ = try await run(script)
    }

    private struct ScriptError: Error {}

    private func run(_ source: String) async throws -> String? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: ScriptError())
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if error != nil {
                    continuation.resume(throwing: ScriptError())
                } else {
                    continuation.resume(returning: result.stringValue)
                }
            }
        }
    }
}
