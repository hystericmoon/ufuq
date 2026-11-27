import Foundation
import UfuqCore

/// The Mac side of the GitHub Actions module: transport, `gh` runner, token file, watched repos.
enum GitHubSupport {
    /// Set at launch; Settings lists its repos.
    static var autoStore: AutoRepoStore?

    static let manualReposKey = "githubManualRepos"

    static var tokenPath: String { GitHubTokenSource.defaultTokenPath(home: NSHomeDirectory()) }

    static var manualRepos: [String] {
        UserDefaults.standard.stringArray(forKey: manualReposKey) ?? []
    }

    static let transport: GitHubClient.Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        return (data, http)
    }

    static func makeClient(_ token: String) -> GitHubClient {
        GitHubClient(token: token, transport: transport)
    }

    static func tokenSource() -> GitHubTokenSource {
        GitHubTokenSource(
            runCommand: { ghCache.value(for: $0, $1) },
            readFile: { try? String(contentsOfFile: $0, encoding: .utf8) },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            tokenPath: tokenPath)
    }

    /// `gh auth token` launches a process; polls run every 15–60 s, so reuse the answer for 10 min.
    static let ghCache = CommandCache(ttl: 600) { run($0, $1) }

    /// Runs an executable with a 5 s timeout; nil if it does not exist or cannot start.
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, stdout: String)? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - Token file (same approach as SyncKeyStore: directory 0700, file 0600)

    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let url = URL(fileURLWithPath: tokenPath)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try Data(value.utf8).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            NSLog("Ufuq: could not save the GitHub token")
            return false
        }
    }

    static func removeToken() {
        try? FileManager.default.removeItem(atPath: tokenPath)
    }
}

/// Repos found from Claude Code sessions, kept for 24 h after the session was last seen.
final class AutoRepoStore: @unchecked Sendable {
    static let retention: TimeInterval = 24 * 3600

    private let lock = NSLock()
    private var lastSeen: [String: Date] = [:]
    private let sessions: @Sendable () -> [AgentSession]
    private let repoForDirectory: @Sendable (String) -> String?
    private let now: @Sendable () -> Date

    init(sessions: @escaping @Sendable () -> [AgentSession],
         repoForDirectory: @escaping @Sendable (String) -> String? = {
             GitRemote.repo(forDirectory: $0, fileSource: LocalFileSource())
         },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.sessions = sessions
        self.repoForDirectory = repoForDirectory
        self.now = now
    }

    /// Most recently seen first.
    func repos() -> [String] {
        let time = now()
        let cwds = Set(sessions().map(\.cwd).filter { !$0.isEmpty })
        let found = cwds.compactMap(repoForDirectory)
        lock.lock()
        defer { lock.unlock() }
        for repo in found { lastSeen[repo] = time }
        lastSeen = lastSeen.filter { time.timeIntervalSince($0.value) < Self.retention }
        return lastSeen.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}

/// Caches a command's result per path + arguments for `ttl` seconds.
final class CommandCache: @unchecked Sendable {
    typealias Result = (status: Int32, stdout: String)?
    private let ttl: TimeInterval
    private let runner: (String, [String]) -> Result
    private let lock = NSLock()
    private var entries: [String: (at: Date, result: Result)] = [:]

    init(ttl: TimeInterval, runner: @escaping (String, [String]) -> Result) {
        self.ttl = ttl
        self.runner = runner
    }

    func value(for path: String, _ arguments: [String]) -> Result {
        let key = ([path] + arguments).joined(separator: "\u{0}")
        lock.lock()
        if let entry = entries[key], Date().timeIntervalSince(entry.at) < ttl {
            lock.unlock()
            return entry.result
        }
        lock.unlock()
        let result = runner(path, arguments)
        lock.lock()
        entries[key] = (Date(), result)
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
