import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import UfuqCore

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private let now0 = utc("2026-11-27T10:00:00Z")

private func fixtureRuns() throws -> [GitHubRun] {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/github/runs", withExtension: "json"))
    return try GitHubRunsResponse.decode(try Data(contentsOf: url)).workflowRuns
}

private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

/// One run as the API shapes it.
private func runJSON(id: Int, name: String = "Mac app", branch: String = "main", sha: String = "s1",
                     event: String = "push", status: String = "completed", conclusion: String? = "success",
                     started: String = "2026-11-27T09:50:00Z", updated: String = "2026-11-27T09:55:00Z",
                     pr: Int? = nil, actor: String = "me") -> String {
    let c = conclusion.map { "\"\($0)\"" } ?? "null"
    let p = pr.map { "[{\"number\":\($0)}]" } ?? "[]"
    return """
    {"id":\(id),"name":"\(name)","head_branch":"\(branch)","head_sha":"\(sha)","event":"\(event)","status":"\(status)",
    "conclusion":\(c),"html_url":"https://github.com/o/r/actions/runs/\(id)","run_started_at":"\(started)",
    "updated_at":"\(updated)","pull_requests":\(p),"actor":{"login":"\(actor)"},"triggering_actor":{"login":"\(actor)"}}
    """
}

private func runsBody(_ runs: [String]) -> Data {
    Data("{\"total_count\":\(runs.count),\"workflow_runs\":[\(runs.joined(separator: ","))]}".utf8)
}

// MARK: - Grouping

final class GitHubBuildTests: XCTestCase {
    func testDecodesRealisticShape() throws {
        let runs = try fixtureRuns()
        XCTAssertEqual(runs.count, 8)
        XCTAssertEqual(runs[2].name, "Mac app")
        XCTAssertEqual(runs[2].headSha.prefix(7), "38350dc")
        XCTAssertEqual(runs[3].pullRequests.first?.number, 12)
        XCTAssertEqual(runs[2].triggeringActor?.login, "me")
        XCTAssertEqual(runs[2].runStartedAt, utc("2026-11-27T09:42:07Z"))
    }

    func testGroupingRules() throws {
        let builds = GitHubBuild.group(try fixtureRuns(), repo: "o/ufuq", login: "me", now: now0)
        // Cancelled-only and >24 h builds are hidden; newest first.
        XCTAssertEqual(builds.map(\.state), [.running, .failed, .passed])
        XCTAssertEqual(builds.map(\.sha), ["eee5555", String(builds[1].sha), "bbb2222"])

        let running = builds[0]
        XCTAssertEqual(running.workflowCount, 2)
        XCTAssertNil(running.finishedAt)
        XCTAssertFalse(running.isMine)
        XCTAssertEqual(running.repoName, "ufuq")
        XCTAssertEqual(running.startedAt, utc("2026-11-27T09:57:00Z"))

        let failed = builds[1]
        XCTAssertEqual(failed.workflowCount, 3)
        XCTAssertEqual(failed.failedWorkflows, ["Mac app"])
        XCTAssertEqual(failed.url, "https://github.com/o/r/actions/runs/45975889338")
        XCTAssertEqual(failed.startedAt, utc("2026-11-27T09:42:07Z"))
        XCTAssertEqual(failed.finishedAt, utc("2026-11-27T09:49:17Z"))
        XCTAssertEqual(failed.branch, "main")
        XCTAssertNil(failed.prNumber)
        XCTAssertTrue(failed.isMine)

        let pr = builds[2]
        XCTAssertEqual(pr.prNumber, 12)
        XCTAssertEqual(pr.branch, "feat/x")
        XCTAssertEqual(pr.state, .passed)
    }

    func testIsMineNeedsLoginAndSameShaDifferentEventSplits() {
        let t = utc("2026-11-27T09:00:00Z")
        let push = GitHubRun(id: 1, headSha: "x", event: "push", conclusion: "success", updatedAt: t, actor: .init(login: "Me"))
        let pr = GitHubRun(id: 2, headSha: "x", event: "pull_request", conclusion: "success", updatedAt: t,
                           triggeringActor: .init(login: "me"))
        let builds = GitHubBuild.group([push, pr], repo: "o/r", login: "me", now: now0)
        XCTAssertEqual(builds.count, 2)
        XCTAssertTrue(builds.allSatisfy(\.isMine))
        XCTAssertTrue(GitHubBuild.group([push], repo: "o/r", login: nil, now: now0).allSatisfy { !$0.isMine })
    }

    func testStatesAndWindowEdge() {
        let t = utc("2026-11-27T09:00:00Z")
        func state(_ status: String, _ conclusion: String?) -> GitHubBuild.State? {
            GitHubBuild.group([GitHubRun(id: 1, headSha: "x", event: "push", status: status, conclusion: conclusion, updatedAt: t)],
                              repo: "o/r", login: nil, now: now0).first?.state
        }
        XCTAssertEqual(state("waiting", nil), .running)
        XCTAssertEqual(state("pending", nil), .running)
        XCTAssertEqual(state("completed", "timed_out"), .failed)
        XCTAssertEqual(state("completed", "startup_failure"), .failed)
        XCTAssertEqual(state("completed", "action_required"), .failed)
        XCTAssertEqual(state("completed", "skipped"), .passed)
        XCTAssertEqual(state("completed", "neutral"), .passed)
        XCTAssertNil(state("completed", "cancelled"))
        // Running beats failed; failed beats passed; cancelled next to success still passes.
        let mixed = [GitHubRun(id: 1, headSha: "x", event: "push", conclusion: "failure", updatedAt: t),
                     GitHubRun(id: 2, headSha: "x", event: "push", status: "in_progress", updatedAt: t)]
        XCTAssertEqual(GitHubBuild.group(mixed, repo: "o/r", login: nil, now: now0).first?.state, .running)
        let okCancelled = [GitHubRun(id: 1, headSha: "x", event: "push", conclusion: "cancelled", updatedAt: t),
                           GitHubRun(id: 2, headSha: "x", event: "push", conclusion: "success", updatedAt: t)]
        XCTAssertEqual(GitHubBuild.group(okCancelled, repo: "o/r", login: nil, now: now0).first?.state, .passed)
        // Exactly 24 h old is out.
        let old = GitHubRun(id: 3, headSha: "y", event: "push", conclusion: "success", updatedAt: now0.addingTimeInterval(-24 * 3600))
        XCTAssertTrue(GitHubBuild.group([old], repo: "o/r", login: nil, now: now0).isEmpty)
    }
}

// MARK: - Git remote

final class GitRemoteTests: XCTestCase {
    private func config(_ url: String) -> String {
        "[core]\n\trepositoryformatversion = 0\n[remote \"upstream\"]\n\turl = https://github.com/other/thing.git\n[remote \"origin\"]\n\turl = \(url)\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n"
    }

    func testThreeUrlForms() {
        for url in ["git@github.com:hystericmoon/ufuq.git", "git@github.com:hystericmoon/ufuq",
                    "https://github.com/hystericmoon/ufuq.git", "https://github.com/hystericmoon/ufuq",
                    "https://github.com/hystericmoon/ufuq/", "ssh://git@github.com/hystericmoon/ufuq.git",
                    "https://user@github.com/hystericmoon/ufuq.git"] {
            XCTAssertEqual(GitRemote.parseGitHubRepo(fromConfig: config(url)), "hystericmoon/ufuq", url)
        }
    }

    func testNonGitHubAndMissingOrigin() {
        XCTAssertNil(GitRemote.parseGitHubRepo(fromConfig: config("git@gitlab.com:o/r.git")))
        XCTAssertNil(GitRemote.parseGitHubRepo(fromConfig: config("https://example.com/github.com/o/r.git")))
        XCTAssertNil(GitRemote.parseGitHubRepo(fromConfig: config("https://github.com/onlyowner")))
        XCTAssertNil(GitRemote.parseGitHubRepo(fromConfig: "[remote \"upstream\"]\n\turl = https://github.com/o/r.git\n"))
        XCTAssertNil(GitRemote.parseGitHubRepo(fromConfig: ""))
    }

    func testWalksUpFromSubdirectory() {
        let fs = InMemoryFileSource(strings: ["/Users/x/ufuq/.git/config": config("git@github.com:o/ufuq.git"),
                                              "/Users/x/ufuq/README.md": "hi"])
        XCTAssertEqual(GitRemote.repo(forDirectory: "/Users/x/ufuq", fileSource: fs), "o/ufuq")
        XCTAssertEqual(GitRemote.repo(forDirectory: "/Users/x/ufuq/UfuqCore/Sources", fileSource: fs), "o/ufuq")
        XCTAssertNil(GitRemote.repo(forDirectory: "/Users/x/other", fileSource: fs))
    }

    func testWorktreeFileWithCommondir() {
        let fs = InMemoryFileSource(strings: [
            "/Users/x/wt/.git": "gitdir: /Users/x/ufuq/.git/worktrees/wt\n",
            "/Users/x/ufuq/.git/worktrees/wt/commondir": "../..\n",
            "/Users/x/ufuq/.git/config": config("https://github.com/o/ufuq.git"),
        ])
        XCTAssertEqual(GitRemote.repo(forDirectory: "/Users/x/wt/sub", fileSource: fs), "o/ufuq")
    }

    func testWorktreeFileWithoutCommondirAndRelativeGitdir() {
        let fs = InMemoryFileSource(strings: [
            "/Users/x/wt/.git": "gitdir: ../ufuq/.git/worktrees/wt\n",
            "/Users/x/ufuq/.git/config": config("https://github.com/o/ufuq.git"),
            "/Users/x/ufuq/.git/worktrees/wt/HEAD": "ref: refs/heads/x\n",
        ])
        XCTAssertEqual(GitRemote.repo(forDirectory: "/Users/x/wt", fileSource: fs), "o/ufuq")
    }
}

// MARK: - Fake transport

private final class FakeTransport: @unchecked Sendable {
    struct Reply {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
        var error: Error?
    }

    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var routes: [String: [Reply]] = [:]

    /// Replies for a path (and query-less), consumed in order; the last one repeats.
    func set(_ path: String, _ replies: Reply...) { lock.lock(); routes[path] = replies; lock.unlock() }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var paths: [String] { requests.compactMap { $0.url?.path } }

    var transport: GitHubClient.Transport {
        { [self] request in
            let reply: Reply = {
                lock.lock(); defer { lock.unlock() }
                _requests.append(request)
                let path = request.url?.path ?? ""
                guard var list = routes[path], !list.isEmpty else { return Reply(status: 404) }
                let first = list[0]
                if list.count > 1 { list.removeFirst(); routes[path] = list }
                return first
            }()
            if let error = reply.error { throw error }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            return (reply.body, response)
        }
    }
}

private struct Offline: Error {}

// MARK: - Client

final class GitHubClientTests: XCTestCase {
    func testRunsRequestHeadersAndEtag() async throws {
        let fake = FakeTransport()
        fake.set("/repos/o/r/actions/runs",
                 .init(status: 200, headers: ["ETag": "W/\"abc\""], body: runsBody([runJSON(id: 1)])))
        let client = GitHubClient(token: "tok", transport: fake.transport)
        let result = try await client.runs(repo: "o/r", etag: "W/\"old\"")
        guard case .runs(let runs, let etag) = result else { return XCTFail("expected runs") }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(etag, "W/\"abc\"")
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/o/r/actions/runs?per_page=20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "W/\"old\"")
    }

    func testNoIfNoneMatchWithoutEtag() async throws {
        let fake = FakeTransport()
        fake.set("/repos/o/r/actions/runs", .init(status: 200, body: runsBody([])))
        _ = try await GitHubClient(token: "t", transport: fake.transport).runs(repo: "o/r", etag: nil)
        XCTAssertNil(fake.requests[0].value(forHTTPHeaderField: "If-None-Match"))
    }

    func testNotModified() async throws {
        let fake = FakeTransport()
        fake.set("/repos/o/r/actions/runs", .init(status: 304))
        let result = try await GitHubClient(token: "t", transport: fake.transport).runs(repo: "o/r", etag: "x")
        XCTAssertEqual(result, .notModified)
    }

    func testErrorMapping() async throws {
        func error(_ reply: FakeTransport.Reply) async -> GitHubError? {
            let fake = FakeTransport()
            fake.set("/repos/o/r/actions/runs", reply)
            let client = GitHubClient(token: "t", transport: fake.transport, now: { now0 })
            do { _ = try await client.runs(repo: "o/r"); return nil } catch { return error as? GitHubError }
        }
        let reset = Int(now0.timeIntervalSince1970) + 600
        let e401 = await error(.init(status: 401))
        let e403 = await error(.init(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(reset)"]))
        let e429 = await error(.init(status: 429, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(reset)"]))
        let e403plain = await error(.init(status: 403, headers: ["x-ratelimit-remaining": "42"]))
        let e500 = await error(.init(status: 500))
        let eBody = await error(.init(status: 200, body: Data("nope".utf8)))
        XCTAssertEqual(e401, .unauthorized)
        XCTAssertEqual(e403, .rateLimited(until: now0.addingTimeInterval(600)))
        XCTAssertEqual(e429, .rateLimited(until: now0.addingTimeInterval(600)))
        XCTAssertEqual(e403plain, .http(403))
        XCTAssertEqual(e500, .http(500))
        XCTAssertEqual(eBody, .invalidResponse)
    }

    func testUserAndRepoExistsAndBadRepo() async throws {
        let fake = FakeTransport()
        fake.set("/user", .init(status: 200, body: Data(#"{"login":"me","id":1}"#.utf8)))
        fake.set("/repos/o/r", .init(status: 200, body: Data("{}".utf8)))
        fake.set("/repos/o/gone", .init(status: 404))
        let client = GitHubClient(token: "t", transport: fake.transport)
        let login = try await client.user()
        XCTAssertEqual(login, "me")
        let exists = try await client.repoExists("o/r")
        XCTAssertTrue(exists)
        let gone = try await client.repoExists("o/gone")
        XCTAssertFalse(gone)
        do { _ = try await client.repoExists("o/r/../x"); XCTFail("should reject") } catch {
            XCTAssertEqual(error as? GitHubError, .invalidResponse)
        }
    }
}

// MARK: - Token source

final class GitHubTokenSourceTests: XCTestCase {
    private func source(ghExists: Bool, ghResult: (Int32, String)?, file: String?) -> GitHubTokenSource {
        GitHubTokenSource(
            runCommand: { path, args in
                XCTAssertEqual(args, ["auth", "token"])
                return ghResult.map { (status: $0.0, stdout: $0.1) }
            },
            readFile: { $0 == "/tok" ? file : nil },
            fileExists: { ghExists && $0 == "/usr/local/bin/gh" },
            tokenPath: "/tok")
    }

    func testGhWins() {
        let t = source(ghExists: true, ghResult: (0, "gho_abc\n"), file: "ghp_file").token()
        XCTAssertEqual(t?.value, "gho_abc")
        XCTAssertEqual(t?.origin, .gh)
    }

    func testFallsBackToFile() {
        XCTAssertEqual(source(ghExists: false, ghResult: nil, file: " ghp_file \n").token()?.value, "ghp_file")
        XCTAssertEqual(source(ghExists: true, ghResult: (1, ""), file: "ghp_file").token()?.origin, .file)
        XCTAssertEqual(source(ghExists: true, ghResult: (0, "  \n"), file: "ghp_file").token()?.origin, .file)
        XCTAssertEqual(source(ghExists: true, ghResult: nil, file: "ghp_file").token()?.origin, .file)
    }

    func testNeither() {
        XCTAssertNil(source(ghExists: false, ghResult: nil, file: nil).token())
        XCTAssertNil(source(ghExists: true, ghResult: (1, "x"), file: "  \n").token())
    }

    func testDefaultPath() {
        XCTAssertEqual(GitHubTokenSource.defaultTokenPath(home: "/Users/x"), "/Users/x/Library/Application Support/Ufuq/github-token")
        XCTAssertEqual(GitHubTokenSource.defaultTokenPath(home: "/Users/x/"), "/Users/x/Library/Application Support/Ufuq/github-token")
    }
}

// MARK: - Module

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Date
    init(_ t: Date) { self.t = t }
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func set(_ d: Date) { lock.lock(); t = d; lock.unlock() }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.lock(); defer { lock.unlock() }; return v } set { lock.lock(); v = newValue; lock.unlock() } }
}

final class GitHubActionsModuleTests: XCTestCase {
    private let clock = Clock(now0)
    private let fake = FakeTransport()
    private let token = Box<String?>("tok")
    private let auto = Box<[String]>(["o/r"])
    private let manual = Box<[String]>([])

    private func makeModule() -> GitHubActionsModule {
        let tokenBox = token
        let source = GitHubTokenSource(runCommand: { _, _ in nil }, readFile: { _ in tokenBox.value },
                                       fileExists: { _ in false }, tokenPath: "/tok")
        let transport = fake.transport
        let clock = clock
        let auto = auto, manual = manual
        fake.set("/user", .init(status: 200, body: Data(#"{"login":"me"}"#.utf8)))
        return GitHubActionsModule(
            tokenSource: source,
            makeClient: { GitHubClient(token: $0, transport: transport, now: { clock.now }) },
            autoRepos: { auto.value }, manualRepos: { manual.value }, now: { clock.now })
    }

    private func setRuns(_ runs: [String], repo: String = "o/r", etag: String? = nil) {
        fake.set("/repos/\(repo)/actions/runs",
                 .init(status: 200, headers: etag.map { ["ETag": $0] } ?? [:], body: runsBody(runs)))
    }

    private func collect(_ module: GitHubActionsModule) -> Box<[PeekEvent]> {
        let got = Box<[PeekEvent]>([])
        let stream = module.peekEvents()
        Task { for await e in stream { got.value += [e] } }
        return got
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    func testFirstPollNoPeeksThenFailedPeekWithWorkflow() async throws {
        let module = makeModule()
        let peeks = collect(module)
        setRuns([runJSON(id: 1, name: "Mac app", status: "in_progress", conclusion: nil)])
        try await module.refresh()
        setRuns([runJSON(id: 1, name: "Mac app", conclusion: "failure")])
        try await module.refresh()
        await settle()
        XCTAssertEqual(peeks.value.count, 1)
        let peek = try XCTUnwrap(peeks.value.first)
        XCTAssertEqual(peek.title, "CI failed")
        XCTAssertEqual(peek.message, "r · main · Mac app")
        XCTAssertEqual(peek.id, "github.failed.o/r.s1")
        XCTAssertEqual(peek.priority, .normal)
        try await module.refresh()  // unchanged: no repeat
        await settle()
        XCTAssertEqual(peeks.value.count, 1)
    }

    func testFirstPollAlreadyFailedMakesNoPeek() async throws {
        let module = makeModule()
        let peeks = collect(module)
        setRuns([runJSON(id: 1, conclusion: "failure")])
        try await module.refresh()
        try await module.refresh()
        await settle()
        XCTAssertTrue(peeks.value.isEmpty)
    }

    func testFailedPeekPrAndMultipleWorkflows() async throws {
        let module = makeModule()
        let peeks = collect(module)
        setRuns([runJSON(id: 1, event: "pull_request", status: "in_progress", conclusion: nil, pr: 12),
                 runJSON(id: 3, name: "Core", sha: "s2", status: "in_progress", conclusion: nil)])
        try await module.refresh()
        setRuns([runJSON(id: 1, event: "pull_request", conclusion: "failure", pr: 12),
                 runJSON(id: 2, name: "Core", event: "pull_request", conclusion: "failure", pr: 12),
                 runJSON(id: 3, name: "Core", sha: "s2", conclusion: "failure"),
                 runJSON(id: 4, name: "Mac app", sha: "s2", conclusion: "failure")])
        try await module.refresh()
        await settle()
        let messages = peeks.value.map(\.message).sorted()
        XCTAssertEqual(messages, ["r · PR #12 · 2 workflows", "r · main · 2 workflows"])
    }

    func testPassedPeekOnlyWhenMineAndLongEnough() async throws {
        let module = makeModule()
        let peeks = collect(module)
        setRuns([runJSON(id: 1, sha: "mine", status: "in_progress", conclusion: nil, started: "2026-11-27T09:50:00Z"),
                 runJSON(id: 2, sha: "theirs", status: "in_progress", conclusion: nil, actor: "other"),
                 runJSON(id: 3, sha: "quick", status: "in_progress", conclusion: nil, started: "2026-11-27T09:54:30Z")])
        try await module.refresh()
        setRuns([runJSON(id: 1, sha: "mine", started: "2026-11-27T09:50:00Z", updated: "2026-11-27T09:53:40Z", pr: 12),
                 runJSON(id: 2, sha: "theirs", actor: "other"),
                 runJSON(id: 3, sha: "quick", started: "2026-11-27T09:54:30Z", updated: "2026-11-27T09:55:15Z")])
        try await module.refresh()
        await settle()
        XCTAssertEqual(peeks.value.count, 1)
        XCTAssertEqual(peeks.value[0].title, "CI passed")
        XCTAssertEqual(peeks.value[0].message, "r · PR #12 · 3m 40s")
        XCTAssertEqual(peeks.value[0].id, "github.passed.o/r.mine")
    }

    func testNewRepoGetsNoPeekOnItsFirstPoll() async throws {
        let module = makeModule()
        let peeks = collect(module)
        setRuns([runJSON(id: 1, conclusion: "success")])
        try await module.refresh()
        auto.value = ["o/r", "o/new"]
        setRuns([runJSON(id: 9, conclusion: "failure")], repo: "o/new")
        try await module.refresh()
        await settle()
        XCTAssertTrue(peeks.value.isEmpty)
        XCTAssertEqual(module.builds(at: now0).count, 2)
    }

    func testCollapsedTextsAndPriority() async throws {
        let module = makeModule()
        setRuns([runJSON(id: 1, sha: "run", status: "in_progress", conclusion: nil),
                 runJSON(id: 2, sha: "bad", conclusion: "failure", updated: "2026-11-27T09:55:00Z"),
                 runJSON(id: 3, sha: "ok", conclusion: "success", updated: "2026-11-27T09:57:00Z")])
        try await module.refresh()
        var a = try XCTUnwrap(module.collapsedActivity(at: now0))
        XCTAssertEqual(a.text, "CI running")
        XCTAssertEqual(a.id, "github")
        XCTAssertEqual(a.moduleID, "github")
        XCTAssertEqual(a.source, .other)
        XCTAssertFalse(a.isAlert)
        XCTAssertEqual(a.accessibilityLabel, "GitHub Actions, r, main, running")

        setRuns([runJSON(id: 1, sha: "run", status: "in_progress", conclusion: nil),
                 runJSON(id: 4, sha: "run2", status: "queued", conclusion: nil)])
        try await module.refresh()
        a = try XCTUnwrap(module.collapsedActivity(at: now0))
        XCTAssertEqual(a.text, "2 CI running")

        setRuns([runJSON(id: 2, sha: "bad", conclusion: "failure", updated: "2026-11-27T09:55:00Z"),
                 runJSON(id: 3, sha: "ok", conclusion: "success", updated: "2026-11-27T09:57:00Z")])
        try await module.refresh()
        a = try XCTUnwrap(module.collapsedActivity(at: now0))
        XCTAssertEqual(a.text, "CI failed")
        XCTAssertEqual(a.accessibilityLabel, "GitHub Actions, r, main, failed")
        // The failure (finished 09:55) leaves the wing after 10 minutes.
        XCTAssertEqual(try module.collapsedActivity(at: utc("2026-11-27T10:04:59Z"))?.text, "CI failed")
        XCTAssertNil(try module.collapsedActivity(at: utc("2026-11-27T10:05:00Z")))
        // Mine, passed 09:57: shown for 5 minutes only.
        setRuns([runJSON(id: 3, sha: "ok", conclusion: "success", updated: "2026-11-27T09:57:00Z")])
        try await module.refresh()
        XCTAssertEqual(try module.collapsedActivity(at: utc("2026-11-27T10:01:59Z"))?.text, "CI passed")
        XCTAssertNil(try module.collapsedActivity(at: utc("2026-11-27T10:02:00Z")))
        setRuns([runJSON(id: 2, sha: "bad", conclusion: "failure", updated: "2026-11-27T09:55:00Z")])
        try await module.refresh()
        XCTAssertEqual(module.accessibilitySummary(), "GitHub Actions, r, main, failed")
    }

    func testPassedNotMineNotShown() async throws {
        let module = makeModule()
        setRuns([runJSON(id: 1, conclusion: "success", updated: "2026-11-27T09:58:00Z", actor: "other")])
        try await module.refresh()
        XCTAssertNil(try module.collapsedActivity(at: now0))
    }

    func testPollInterval() async throws {
        let module = makeModule()
        setRuns([runJSON(id: 1, status: "in_progress", conclusion: nil)])
        try await module.refresh()
        XCTAssertEqual(module.pollInterval(at: now0), 15)
        setRuns([runJSON(id: 1, conclusion: "success")])
        try await module.refresh()
        XCTAssertEqual(module.pollInterval(at: now0), 60)
    }

    func testStaleOnNetworkErrorKeepsData() async throws {
        let module = makeModule()
        setRuns([runJSON(id: 1, conclusion: "failure")])
        try await module.refresh()
        XCTAssertEqual(module.status, .ok)
        fake.set("/repos/o/r/actions/runs", .init(status: 200, error: Offline()))
        clock.set(now0.addingTimeInterval(60))
        try await module.refresh()
        XCTAssertEqual(module.status, .stale(since: now0))
        XCTAssertEqual(module.builds(at: clock.now).count, 1)
        setRuns([runJSON(id: 1, conclusion: "failure")])
        try await module.refresh()
        XCTAssertEqual(module.status, .ok)
    }

    func testUnavailableOn401AndWithoutToken() async throws {
        let module = makeModule()
        fake.set("/repos/o/r/actions/runs", .init(status: 401))
        try await module.refresh()
        XCTAssertEqual(module.status, .unavailable(reason: "GitHub token rejected"))
        XCTAssertTrue(module.builds(at: now0).isEmpty)
        XCTAssertNil(try module.collapsedActivity(at: now0))

        token.value = nil
        try await module.refresh()
        XCTAssertEqual(module.status, .unavailable(reason: "No GitHub token"))
    }

    func testLoginFetchedOncePerToken() async throws {
        let module = makeModule()
        setRuns([runJSON(id: 1)])
        try await module.refresh()
        try await module.refresh()
        XCTAssertEqual(fake.paths.filter { $0 == "/user" }.count, 1)
        token.value = "other"
        try await module.refresh()
        XCTAssertEqual(fake.paths.filter { $0 == "/user" }.count, 2)
    }

    func testTokenChangeSuppressesPeeks() async throws {
        let module = makeModule()
        let peeks = collect(module)
        setRuns([runJSON(id: 1, status: "in_progress", conclusion: nil)])
        try await module.refresh()
        token.value = "new"
        setRuns([runJSON(id: 1, conclusion: "failure")])
        try await module.refresh()
        await settle()
        XCTAssertTrue(peeks.value.isEmpty)
    }

    func testOneRepoFailingDoesNotHideOthers() async throws {
        let module = makeModule()
        auto.value = ["o/r", "o/bad"]
        setRuns([runJSON(id: 1, conclusion: "failure")])
        fake.set("/repos/o/bad/actions/runs", .init(status: 500))
        try await module.refresh()
        XCTAssertEqual(module.status, .ok)
        XCTAssertEqual(module.builds(at: now0).map(\.repo), ["o/r"])
    }

    func testMaxTenReposManualFirstDedupedCaseInsensitively() async throws {
        let module = makeModule()
        manual.value = ["m/one", "O/R"]
        auto.value = (1...12).map { "a/r\($0)" } + ["o/r"]
        let repos = module.watchedRepos()
        XCTAssertEqual(repos.count, 10)
        XCTAssertEqual(Array(repos.prefix(3)), ["m/one", "O/R", "a/r1"])
        XCTAssertFalse(repos.contains("o/r"))
        for repo in repos { fake.set("/repos/\(repo)/actions/runs", .init(status: 200, body: runsBody([]))) }
        try await module.refresh()
        XCTAssertEqual(fake.paths.filter { $0.hasSuffix("/actions/runs") }.count, 10)
    }

    func testEtagSentAndNotModifiedKeepsData() async throws {
        let module = makeModule()
        setRuns([runJSON(id: 1, conclusion: "failure")], etag: "W/\"1\"")
        try await module.refresh()
        fake.set("/repos/o/r/actions/runs", .init(status: 304))
        try await module.refresh()
        let runRequests = fake.requests.filter { $0.url?.path.hasSuffix("/actions/runs") == true }
        XCTAssertNil(runRequests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(runRequests[1].value(forHTTPHeaderField: "If-None-Match"), "W/\"1\"")
        XCTAssertEqual(module.builds(at: now0).count, 1)
        XCTAssertEqual(module.status, .ok)
    }

    func testRateLimitBackoffSkipsPolls() async throws {
        let module = makeModule()
        let reset = Int(now0.timeIntervalSince1970) + 300
        fake.set("/repos/o/r/actions/runs",
                 .init(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(reset)"]),
                 .init(status: 200, body: runsBody([runJSON(id: 1, conclusion: "failure")])))
        try await module.refresh()
        let after1 = fake.paths.filter { $0.hasSuffix("/actions/runs") }.count
        clock.set(now0.addingTimeInterval(120))
        try await module.refresh()  // still backing off
        XCTAssertEqual(fake.paths.filter { $0.hasSuffix("/actions/runs") }.count, after1)
        clock.set(now0.addingTimeInterval(301))
        try await module.refresh()
        XCTAssertEqual(fake.paths.filter { $0.hasSuffix("/actions/runs") }.count, after1 + 1)
        XCTAssertEqual(module.builds(at: clock.now).count, 1)
    }
}
