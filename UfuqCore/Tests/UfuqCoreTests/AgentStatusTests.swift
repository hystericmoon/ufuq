import XCTest
@testable import UfuqCore

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/agents/\(name)", withExtension: "json"))
    return try Data(contentsOf: url)
}

private func event(_ name: String) throws -> AgentHookEvent {
    try XCTUnwrap(AgentHookEvent.parse(try fixture(name)))
}

private func makeSession(_ state: AgentSessionState, id: String = "abc123", title: String = "ufuq",
                     updatedAt: Date, runningSince: Date? = nil, finishedAt: Date? = nil) -> AgentSession {
    AgentSession(id: id, title: title, cwd: "/Users/x/\(title)", state: state, updatedAt: updatedAt,
                 runningSince: runningSince, finishedAt: finishedAt)
}

// MARK: - Event parsing and state machine

final class AgentStateMachineTests: XCTestCase {
    private let t0 = utc("2026-11-27T10:00:00Z")
    private let t1 = utc("2026-11-27T10:05:00Z")

    private func written(_ update: AgentSessionUpdate) throws -> AgentSession {
        guard case .write(let s) = update else { throw XCTSkip("expected write, got \(update)") }
        return s
    }

    func testParseIgnoresUnknownKeysAndRejectsGarbage() throws {
        let e = try event("notification_permission")
        XCTAssertEqual(e.sessionID, "abc123")
        XCTAssertEqual(e.hookEventName, "Notification")
        XCTAssertEqual(e.cwd, "/Users/x/ufuq")
        XCTAssertEqual(e.notificationType, "permission_prompt")
        XCTAssertNil(AgentHookEvent.parse(try fixture("garbage")))
        XCTAssertNil(AgentHookEvent.parse(Data()))
        XCTAssertNil(AgentHookEvent.parse(Data(#"{"hook_event_name":"Stop"}"#.utf8)))
        XCTAssertNil(AgentHookEvent.parse(Data(#"{"session_id":"","hook_event_name":"Stop"}"#.utf8)))
        XCTAssertEqual(try event("subagent_pre_tool_use").agentID, "agent-7")
        XCTAssertEqual(AgentHookEvent.parse(Data(#"{"session_id":"s","hook_event_name":"Stop","session_title":"Fix bug"}"#.utf8))?.sessionTitle, "Fix bug")
    }

    func testSessionStartIsIdle() throws {
        let s = try written(AgentStateMachine.apply(try event("session_start"), to: nil, now: t0, appBundleID: "com.apple.Terminal"))
        XCTAssertEqual(s.state, .idle)
        XCTAssertEqual(s.title, "ufuq")
        XCTAssertEqual(s.cwd, "/Users/x/ufuq")
        XCTAssertEqual(s.appBundleID, "com.apple.Terminal")
        XCTAssertNil(s.runningSince)
    }

    func testUserPromptSubmitStartsRunning() throws {
        let old = makeSession(.done, updatedAt: t0, runningSince: t0, finishedAt: t0)
        let s = try written(AgentStateMachine.apply(try event("user_prompt_submit"), to: old, now: t1, appBundleID: nil))
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.runningSince, t1)
        XCTAssertNil(s.finishedAt)
        XCTAssertEqual(s.updatedAt, t1)
    }

    func testToolEventsKeepOrSetRunningSince() throws {
        for name in ["pre_tool_use", "post_tool_use", "post_tool_use_failure", "subagent_pre_tool_use"] {
            let kept = try written(AgentStateMachine.apply(
                try event(name), to: makeSession(.running, updatedAt: t0, runningSince: t0), now: t1, appBundleID: nil))
            XCTAssertEqual(kept.state, .running, name)
            XCTAssertEqual(kept.runningSince, t0, name)
            let fresh = try written(AgentStateMachine.apply(
                try event(name), to: makeSession(.idle, updatedAt: t0), now: t1, appBundleID: nil))
            XCTAssertEqual(fresh.state, .running, name)
            XCTAssertEqual(fresh.runningSince, t1, name)
            // Unknown session (e.g. after SessionEnd): no ghost.
            XCTAssertEqual(AgentStateMachine.apply(try event(name), to: nil, now: t1, appBundleID: nil), .unchanged, name)
        }
    }

    func testPermissionRequestWaits() throws {
        let s = try written(AgentStateMachine.apply(
            try event("permission_request"), to: makeSession(.running, updatedAt: t0, runningSince: t0), now: t1, appBundleID: nil))
        XCTAssertEqual(s.state, .waiting)
        XCTAssertEqual(s.runningSince, t0)
    }

    func testNotificationTypes() throws {
        let running = makeSession(.running, updatedAt: t0, runningSince: t0)
        for name in ["notification_permission", "notification_elicitation"] {
            let s = try written(AgentStateMachine.apply(try event(name), to: running, now: t1, appBundleID: nil))
            XCTAssertEqual(s.state, .waiting, name)
        }
        XCTAssertEqual(AgentStateMachine.apply(try event("notification_idle"), to: running, now: t1, appBundleID: nil), .unchanged)
        let noType = AgentHookEvent(sessionID: "abc123", hookEventName: "Notification")
        XCTAssertEqual(AgentStateMachine.apply(noType, to: running, now: t1, appBundleID: nil), .unchanged)
    }

    func testStopAndStopFailureAreDone() throws {
        for name in ["stop", "stop_failure"] {
            let s = try written(AgentStateMachine.apply(
                try event(name), to: makeSession(.running, updatedAt: t0, runningSince: t0), now: t1, appBundleID: nil))
            XCTAssertEqual(s.state, .done, name)
            XCTAssertEqual(s.finishedAt, t1, name)
            XCTAssertEqual(s.runningSince, t0, name)
        }
    }

    func testSessionEndDeletes() throws {
        XCTAssertEqual(AgentStateMachine.apply(try event("session_end"), to: makeSession(.done, updatedAt: t0), now: t1, appBundleID: nil), .delete)
        XCTAssertEqual(AgentStateMachine.apply(try event("session_end"), to: nil, now: t1, appBundleID: nil), .delete)
    }

    func testUnknownEventIsUnchanged() throws {
        XCTAssertEqual(AgentStateMachine.apply(try event("unknown_event"), to: nil, now: t1, appBundleID: nil), .unchanged)
    }

    func testTitleFromSessionTitleKeptAcrossEvents() throws {
        let first = AgentHookEvent(sessionID: "s", hookEventName: "UserPromptSubmit", cwd: "/a/proj", sessionTitle: "Fix login")
        let s1 = try written(AgentStateMachine.apply(first, to: nil, now: t0, appBundleID: nil))
        XCTAssertEqual(s1.title, "Fix login")
        let next = AgentHookEvent(sessionID: "s", hookEventName: "PreToolUse", cwd: "/a/proj")
        let s2 = try written(AgentStateMachine.apply(next, to: s1, now: t1, appBundleID: nil))
        XCTAssertEqual(s2.title, "Fix login")
    }

    func testFullTurnSequence() throws {
        var current: AgentSession?
        var now = t0
        func step(_ name: String) throws {
            now = now.addingTimeInterval(10)
            switch AgentStateMachine.apply(try event(name), to: current, now: now, appBundleID: nil) {
            case .write(let s): current = s
            case .delete: current = nil
            case .unchanged: break
            }
        }
        try step("session_start");       XCTAssertEqual(current?.state, .idle)
        try step("user_prompt_submit");  XCTAssertEqual(current?.state, .running)
        let started = current?.runningSince
        try step("pre_tool_use");        XCTAssertEqual(current?.state, .running)
        try step("permission_request");  XCTAssertEqual(current?.state, .waiting)
        try step("post_tool_use");       XCTAssertEqual(current?.state, .running)
        XCTAssertEqual(current?.runningSince, started)
        try step("stop");                XCTAssertEqual(current?.state, .done)
        XCTAssertEqual(current?.finishedAt, now)
        try step("session_end");         XCTAssertNil(current)
    }

    func testSessionEncodingIsSortedAndISO8601() throws {
        let s = AgentSession(id: "a", title: "t", cwd: "/c", state: .running, updatedAt: t0, runningSince: t0)
        let text = String(decoding: try s.encoded(), as: UTF8.self)
        XCTAssertEqual(text, #"{"cwd":"\/c","id":"a","runningSince":"2026-11-27T10:00:00Z","state":"running","title":"t","updatedAt":"2026-11-27T10:00:00Z"}"#
            .replacingOccurrences(of: "\\/", with: "/"))
        XCTAssertEqual(try AgentSession.decode(try s.encoded()), s)
    }
}

// MARK: - Store

final class AgentStateStoreTests: XCTestCase {
    private var dir: String!
    private let t0 = utc("2026-11-27T10:00:00Z")

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "ufuq-agents-\(UUID().uuidString)"
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    private var store: AgentStateStore { AgentStateStore(directory: dir) }
    private func path(_ name: String) -> String { dir + "/" + name }

    func testWritesStateFileWithoutPromptText() throws {
        store.apply(stdin: try fixture("user_prompt_submit"), now: t0, environment: ["__CFBundleIdentifier": "com.googlecode.iterm2"])
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path("abc123.json")))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("SECRET"))
        XCTAssertFalse(text.contains("rotate"))
        let s = try AgentSession.decode(data)
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.appBundleID, "com.googlecode.iterm2")
        for name in ["pre_tool_use", "permission_request", "stop"] {
            store.apply(stdin: try fixture(name), now: t0)
        }
        let all = String(decoding: try XCTUnwrap(FileManager.default.contents(atPath: path("abc123.json"))), as: UTF8.self)
        XCTAssertFalse(all.contains("SECRET"))
        XCTAssertTrue(all.contains("com.googlecode.iterm2"))
        XCTAssertEqual(try AgentSession.decode(Data(all.utf8)).state, .done)
    }

    func testSessionEndDeletesFile() throws {
        store.apply(stdin: try fixture("user_prompt_submit"), now: t0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("abc123.json")))
        store.apply(stdin: try fixture("session_end"), now: t0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("abc123.json")))
    }

    func testGarbageAndUnknownLeaveNothing() throws {
        XCTAssertEqual(store.apply(stdin: try fixture("garbage"), now: t0), .unchanged)
        XCTAssertEqual(store.apply(stdin: Data(), now: t0), .unchanged)
        XCTAssertEqual(store.apply(stdin: try fixture("unknown_event"), now: t0), .unchanged)
        XCTAssertEqual(store.apply(stdin: try fixture("notification_idle"), now: t0), .unchanged)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        XCTAssertTrue(files.filter { $0.hasSuffix(".json") }.isEmpty)
    }

    func testCorruptExistingFileIsReplaced() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "garbage".write(toFile: path("abc123.json"), atomically: true, encoding: .utf8)
        store.apply(stdin: try fixture("user_prompt_submit"), now: t0)
        XCTAssertEqual(try AgentSession.decode(try XCTUnwrap(FileManager.default.contents(atPath: path("abc123.json")))).state, .running)
    }

    func testNoTemporaryFilesLeftBehind() throws {
        store.apply(stdin: try fixture("user_prompt_submit"), now: t0)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0 != ".lock" }
        XCTAssertEqual(names, ["abc123.json"])
    }

    func testSessionStartPrunesOldFiles() throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let old = makeSession(.done, id: "old", updatedAt: t0.addingTimeInterval(-25 * 3600))
        let recent = makeSession(.done, id: "recent", updatedAt: t0.addingTimeInterval(-23 * 3600))
        try old.encoded().write(to: URL(fileURLWithPath: path("old.json")))
        try recent.encoded().write(to: URL(fileURLWithPath: path("recent.json")))
        try "garbage".write(toFile: path("junk.json"), atomically: true, encoding: .utf8)
        // A non-SessionStart event does not prune.
        store.apply(stdin: try fixture("user_prompt_submit"), now: t0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("old.json")))
        store.apply(stdin: try fixture("session_start"), now: t0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("old.json")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("recent.json")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path("junk.json")))
    }

    func testFileNameSanitizing() {
        XCTAssertEqual(AgentStateStore.fileName(forSessionID: "abc-1.2_x"), "abc-1.2_x.json")
        XCTAssertEqual(AgentStateStore.fileName(forSessionID: "../etc/passwd"), ".._etc_passwd.json")
        XCTAssertEqual(AgentStateStore.fileName(forSessionID: "a b/ü"), "a_b__.json")
    }

    func testDirectoryResolution() {
        XCTAssertEqual(AgentStateStore.resolveDirectory(environment: ["UFUQ_AGENT_DIR": "/tmp/x"]), "/tmp/x")
        XCTAssertTrue(AgentStateStore.resolveDirectory(environment: [:]).hasSuffix("Ufuq/agents"))
    }

    func testConcurrentWritersKeepFilesValid() throws {
        let data = try fixture("pre_tool_use")
        let s = store
        s.apply(stdin: try fixture("user_prompt_submit"), now: Date())
        DispatchQueue.concurrentPerform(iterations: 40) { _ in s.apply(stdin: data, now: Date()) }
        let read = try XCTUnwrap(FileManager.default.contents(atPath: path("abc123.json")))
        XCTAssertEqual(try AgentSession.decode(read).state, .running)
    }
}

// MARK: - Module

final class AgentStatusModuleTests: XCTestCase {
    private let dir = "/agents"
    private let now = utc("2026-11-27T10:00:00Z")

    private func module(_ sessions: [AgentSession], extra: [String: String] = [:]) async throws -> AgentStatusModule {
        var files: [String: String] = extra
        for s in sessions { files["\(dir)/\(s.id).json"] = String(decoding: try s.encoded(), as: UTF8.self) }
        let m = AgentStatusModule(directory: dir, fileSource: InMemoryFileSource(strings: files))
        try await m.refresh()
        return m
    }

    private func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }

    func testIdentity() {
        let m = AgentStatusModule(directory: dir, fileSource: InMemoryFileSource())
        XCTAssertEqual(m.id, "agent")
        XCTAssertEqual(m.title, "Agents")
    }

    func testMissingDirectoryIsEmptyAndOk() async throws {
        let m = AgentStatusModule(directory: "/definitely/not/here", fileSource: LocalFileSource())
        try await m.refresh()
        XCTAssertEqual(m.status, .ok)
        XCTAssertNil(try m.collapsedActivity(at: now))
        XCTAssertTrue(m.sessions(at: now).isEmpty)
        XCTAssertEqual(m.accessibilitySummary(), "No agents running")
    }

    func testIdleHiddenEverywhere() async throws {
        let m = try await module([makeSession(.idle, updatedAt: ago(10))])
        XCTAssertNil(try m.collapsedActivity(at: now))
        XCTAssertTrue(m.sessions(at: now).isEmpty)
        XCTAssertTrue(m.syncAgents(at: now).isEmpty)
    }

    func testOneRunning() async throws {
        let m = try await module([makeSession(.running, updatedAt: ago(5), runningSince: ago(4 * 60 + 10))])
        let a = try XCTUnwrap(try m.collapsedActivity(at: now))
        XCTAssertEqual(a.id, "agent")
        XCTAssertEqual(a.moduleID, "agent")
        XCTAssertEqual(a.source, .agent)
        XCTAssertEqual(a.text, "ufuq · 4m")
        XCTAssertFalse(a.isAlert)
        XCTAssertEqual(a.accessibilityLabel, "Claude Code, ufuq, running")
    }

    func testThreeRunning() async throws {
        let m = try await module((1...3).map { makeSession(.running, id: "s\($0)", title: "p\($0)", updatedAt: ago(5), runningSince: ago(60)) })
        let a = try XCTUnwrap(try m.collapsedActivity(at: now))
        XCTAssertEqual(a.text, "3 agents running")
        XCTAssertFalse(a.isAlert)
    }

    func testWaitingWinsAndCountsMore() async throws {
        let one = try await module([
            makeSession(.running, id: "r", title: "run", updatedAt: ago(5), runningSince: ago(60)),
            makeSession(.waiting, id: "w1", title: "ufuq", updatedAt: ago(10), runningSince: ago(60)),
        ])
        let a = try XCTUnwrap(try one.collapsedActivity(at: now))
        XCTAssertEqual(a.text, "Needs input · ufuq")
        XCTAssertTrue(a.isAlert)
        XCTAssertEqual(a.accessibilityLabel, "Claude Code, ufuq, needs input")

        let three = try await module([
            makeSession(.waiting, id: "w1", title: "alpha", updatedAt: ago(30)),
            makeSession(.waiting, id: "w2", title: "beta", updatedAt: ago(10)),
            makeSession(.waiting, id: "w3", title: "gamma", updatedAt: ago(20)),
        ])
        let b = try XCTUnwrap(try three.collapsedActivity(at: now))
        XCTAssertEqual(b.text, "Needs input · beta +2")
        XCTAssertTrue(b.isAlert)
    }

    func testDoneShowsFiveMinutesInWingButStaysInTileAndSync() async throws {
        let recent = try await module([makeSession(.done, updatedAt: ago(60), runningSince: ago(300), finishedAt: ago(60))])
        let a = try XCTUnwrap(try recent.collapsedActivity(at: now))
        XCTAssertEqual(a.text, "ufuq done")
        XCTAssertFalse(a.isAlert)
        XCTAssertEqual(a.accessibilityLabel, "Claude Code, ufuq, done")

        let old = try await module([makeSession(.done, updatedAt: ago(6 * 60), runningSince: ago(600), finishedAt: ago(6 * 60))])
        XCTAssertNil(try old.collapsedActivity(at: now))
        XCTAssertEqual(old.sessions(at: now).count, 1)
        XCTAssertEqual(old.syncAgents(at: now).map(\.state), [.done])
    }

    func testSixHourStaleHiddenEverywhere() async throws {
        let m = try await module([
            makeSession(.running, id: "stale", updatedAt: ago(6 * 3600 + 1), runningSince: ago(7 * 3600)),
            makeSession(.done, id: "fresh", updatedAt: ago(5 * 3600), finishedAt: ago(5 * 3600)),
        ])
        XCTAssertNil(try m.collapsedActivity(at: now))
        XCTAssertEqual(m.sessions(at: now).map(\.id), ["fresh"])
        XCTAssertEqual(m.syncAgents(at: now).map(\.id), ["fresh"])
    }

    func testSessionsNewestFirstAndSyncAgents() async throws {
        let m = try await module([
            makeSession(.running, id: "a", title: "A", updatedAt: ago(100), runningSince: ago(100)),
            makeSession(.waiting, id: "b", title: "B", updatedAt: ago(10)),
            makeSession(.idle, id: "c", title: "C", updatedAt: ago(1)),
            makeSession(.done, id: "d", title: "D", updatedAt: ago(50), finishedAt: ago(50)),
        ])
        XCTAssertEqual(m.sessions(at: now).map(\.id), ["b", "d", "a"])
        XCTAssertEqual(m.syncAgents(at: now), [
            SyncAgent(id: "b", title: "B", state: .waiting, updatedAt: ago(10)),
            SyncAgent(id: "d", title: "D", state: .done, updatedAt: ago(50)),
            SyncAgent(id: "a", title: "A", state: .running, updatedAt: ago(100)),
        ])
    }

    func testCorruptFileIsSkipped() async throws {
        let good = makeSession(.running, updatedAt: ago(5), runningSince: ago(120))
        let m = try await module([good], extra: ["\(dir)/broken.json": "not json"])
        XCTAssertEqual(m.status, .ok)
        XCTAssertEqual(m.sessions(at: now).map(\.id), ["abc123"])
    }

    func testElapsedFormats() {
        XCTAssertEqual(AgentStatusModule.wingElapsed(20), "<1m")
        XCTAssertEqual(AgentStatusModule.wingElapsed(59), "<1m")
        XCTAssertEqual(AgentStatusModule.wingElapsed(60), "1m")
        XCTAssertEqual(AgentStatusModule.wingElapsed(250), "4m")
        XCTAssertEqual(AgentStatusModule.wingElapsed(3900), "1h 5m")
        XCTAssertEqual(AgentStatusModule.peekElapsed(45), "45s")
        XCTAssertEqual(AgentStatusModule.peekElapsed(252), "4m 12s")
        XCTAssertEqual(AgentStatusModule.peekElapsed(3900), "1h 5m")
    }

    func testWingElapsedIsShownForLongRun() async throws {
        let m = try await module([makeSession(.running, updatedAt: ago(5), runningSince: ago(3900))])
        XCTAssertEqual(try m.collapsedActivity(at: now)?.text, "ufuq · 1h 5m")
        let fresh = try await module([makeSession(.running, updatedAt: ago(5), runningSince: ago(10))])
        XCTAssertEqual(try fresh.collapsedActivity(at: now)?.text, "ufuq · <1m")
    }

    // MARK: Peeks

    /// A module over a mutable in-memory directory, to simulate successive refreshes.
    private final class Box: @unchecked Sendable { var files: [String: String] = [:] }

    private struct BoxSource: FileSource {
        let box: Box
        func files(under directory: String, suffix: String) throws -> [String] { box.files.keys.sorted() }
        func read(_ path: String) throws -> Data { Data(box.files[path]!.utf8) }
    }

    private func set(_ box: Box, _ s: AgentSession) throws {
        box.files["\(dir)/\(s.id).json"] = String(decoding: try s.encoded(), as: UTF8.self)
    }

    private func collect(_ m: AgentStatusModule, during body: () async throws -> Void) async throws -> [PeekEvent] {
        let stream = m.peekEvents()
        var received: [PeekEvent] = []
        let task = Task { () -> [PeekEvent] in
            var out: [PeekEvent] = []
            for await e in stream { out.append(e) }
            return out
        }
        try await body()
        // Terminate the stream by dropping the consumer after a short settle.
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        received = await task.value
        return received
    }

    func testPeeks() async throws {
        let box = Box()
        let m = AgentStatusModule(directory: dir, fileSource: BoxSource(box: box))
        try set(box, makeSession(.running, id: "w", title: "waiter", updatedAt: ago(100), runningSince: ago(100)))
        try set(box, makeSession(.waiting, id: "base", title: "baseline", updatedAt: ago(100)))
        try set(box, makeSession(.running, id: "long", title: "long", updatedAt: ago(100), runningSince: ago(300)))
        try set(box, makeSession(.running, id: "short", title: "short", updatedAt: ago(100), runningSince: ago(100)))

        let events = try await collect(m) {
            try await m.refresh()   // baseline: no peeks even though one session is already waiting
            try self.set(box, makeSession(.waiting, id: "w", title: "waiter", updatedAt: self.ago(5), runningSince: self.ago(100)))
            try self.set(box, makeSession(.done, id: "long", title: "long", updatedAt: self.ago(0),
                                           runningSince: self.ago(252), finishedAt: self.ago(0)))
            try self.set(box, makeSession(.done, id: "short", title: "short", updatedAt: self.ago(0),
                                           runningSince: self.ago(20), finishedAt: self.ago(0)))
            try await m.refresh()
            try await m.refresh()   // nothing changed: no repeats
        }
        XCTAssertEqual(events.map(\.id), ["agent.done.long", "agent.waiting.w"])
        let waiting = try XCTUnwrap(events.first { $0.id == "agent.waiting.w" })
        XCTAssertEqual(waiting.title, "Claude needs input")
        XCTAssertEqual(waiting.message, "waiter")
        XCTAssertEqual(waiting.priority, .critical)
        XCTAssertEqual(waiting.moduleID, "agent")
        let done = try XCTUnwrap(events.first { $0.id == "agent.done.long" })
        XCTAssertEqual(done.title, "Task done")
        XCTAssertEqual(done.message, "long · 4m 12s")
        XCTAssertEqual(done.priority, .normal)
    }

    func testDonePeekThresholdIsThirtySeconds() async throws {
        let box = Box()
        let m = AgentStatusModule(directory: dir, fileSource: BoxSource(box: box))
        try set(box, makeSession(.running, id: "a", title: "a", updatedAt: ago(10), runningSince: ago(100)))
        try set(box, makeSession(.running, id: "b", title: "b", updatedAt: ago(10), runningSince: ago(100)))
        let events = try await collect(m) {
            try await m.refresh()
            try self.set(box, makeSession(.done, id: "a", title: "a", updatedAt: self.now, runningSince: self.ago(30), finishedAt: self.now))
            try self.set(box, makeSession(.done, id: "b", title: "b", updatedAt: self.now, runningSince: self.ago(29), finishedAt: self.now))
            try await m.refresh()
        }
        XCTAssertEqual(events.map(\.id), ["agent.done.a"])
        XCTAssertEqual(events.first?.message, "a · 30s")
    }

    func testNewSessionWaitingAfterBaselinePeeks() async throws {
        let box = Box()
        let m = AgentStatusModule(directory: dir, fileSource: BoxSource(box: box))
        let events = try await collect(m) {
            try await m.refresh()
            try self.set(box, makeSession(.waiting, id: "n", title: "new", updatedAt: self.now))
            try await m.refresh()
        }
        XCTAssertEqual(events.map(\.id), ["agent.waiting.n"])
    }
}

// MARK: - Installer

final class ClaudeHookInstallerTests: XCTestCase {
    private let hook = "/Applications/Ufuq.app/Contents/MacOS/ufuq-hook"

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func commands(_ data: Data, event: String) throws -> [String] {
        let hooks = try XCTUnwrap(try object(data)["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    func testInstallIntoNilAndEmpty() throws {
        for input in [nil, Data(), Data("  \n".utf8)] as [Data?] {
            let out = try ClaudeHookInstaller.install(into: input, hookPath: hook)
            let hooks = try XCTUnwrap(try object(out)["hooks"] as? [String: Any])
            XCTAssertEqual(Set(hooks.keys), Set(ClaudeHookInstaller.events))
            XCTAssertEqual(ClaudeHookInstaller.events.count, 10)
            for event in ClaudeHookInstaller.events {
                let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
                XCTAssertEqual(groups.count, 1)
                XCTAssertNil(groups[0]["matcher"])
                let entry = try XCTUnwrap((groups[0]["hooks"] as? [[String: Any]])?.first)
                XCTAssertEqual(entry["type"] as? String, "command")
                XCTAssertEqual(entry["command"] as? String, "'\(hook)' || true")
                XCTAssertEqual(entry["timeout"] as? Int, 5)
            }
            XCTAssertTrue(ClaudeHookInstaller.isInstalled(in: out))
        }
    }

    func testOutputIsPrettyAndSorted() throws {
        let text = String(decoding: try ClaudeHookInstaller.install(into: nil, hookPath: hook), as: UTF8.self)
        XCTAssertTrue(text.contains("\n  \"hooks\""))
        let order = ["Notification", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "PreToolUse",
                     "SessionEnd", "SessionStart", "Stop", "StopFailure", "UserPromptSubmit"]
        let positions = order.map { text.range(of: "\"\($0)\"")!.lowerBound }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testPreservesOtherKeysAndHooks() throws {
        let existing = #"""
        {"model":"opus","permissions":{"allow":["Bash(ls)"]},
         "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard"}]}],
                  "Custom":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}
        """#
        let out = try ClaudeHookInstaller.install(into: Data(existing.utf8), hookPath: hook)
        let root = try object(out)
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertEqual((root["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls)"])
        XCTAssertEqual(try commands(out, event: "PreToolUse"), ["/usr/local/bin/guard", "'\(hook)' || true"])
        XCTAssertEqual(try commands(out, event: "Custom"), ["echo hi"])
    }

    func testInstallIsIdempotentAndUpdatesPath() throws {
        let once = try ClaudeHookInstaller.install(into: nil, hookPath: hook)
        let twice = try ClaudeHookInstaller.install(into: once, hookPath: hook)
        XCTAssertEqual(once, twice)
        let moved = try ClaudeHookInstaller.install(into: once, hookPath: "/new/ufuq-hook")
        XCTAssertEqual(try commands(moved, event: "Stop"), ["'/new/ufuq-hook' || true"])
    }

    func testUninstallRemovesOnlyOurs() throws {
        let existing = #"""
        {"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard"}]}]}}
        """#
        let installed = try ClaudeHookInstaller.install(into: Data(existing.utf8), hookPath: hook)
        let out = try ClaudeHookInstaller.uninstall(from: installed)
        XCTAssertFalse(ClaudeHookInstaller.isInstalled(in: out))
        let hooks = try XCTUnwrap(try object(out)["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["PreToolUse"])
        XCTAssertEqual(try commands(out, event: "PreToolUse"), ["/usr/local/bin/guard"])
        XCTAssertEqual(try object(out)["model"] as? String, "opus")
    }

    func testUninstallFromNothingInstalledChangesNothingSemantically() throws {
        let existing = #"{"model":"opus"}"#
        let out = try ClaudeHookInstaller.uninstall(from: Data(existing.utf8))
        XCTAssertEqual(try object(out) as NSDictionary, ["model": "opus"] as NSDictionary)
    }

    func testUninstallKeepsGroupWithOtherHooks() throws {
        let existing = #"""
        {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/x/ufuq-hook || true"},{"type":"command","command":"echo bye"}]}]}}
        """#
        let out = try ClaudeHookInstaller.uninstall(from: Data(existing.utf8))
        XCTAssertEqual(try commands(out, event: "Stop"), ["echo bye"])
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try ClaudeHookInstaller.install(into: Data("{nope".utf8), hookPath: hook))
        XCTAssertThrowsError(try ClaudeHookInstaller.install(into: Data("[1,2]".utf8), hookPath: hook))
        XCTAssertThrowsError(try ClaudeHookInstaller.install(into: Data(#"{"hooks":[]}"#.utf8), hookPath: hook))
        XCTAssertThrowsError(try ClaudeHookInstaller.install(into: Data(#"{"hooks":{"Stop":{}}}"#.utf8), hookPath: hook))
        XCTAssertThrowsError(try ClaudeHookInstaller.uninstall(from: Data("{nope".utf8)))
        XCTAssertThrowsError(try ClaudeHookInstaller.install(into: nil, hookPath: "/bin/other"))
        XCTAssertFalse(ClaudeHookInstaller.isInstalled(in: Data("{nope".utf8)))
    }

    func testPathWithSpaceAndQuoteIsShellQuoted() throws {
        let path = "/Users/o'brien/My Apps/ufuq-hook"
        let out = try ClaudeHookInstaller.install(into: nil, hookPath: path)
        XCTAssertEqual(try commands(out, event: "Stop"), ["'/Users/o'\\''brien/My Apps/ufuq-hook' || true"])
        XCTAssertTrue(ClaudeHookInstaller.isInstalled(in: out))
    }

    func testPartialInstallIsNotInstalled() throws {
        let partial = #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/x/ufuq-hook' || true"}]}]}}"#
        XCTAssertFalse(ClaudeHookInstaller.isInstalled(in: Data(partial.utf8)))
    }
}
