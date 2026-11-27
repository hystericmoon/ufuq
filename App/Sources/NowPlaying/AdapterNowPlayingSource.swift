import Foundation
import UfuqCore

/// ungive/mediaremote-adapter, run through /usr/bin/perl. The script, the framework and the test
/// client are bundled at Contents/Resources/MediaRemoteAdapter (CI builds them; see mac.yml).
final class AdapterNowPlayingSource: NowPlayingSource, @unchecked Sendable {
    let name = "MediaRemote adapter"

    private let perl = "/usr/bin/perl"
    private let script: String?
    private let framework: String?
    private let testClient: String?

    /// MediaRemote command ids for `send`. The README says "a positive integer" and points at the
    /// `supportedCommands` key; these are the MRMediaRemoteCommand values.
    private enum CommandID {
        static let togglePlayPause = 2
        static let next = 4
        static let previous = 5
    }

    init(bundle: Bundle = .main) {
        let dir = bundle.resourceURL?.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        func path(_ file: String) -> String? {
            guard let url = dir?.appendingPathComponent(file),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url.path
        }
        script = path("mediaremote-adapter.pl")
        framework = path("MediaRemoteAdapter.framework")
        testClient = path("MediaRemoteAdapterTestClient")
    }

    /// `[script, framework, testClient]`, or nil when the bundle lacks the files.
    private var base: [String]? {
        guard let script, let framework, let testClient else { return nil }
        return [script, framework, testClient]
    }

    func selfTest() async -> Bool {
        guard let base else { return false }
        guard let output = try? await ProcessRunner.run("/usr/bin/perl", base + ["test"], timeout: 5) else { return false }
        return output.status == 0
    }

    func snapshot() async throws -> NowPlaying? {
        guard let base else { throw ProcessRunnerError.failed(-1) }
        let output = try await ProcessRunner.run("/usr/bin/perl", base + ["get"])
        guard output.status == 0 else { throw ProcessRunnerError.failed(output.status) }
        return MediaRemoteAdapterParser.parse(output.stdout).nowPlaying
    }

    func send(_ command: NowPlayingCommand) async throws {
        guard let base else { throw ProcessRunnerError.failed(-1) }
        let arguments: [String]
        switch command {
        case .playPause: arguments = ["send", String(CommandID.togglePlayPause)]
        case .next: arguments = ["send", String(CommandID.next)]
        case .previous: arguments = ["send", String(CommandID.previous)]
        case .seek(let seconds): arguments = ["seek", String(Int(max(0, seconds) * 1_000_000))]
        }
        let output = try await ProcessRunner.run("/usr/bin/perl", base + arguments)
        guard output.status == 0 else { throw ProcessRunnerError.failed(output.status) }
    }
}
