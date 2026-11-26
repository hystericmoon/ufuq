import XCTest
@testable import UfuqCore

private struct SourceBroke: LocalizedError {
    var errorDescription: String? { "Antigravity state file missing" }
}

private final class FakeModule: UfuqModule {
    let id: String
    let title: String
    var isEnabled = true
    var status: ModuleStatus = .ok
    var failRefresh = false
    var failActivity = false
    var refreshCount = 0

    init(_ id: String, source: ActivitySource = .other) {
        self.id = id
        self.title = id.capitalized
        self.source = source
    }

    let source: ActivitySource

    func refresh() async throws {
        refreshCount += 1
        if failRefresh { throw SourceBroke() }
    }

    func collapsedActivity(at now: Date) throws -> LiveActivity? {
        if failActivity { throw SourceBroke() }
        return LiveActivity(id: id, moduleID: id, source: source, text: title, accessibilityLabel: title)
    }

    func accessibilitySummary() -> String { title }
}

final class ModuleRegistryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRegisterRejectsDuplicateIDs() throws {
        let registry = ModuleRegistry()
        try registry.register(FakeModule("prayer"))
        XCTAssertThrowsError(try registry.register(FakeModule("prayer"))) { error in
            XCTAssertEqual(error as? ModuleRegistry.RegistrationError, .duplicateID("prayer"))
        }
        XCTAssertEqual(registry.modules.count, 1)
    }

    func testThrowingRefreshMarksOnlyThatModuleUnavailable() async throws {
        let registry = ModuleRegistry()
        let prayer = FakeModule("prayer", source: .prayer)
        let antigravity = FakeModule("antigravity", source: .aiUsage)
        antigravity.failRefresh = true
        try registry.register(prayer)
        try registry.register(antigravity)

        await registry.refreshAll()

        XCTAssertEqual(registry.status(of: "prayer"), .ok)
        XCTAssertEqual(registry.status(of: "antigravity"), .unavailable(reason: "Antigravity state file missing"))
        XCTAssertEqual(registry.activities(at: now).map(\.id), ["prayer"])
    }

    func testRecoversAfterSuccessfulRefresh() async throws {
        let registry = ModuleRegistry()
        let m = FakeModule("codex")
        m.failRefresh = true
        try registry.register(m)
        await registry.refreshAll()
        XCTAssertFalse(registry.status(of: "codex")!.isAvailable)

        m.failRefresh = false
        await registry.refreshAll()
        XCTAssertEqual(registry.status(of: "codex"), .ok)
        XCTAssertEqual(registry.activities(at: now).map(\.id), ["codex"])
    }

    func testThrowingActivityIsSkippedAndMarked() throws {
        let registry = ModuleRegistry()
        let bad = FakeModule("bad")
        bad.failActivity = true
        try registry.register(bad)
        try registry.register(FakeModule("good"))

        XCTAssertEqual(registry.activities(at: now).map(\.id), ["good"])
        XCTAssertEqual(registry.status(of: "bad"), .unavailable(reason: "Antigravity state file missing"))
    }

    func testDisabledAndSelfReportedUnavailableModulesAreSkipped() async throws {
        let registry = ModuleRegistry()
        let off = FakeModule("off")
        off.isEnabled = false
        let down = FakeModule("down")
        down.status = .unavailable(reason: "No ~/.codex")
        let stale = FakeModule("stale")
        stale.status = .stale(since: now)
        try registry.register(off)
        try registry.register(down)
        try registry.register(stale)

        await registry.refreshAll()
        XCTAssertEqual(off.refreshCount, 0)
        XCTAssertEqual(registry.activities(at: now).map(\.id), ["stale"], "stale data still shows")
        XCTAssertEqual(registry.status(of: "down"), .unavailable(reason: "No ~/.codex"))
        XCTAssertNil(registry.status(of: "missing"))
    }

    func testDefaultPeekStreamFinishes() async {
        var count = 0
        for await _ in FakeModule("x").peekEvents() { count += 1 }
        XCTAssertEqual(count, 0)
    }
}
