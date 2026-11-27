import Foundation

/// CI status of the repos you work in (GitHub Actions). See `docs/github-actions.md`.
public final class GitHubActionsModule: UfuqModule {
    public let id = "github"
    public let title = "GitHub Actions"
    public var isEnabled = true

    public static let maxRepos = 10
    public static let activeInterval: TimeInterval = 15
    public static let idleInterval: TimeInterval = 60
    /// A failed build stays in the wing this long after it finished.
    public static let failedWingWindow: TimeInterval = 10 * 60
    /// A passed build of yours stays in the wing this long.
    public static let passedWingWindow: TimeInterval = 5 * 60
    /// Your own build must have run this long to earn a "CI passed" peek.
    public static let passedPeekThreshold: TimeInterval = 60

    private struct RepoCache {
        var etag: String?
        var runs: [GitHubRun]
    }

    private struct State {
        var token: String?
        var login: String?
        var client: GitHubClient?
        var cache: [String: RepoCache] = [:]          // keyed by lowercased repo
        var builds: [GitHubBuild] = []
        /// Build states at the previous poll, per repo that has been polled successfully.
        var previous: [String: [String: GitHubBuild.State]] = [:]
        var status: ModuleStatus = .ok
        var lastSuccess: Date?
        var backoffUntil: Date?
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let tokenSource: GitHubTokenSource
    private let makeClient: @Sendable (String) -> GitHubClient
    private let autoRepos: @Sendable () -> [String]
    private let manualRepos: @Sendable () -> [String]
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var state = State()
    /// One poll at a time: a slow poll overlapping the next tick would race on `state`.
    private var isPolling = false

    /// - Parameters:
    ///   - makeClient: builds a client for a token (the app supplies the `URLSession` transport).
    ///   - autoRepos: repos found from Claude Code sessions (the app resolves them with `GitRemote`).
    ///   - manualRepos: `owner/repo` entries added in Settings.
    public init(tokenSource: GitHubTokenSource,
                makeClient: @escaping @Sendable (String) -> GitHubClient,
                autoRepos: @escaping @Sendable () -> [String] = { [] },
                manualRepos: @escaping @Sendable () -> [String] = { [] },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.tokenSource = tokenSource
        self.makeClient = makeClient
        self.autoRepos = autoRepos
        self.manualRepos = manualRepos
        self.now = now
    }

    public var status: ModuleStatus { withLock { $0.status } }

    // MARK: - Repos

    /// Manual first, then auto; deduped case-insensitively; at most 10.
    public func watchedRepos() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in manualRepos() + autoRepos() {
            let repo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard GitHubClient.isValidRepo(repo), seen.insert(repo.lowercased()).inserted else { continue }
            result.append(repo)
            if result.count == Self.maxRepos { break }
        }
        return result
    }

    // MARK: - Refresh (one poll)

    public func refresh() async throws {
        let started: Bool = { lock.lock(); defer { lock.unlock() }
            if isPolling { return false }
            isPolling = true
            return true
        }()
        guard started else { return }
        defer { lock.lock(); isPolling = false; lock.unlock() }
        let time = now()
        guard let token = tokenSource.token() else {
            withLock { s in
                s = State(status: .unavailable(reason: "No GitHub token"), peeks: s.peeks)
            }
            return
        }

        // Snapshot; a token change starts over (no peeks on the first poll after it).
        var snapshot = withLock { s -> State in
            if s.token != token.value {
                s = State(token: token.value, peeks: s.peeks)
            }
            return s
        }
        if let until = snapshot.backoffUntil, time < until { return }
        snapshot.backoffUntil = nil

        let client = snapshot.client ?? makeClient(token.value)
        snapshot.client = client
        let repos = watchedRepos()
        let wanted = Set(repos.map { $0.lowercased() })
        snapshot.cache = snapshot.cache.filter { wanted.contains($0.key) }
        snapshot.previous = snapshot.previous.filter { wanted.contains($0.key) }

        var rejected = false
        var anySuccess = false
        var anyFailure = false
        var polled: Set<String> = []

        pass: do {
            if snapshot.login == nil {
                do {
                    snapshot.login = try await client.user()
                } catch let error as GitHubError {
                    switch error {
                    case .unauthorized: rejected = true
                    case .rateLimited(let until): snapshot.backoffUntil = until; anyFailure = true
                    default: anyFailure = true
                    }
                    break pass
                } catch {
                    anyFailure = true
                    break pass
                }
            }

            for repo in repos {
                let key = repo.lowercased()
                do {
                    switch try await client.runs(repo: repo, etag: snapshot.cache[key]?.etag) {
                    case .notModified:
                        if snapshot.cache[key] == nil { snapshot.cache[key] = RepoCache(etag: nil, runs: []) }
                    case .runs(let runs, let etag):
                        snapshot.cache[key] = RepoCache(etag: etag, runs: runs)
                    }
                    anySuccess = true
                    polled.insert(key)
                } catch GitHubError.unauthorized {
                    rejected = true
                    break pass
                } catch GitHubError.rateLimited(let until) {
                    snapshot.backoffUntil = until
                    anyFailure = true
                    break pass
                } catch {
                    anyFailure = true  // this repo keeps its last data; the others carry on
                }
            }
        }

        if rejected {
            withLock { s in
                s = State(token: token.value, login: snapshot.login, client: client,
                          status: .unavailable(reason: "GitHub token rejected"), peeks: s.peeks)
            }
            return
        }

        if anySuccess { snapshot.lastSuccess = time }
        if anyFailure && !anySuccess {
            snapshot.status = .stale(since: snapshot.lastSuccess ?? time)
        } else {
            snapshot.status = .ok
        }

        // Regroup from the cache so a failed repo keeps its last builds.
        var builds: [GitHubBuild] = []
        for repo in repos {
            guard let cache = snapshot.cache[repo.lowercased()] else { continue }
            builds += GitHubBuild.group(cache.runs, repo: repo, login: snapshot.login, now: time)
        }
        builds.sort { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }

        var events: [PeekEvent] = []
        for build in builds.sorted(by: { $0.id < $1.id }) {
            let key = build.repo.lowercased()
            // Only repos polled before this poll have a baseline to compare with.
            guard let before = snapshot.previous[key] else { continue }
            if let event = peek(for: build, previous: before[build.id]) { events.append(event) }
        }
        for repo in polled {
            snapshot.previous[repo] = Dictionary(
                builds.filter { $0.repo.lowercased() == repo }.map { ($0.id, $0.state) },
                uniquingKeysWith: { _, new in new })
        }
        snapshot.builds = builds

        let continuation = withLock { s -> AsyncStream<PeekEvent>.Continuation? in
            snapshot.peeks = s.peeks
            s = snapshot
            return s.peeks
        }
        for event in events { continuation?.yield(event) }
    }

    /// 15 s while any watched build is running, else 60 s.
    public func pollInterval(at now: Date) -> TimeInterval {
        builds(at: now).contains { $0.state == .running } ? Self.activeInterval : Self.idleInterval
    }

    // MARK: - Builds

    /// Builds updated within 24 h, newest first.
    public func builds(at now: Date) -> [GitHubBuild] {
        withLock { $0.builds }.filter { now.timeIntervalSince($0.updatedAt) < GitHubBuild.window }
    }

    // MARK: - Collapsed activity

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        guard status.isAvailable else { return nil }
        let all = builds(at: now)
        let running = all.filter { $0.state == .running }
        if let first = running.first {
            let extra = running.count - 1
            return LiveActivity(
                id: "github", moduleID: id, source: .other,
                text: running.count == 1 ? "CI running" : "\(running.count) CI running",
                accessibilityLabel: label(first, "running") + (extra > 0 ? ", plus \(extra) more running" : ""))
        }
        if let failed = all.first(where: {
            $0.state == .failed && now.timeIntervalSince($0.finishedAt ?? $0.updatedAt) < Self.failedWingWindow
        }) {
            return LiveActivity(id: "github", moduleID: id, source: .other,
                                text: "CI failed", accessibilityLabel: label(failed, "failed"))
        }
        if let passed = all.first(where: {
            $0.state == .passed && $0.isMine && now.timeIntervalSince($0.finishedAt ?? $0.updatedAt) < Self.passedWingWindow
        }) {
            return LiveActivity(id: "github", moduleID: id, source: .other,
                                text: "CI passed", accessibilityLabel: label(passed, "passed"))
        }
        return nil
    }

    public func accessibilitySummary() -> String {
        (try? collapsedActivity(at: now()))?.accessibilityLabel ?? "GitHub Actions, no recent activity"
    }

    private func label(_ build: GitHubBuild, _ word: String) -> String {
        "GitHub Actions, " + [build.repoName, build.branch, word].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: - Peeks

    /// One consumer at a time, like `AIUsageModule`.
    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
            continuation.onTermination = { [weak self] _ in self?.withLock { $0.peeks = nil } }
        }
    }

    private func peek(for build: GitHubBuild, previous: GitHubBuild.State?) -> PeekEvent? {
        switch build.state {
        case .failed where previous != .failed:
            var parts = [build.repoName]
            if let pr = build.prNumber {
                parts.append("PR #\(pr)")
            } else if let branch = build.branch {
                parts.append(branch)
            }
            if build.failedWorkflows.count > 1 {
                parts.append("\(build.failedWorkflows.count) workflows")
            } else if build.prNumber == nil, let name = build.failedWorkflows.first {
                parts.append(name)
            }
            return PeekEvent(id: "github.failed.\(build.repo).\(build.sha)", moduleID: id,
                             title: "CI failed", message: parts.joined(separator: " · "))
        case .passed where previous != .passed:
            guard build.isMine, let start = build.startedAt, let end = build.finishedAt else { return nil }
            let elapsed = end.timeIntervalSince(start)
            guard elapsed >= Self.passedPeekThreshold else { return nil }
            let place = build.prNumber.map { "PR #\($0)" } ?? build.branch
            let message = ([build.repoName] + [place].compactMap { $0 } + [AgentStatusModule.peekElapsed(elapsed)])
                .joined(separator: " · ")
            return PeekEvent(id: "github.passed.\(build.repo).\(build.sha)", moduleID: id,
                             title: "CI passed", message: message)
        default:
            return nil
        }
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
