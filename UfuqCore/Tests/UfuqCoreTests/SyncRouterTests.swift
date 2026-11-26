import XCTest
@testable import UfuqCore

/// XOR "sealer" with a tag byte: enough to test routing without CryptoKit (not on Linux).
struct FakeSealer: SyncSealer {
    var key: UInt8
    struct Bad: Error {}
    func seal(_ plaintext: Data) throws -> Data { Data([0xAA]) + plaintext.map { $0 ^ key } }
    func open(_ sealed: Data) throws -> Data {
        guard sealed.first == 0xAA, sealed.count >= 1 else { throw Bad() }
        let body = sealed.dropFirst().map { $0 ^ key }
        // Wrong key yields garbage; the auth prefix / JSON check rejects it.
        return Data(body)
    }
}

final class SyncRouterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_795_856_400)

    func router(log: SyncEventLog = SyncEventLog(pollInterval: .milliseconds(10)), key: UInt8 = 0x5A,
                clock: Date? = nil, timeout: TimeInterval = 0.2) -> SyncRouter {
        let at = clock ?? now
        return SyncRouter(sealer: FakeSealer(key: key), log: log,
                          content: { SyncSnapshotContent(readings: SyncModelTests.snapshot.readings, agents: SyncModelTests.snapshot.agents) },
                          now: { at }, longPollTimeout: timeout)
    }

    func request(_ path: String, query: [String: String] = [:], key: UInt8 = 0x5A, at: Date? = nil, token: String?? = nil) throws -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token {
            if let token { headers["x-ufuq-auth"] = token }
        } else {
            headers["x-ufuq-auth"] = try SyncAuth.token(sealer: FakeSealer(key: key), now: at ?? now)
        }
        return HTTPRequest(method: "GET", path: path, query: query, headers: headers)
    }

    func testSnapshotIsSealedAndDecodes() async throws {
        let response = await router().handle(try request("/v1/snapshot"))
        XCTAssertEqual(response.status, 200)
        let plain = try FakeSealer(key: 0x5A).open(response.body)
        let snap = try SyncCoding.decode(SyncSnapshot.self, from: plain)
        XCTAssertEqual(snap.generatedAt, now)
        XCTAssertEqual(snap.readings.count, 3)
        XCTAssertEqual(snap.version, 1)
    }

    func testUnpairedGets401WithNoBody() async throws {
        let none = await router().handle(try request("/v1/snapshot", token: .some(nil)))
        XCTAssertEqual(none, HTTPResponse(status: 401))
        let wrongKey = await router().handle(try request("/v1/snapshot", key: 0x11))
        XCTAssertEqual(wrongKey, HTTPResponse(status: 401))
        let junk = await router().handle(try request("/v1/snapshot", token: .some("%%%")))
        XCTAssertEqual(junk.status, 401)
        // Unknown paths do not leak 404 to unpaired callers.
        let unknown = await router().handle(try request("/nope", token: .some(nil)))
        XCTAssertEqual(unknown.status, 401)
    }

    func testStaleTokenRejected() async throws {
        let old = try request("/v1/snapshot", at: now.addingTimeInterval(-600))
        let response = await router().handle(old)
        XCTAssertEqual(response.status, 401)
        let ok = try request("/v1/snapshot", at: now.addingTimeInterval(-299))
        let okResponse = await router().handle(ok)
        XCTAssertEqual(okResponse.status, 200)
    }

    func testUnknownPathIs404ForPairedClient() async throws {
        let response = await router().handle(try request("/v2/other"))
        XCTAssertEqual(response.status, 404)
    }

    func testEventsReturnNewerThanSince() async throws {
        let log = SyncEventLog(pollInterval: .milliseconds(10))
        await log.append(id: "a", moduleId: "usage", title: "t", message: "m", priority: .normal, at: now)
        await log.append(PeekEvent(id: "b", moduleID: "usage", title: "Claude", message: "95%", priority: .critical), at: now)
        let r = router(log: log)
        let response = await r.handle(try request("/v1/events", query: ["since": "1"]))
        let batch = try SyncCoding.decode(SyncEventBatch.self, from: try FakeSealer(key: 0x5A).open(response.body))
        XCTAssertEqual(batch.events.map(\.id), ["b"])
        XCTAssertEqual(batch.events.first?.priority, .critical)
        XCTAssertEqual(batch.latestSeq, 2)
    }

    func testLongPollTimesOutEmptyAndKeepsCursor() async throws {
        let response = await router().handle(try request("/v1/events", query: ["since": "0"]))
        let batch = try SyncCoding.decode(SyncEventBatch.self, from: try FakeSealer(key: 0x5A).open(response.body))
        XCTAssertTrue(batch.events.isEmpty)
        XCTAssertEqual(batch.latestSeq, 0)
    }

    func testLongPollWakesOnNewEvent() async throws {
        let log = SyncEventLog(pollInterval: .milliseconds(10))
        let r = router(log: log, timeout: 5)
        let req = try request("/v1/events", query: ["since": "0"])
        async let response = r.handle(req)
        try await Task.sleep(for: .milliseconds(50))
        await log.append(id: "x", moduleId: "agent", title: "Needs input", message: "m", priority: .normal, at: now)
        let batch = try SyncCoding.decode(SyncEventBatch.self, from: try FakeSealer(key: 0x5A).open(await response.body))
        XCTAssertEqual(batch.events.map(\.id), ["x"])
    }

    func testCursorAheadOfLogRestarts() async throws {
        let log = SyncEventLog(pollInterval: .milliseconds(10))
        await log.append(id: "a", moduleId: "m", title: "t", message: "m", priority: .normal, at: now)
        let response = await router(log: log).handle(try request("/v1/events", query: ["since": "99"]))
        let batch = try SyncCoding.decode(SyncEventBatch.self, from: try FakeSealer(key: 0x5A).open(response.body))
        XCTAssertEqual(batch.events.map(\.id), ["a"])
    }

    func testEventLogCapacity() async {
        let log = SyncEventLog(capacity: 2, pollInterval: .milliseconds(10))
        for i in 0..<5 { await log.append(id: "\(i)", moduleId: "m", title: "t", message: "m", priority: .normal, at: now) }
        let ids = await log.events(since: 0).map(\.id)
        XCTAssertEqual(ids, ["3", "4"])
        let latest = await log.latestSeq
        XCTAssertEqual(latest, 5)
    }
}
