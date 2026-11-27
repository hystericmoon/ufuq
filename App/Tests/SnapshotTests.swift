import AppKit
import SwiftUI
import XCTest
import UfuqCore
@testable import Ufuq

/// Renders the views with fixed data. PNGs go to `$SNAPSHOT_DIR` when it is set (CI uploads them).
@MainActor
final class SnapshotTests: XCTestCase {
    /// Fixed instant: 2026-11-26 08:00:00 UTC = 15:00 in Jakarta (before Ashar).
    private let fixedNow = Date(timeIntervalSince1970: 1_795_680_000)

    private let wings = WingLayout(
        left: LiveActivity(
            id: "prayer.next", moduleID: "prayer", source: .prayer,
            text: "Ashar 15:12", accessibilityLabel: "Ashar in 12 minutes"),
        right: LiveActivity(
            id: "ai.worst", moduleID: "ai", source: .aiUsage,
            text: "82%", accessibilityLabel: "Claude Work, 82 percent of session",
            usageFraction: 0.82),
        rotating: LiveActivity(
            id: "agent.1", moduleID: "agent", source: .agent,
            text: "ufuq · 4m", accessibilityLabel: "Claude Code, ufuq, running"))

    func testCollapsedNotch() throws {
        try render(CollapsedView(layout: wings, centerGap: 188), size: CGSize(width: 368, height: 32), name: "collapsed-notch")
    }

    func testCollapsedPill() throws {
        try render(CollapsedView(layout: wings, centerGap: 16), size: CGSize(width: 300, height: 32), name: "collapsed-pill")
    }

    func testPeekNormal() throws {
        let event = PeekEvent(id: "p", moduleID: "prayer", title: "Ashar", message: "in 10 minutes, at 15:12")
        try render(PeekView(event: event, topInset: 32), size: CGSize(width: 352, height: 92), name: "peek-normal")
    }

    func testPeekCritical() throws {
        let event = PeekEvent(
            id: "c", moduleID: "prayer", title: "Ashar", message: "Time for Ashar, 15:12", priority: .critical)
        try render(PeekView(event: event, topInset: 32), size: CGSize(width: 352, height: 92), name: "peek-critical")
    }

    /// Design canvas option A with every tile this build has: Prayer, AI (four accounts), Battery.
    func testExpandedBentoAllTiles() throws {
        try renderBento(name: "expanded-bento-all", content: BentoContent(
            snapshot: jakarta, now: fixedNow, ai: Self.aiRows,
            battery: BatteryStatus(percent: 82, isCharging: true, isPluggedIn: true)))
    }

    /// What ships until the usage readers are wired: AI empty state, no battery (desktop Mac).
    func testExpandedBentoPrayerOnly() throws {
        try renderBento(name: "expanded-bento-empty-ai", content: BentoContent(snapshot: jakarta, now: fixedNow))
    }

    /// Claude token counts only (no Codex installed): plain tracks, no percent, never amber or red.
    func testExpandedBentoClaudeTokens() throws {
        let rows = [
            AIUsageRow(id: "c1", provider: .claude, name: "Claude", fraction: 0, detail: "Resets in 2 h 10 min", tokens: 4_200_000),
            AIUsageRow(id: "c2", provider: .claude, name: "Claude · Work", fraction: 0, detail: "No session running", tokens: 0),
        ]
        try renderBento(name: "expanded-bento-claude-tokens", content: BentoContent(snapshot: jakarta, now: fixedNow, ai: rows))
    }

    func testAIUsageRowsMapping() {
        let now = fixedNow
        let lines = [
            AIUsageLine(id: "c1", provider: .claude, name: "Claude",
                        value: .tokens(count: 4_200_000, resetsAt: now.addingTimeInterval(130 * 60))),
            AIUsageLine(id: "c2", provider: .claude, name: "Claude · Work", value: .tokens(count: 0, resetsAt: nil)),
            AIUsageLine(id: "cx", provider: .codex, name: "Codex", value: .limits([
                UsageWindowReading(kind: .session5h, snapshot: UsageSnapshot(fraction: 0.2, capturedAt: now)),
                UsageWindowReading(kind: .weekly, snapshot: UsageSnapshot(
                    fraction: 0.41, capturedAt: now, resetsAt: now.addingTimeInterval(130 * 60)), isEstimated: true),
            ])),
            AIUsageLine(id: "x", provider: .codex, name: "Codex 2", value: .unavailable(reason: "no snapshot")),
        ]
        let rows = AIUsageRows.rows(from: lines, now: now)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].tokens, 4_200_000)
        XCTAssertEqual(rows[0].fraction, 0)
        XCTAssertEqual(rows[0].detail, "Resets in 2 h 10 min")
        XCTAssertEqual(rows[0].accessibilityValue, "4.2 million tokens used in this 5-hour session, resets in 2 hours 10 minutes")
        XCTAssertEqual(rows[1].tokens, 0)
        XCTAssertEqual(rows[1].detail, "No session running")
        XCTAssertEqual(rows[2].fraction, 0.41, accuracy: 0.0001)
        XCTAssertNil(rows[2].tokens)
        XCTAssertEqual(rows[2].detail, "Week 41% est. · resets in 2 h 10 min")
        XCTAssertTrue(rows[3].isUnavailable)
        XCTAssertEqual(rows[3].detail, "Unavailable")
        XCTAssertEqual(AIUsageRows.duration(38 * 60), "38 min")
        XCTAssertEqual(AIUsageRows.duration(20), "under 1 min")

        let paced = AIUsageRows.rows(from: [
            AIUsageLine(
                id: "c3", provider: .claude, name: "Claude",
                value: .tokens(count: 4_200_000, resetsAt: now.addingTimeInterval(130 * 60)),
                paceTokensPerHour: 1_800_000, estimatedCostUSD: 4.20
            ),
            AIUsageLine(
                id: "ag", provider: .antigravity, name: "Antigravity",
                value: .unavailable(reason: "schema changed"), isBetaSource: true
            ),
        ], now: now)
        XCTAssertEqual(paced[0].detail, "1.8M/h · ~$4.20 · 2 h 10 m")
        XCTAssertTrue(paced[0].accessibilityValue.contains("pace 1.8 million tokens per hour"))
        XCTAssertTrue(paced[0].accessibilityValue.contains("estimated cost 4 dollars 20 cents"))
        XCTAssertTrue(paced[1].isBetaSource)
        XCTAssertTrue(paced[1].isUnavailable)
    }

    func testExpandedBentoUnavailable() throws {
        try renderBento(name: "expanded-bento-unavailable", content: BentoContent(
            snapshot: nil, now: fixedNow,
            battery: BatteryStatus(percent: 8, isCharging: false, isPluggedIn: false)))
    }

    // MARK: - Agents

    /// A waiting and a running session, through the real module and an in-memory directory.
    private func agentSessions() async throws -> (AgentStatusModule, [AgentSession]) {
        let dir = "/agents"
        let waiting = AgentSession(
            id: "s1", title: "ufuq", cwd: "/work/ufuq", state: .waiting,
            updatedAt: fixedNow.addingTimeInterval(-10), appBundleID: "com.apple.Terminal")
        let running = AgentSession(
            id: "s2", title: "adwam", cwd: "/work/adwam", state: .running,
            updatedAt: fixedNow.addingTimeInterval(-20), runningSince: fixedNow.addingTimeInterval(-250),
            appBundleID: "com.googlecode.iterm2")
        let source = InMemoryFileSource(files: [
            "\(dir)/s1.json": try waiting.encoded(),
            "\(dir)/s2.json": try running.encoded(),
        ])
        let module = AgentStatusModule(directory: dir, fileSource: source)
        try await module.refresh()
        return (module, module.sessions(at: fixedNow))
    }

    func testCollapsedAgentWaiting() async throws {
        let (module, _) = try await agentSessions()
        let activity = try XCTUnwrap(try module.collapsedActivity(at: fixedNow))
        XCTAssertTrue(activity.isAlert)
        var layout = wings
        layout.rotating = activity
        try render(CollapsedView(layout: layout, centerGap: 188), size: CGSize(width: 368, height: 32), name: "collapsed-agent-waiting")
    }

    func testExpandedBentoAgents() async throws {
        let (_, sessions) = try await agentSessions()
        XCTAssertEqual(sessions.count, 2)
        try renderBento(name: "expanded-bento-agents", content: BentoContent(
            snapshot: jakarta, now: fixedNow, ai: Self.aiRows, agents: sessions))
    }

    func testPeekAgentWaiting() throws {
        let event = PeekEvent(
            id: "agent.waiting.s1", moduleID: "agent", title: "Claude needs input", message: "ufuq",
            priority: .critical)
        try render(PeekView(event: event, topInset: 32), size: CGSize(width: 352, height: 92), name: "peek-agent-waiting")
    }

    // MARK: - GitHub Actions

    private static let sampleRuns = """
    {"workflow_runs":[
     {"id":1,"name":"Mac app","status":"completed","conclusion":"failure","head_sha":"aaa","head_branch":"main","event":"push","html_url":"https://github.com/o/ufuq/actions/runs/1","run_started_at":"2026-11-26T07:50:00Z","updated_at":"2026-11-26T07:55:00Z","pull_requests":[],"triggering_actor":{"login":"me"}},
     {"id":2,"name":"CI","status":"in_progress","conclusion":null,"head_sha":"bbb","head_branch":"feature","event":"pull_request","html_url":"https://github.com/o/adwam/actions/runs/2","run_started_at":"2026-11-26T07:56:00Z","updated_at":"2026-11-26T07:58:00Z","pull_requests":[{"number":12}],"triggering_actor":{"login":"me"}}
    ]}
    """

    /// Builds through the real module with a fake transport and token: no network, no disk.
    private func githubBuilds() async throws -> (GitHubActionsModule, [GitHubBuild]) {
        let now = fixedNow
        let transport: GitHubClient.Transport = { request in
            let path = request.url?.path ?? ""
            let body = path == "/user" ? #"{"login":"me"}"# : Self.sampleRuns
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
        let tokenSource = GitHubTokenSource(
            runCommand: { _, _ in nil }, readFile: { _ in "fake-token" }, fileExists: { _ in false }, tokenPath: "/fake")
        let module = GitHubActionsModule(
            tokenSource: tokenSource,
            makeClient: { GitHubClient(token: $0, transport: transport, now: { now }) },
            manualRepos: { ["o/ufuq"] },
            now: { now })
        try await module.refresh()
        return (module, module.builds(at: now))
    }

    /// A running build outranks the failed one in the wing.
    func testCollapsedCIRunning() async throws {
        let (module, builds) = try await githubBuilds()
        XCTAssertFalse(builds.isEmpty)
        let activity = try XCTUnwrap(try module.collapsedActivity(at: fixedNow))
        XCTAssertEqual(activity.text, "CI running")
        var layout = wings
        layout.rotating = activity
        try render(CollapsedView(layout: layout, centerGap: 188), size: CGSize(width: 368, height: 32), name: "collapsed-ci-running")
    }

    func testCollapsedLongTitle() throws {
        var layout = wings
        layout.rotating = LiveActivity(
            id: "agent.long", moduleID: "agent", source: .agent,
            text: "muslimdaily · 12m", accessibilityLabel: "Claude Code, muslimdaily, running")
        try render(CollapsedView(layout: layout, centerGap: 188), size: CGSize(width: 368, height: 32), name: "collapsed-long-title")
    }

    func testExpandedBentoActions() async throws {
        let (_, builds) = try await githubBuilds()
        let (_, sessions) = try await agentSessions()
        XCTAssertEqual(builds.count, 2)
        try renderBento(name: "expanded-bento-actions", content: BentoContent(
            snapshot: jakarta, now: fixedNow, ai: Self.aiRows, agents: sessions, actions: builds))
    }

    private var jakarta: PrayerSnapshot? { PrayerSnapshots.at(fixedNow, location: AppSettings.defaultLocation) }

    private static let aiRows = [
        AIUsageRow(id: "c1", provider: .claude, name: "Claude · Work", fraction: 0.62, detail: "Week 41% · resets 2 h 10 min"),
        AIUsageRow(id: "c2", provider: .claude, name: "Claude · Personal", fraction: 0.18, detail: "In use by Claude Code"),
        AIUsageRow(id: "cx", provider: .codex, name: "Codex", fraction: 0.84, detail: "High · limit in ~38 min"),
        AIUsageRow(id: "ag", provider: .antigravity, name: "Antigravity", fraction: 0.23, detail: "Pro models", isBetaSource: true),
    ]

    /// Solid surface: ImageRenderer cannot draw glass or materials, and the layout is what is checked.
    private func renderBento(name: String, content: BentoContent) throws {
        let size = BentoLayout.size(smallTiles: content.smallTiles.count, stripHeight: 32)
        let view = ExpandedView(
            content: content, layout: wings, centerGap: 188, stripHeight: 32,
            focusedTile: .constant(.prayer), focusToken: 0, surface: .solid, focusable: false)
        try render(view, size: size, name: name, backdrop: Color(hex: 0x33445A))
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String, backdrop: Color = .black) throws {
        let content = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(backdrop)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "\(name): no image")
        XCTAssertGreaterThan(image.size.width, 0)

        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let tiff = try XCTUnwrap(image.tiffRepresentation, "\(name): no tiff")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff), "\(name): no bitmap")
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]), "\(name): no png")
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
