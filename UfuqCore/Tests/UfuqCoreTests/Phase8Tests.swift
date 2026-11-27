import XCTest
@testable import UfuqCore

final class Phase8Tests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private struct StubCalendarSource: CalendarEventSource {
        var result: Result<[MeetingEvent], Error>

        func events(from start: Date, to end: Date) async throws -> [MeetingEvent] {
            try result.get()
        }
    }

    private enum StubError: Error, LocalizedError {
        case denied
        var errorDescription: String? { "Calendar permission denied" }
    }

    // MARK: - Meeting URL parsing

    func testExtractsMeetZoomTeamsWebexAndFaceTimeLinks() {
        let meet = MeetingURLParser.extractJoinLink(
            url: nil,
            location: "https://meet.google.com/abc-defg-hij",
            notes: nil
        )
        XCTAssertEqual(meet?.provider, .googleMeet)
        XCTAssertEqual(meet?.url.absoluteString, "https://meet.google.com/abc-defg-hij")

        let zoom = MeetingURLParser.extractJoinLink(
            url: nil,
            location: "Conference Room",
            notes: "Join Zoom Meeting:\nhttps://us06web.zoom.us/j/81234567890?pwd=xyz."
        )
        XCTAssertEqual(zoom?.provider, .zoom)
        XCTAssertEqual(zoom?.url.absoluteString, "https://us06web.zoom.us/j/81234567890?pwd=xyz")

        let teams = MeetingURLParser.extractJoinLink(
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0"),
            location: nil,
            notes: nil
        )
        XCTAssertEqual(teams?.provider, .teams)

        let webex = MeetingURLParser.extractJoinLink(
            url: nil,
            location: "https://company.webex.com/meet/alex",
            notes: nil
        )
        XCTAssertEqual(webex?.provider, .webex)

        let ft = MeetingURLParser.extractJoinLink(
            url: nil,
            location: nil,
            notes: "Call: https://facetime.apple.com/join#v=1&p=abc"
        )
        XCTAssertEqual(ft?.provider, .facetime)
    }

    func testJoinWindowStartsFiveMinutesBeforeAndStopsAtEnd() {
        let event = MeetingEvent(
            id: "e1",
            title: "Design Sync",
            startDate: t0.addingTimeInterval(5 * 60),
            endDate: t0.addingTimeInterval(35 * 60),
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        XCTAssertFalse(event.canJoin(at: t0.addingTimeInterval(-1)))
        XCTAssertTrue(event.canJoin(at: t0))
        XCTAssertTrue(event.canJoin(at: t0.addingTimeInterval(10 * 60)))
        XCTAssertFalse(event.canJoin(at: t0.addingTimeInterval(35 * 60)))
    }

    // MARK: - CalendarModule & Peeks

    func testCalendarModuleShowsJoinPeekAndAlertWithinFiveMinutes() async throws {
        let event = MeetingEvent(
            id: "meet-1",
            title: "Standup",
            startDate: t0.addingTimeInterval(4 * 60),
            endDate: t0.addingTimeInterval(34 * 60),
            joinURL: URL(string: "https://meet.google.com/xyz-abcd-efg")
        )
        let module = CalendarModule(
            source: StubCalendarSource(result: .success([event])),
            clock: { [t0] in t0 }
        )

        var collected: [PeekEvent] = []
        let stream = module.peekEvents()
        let reader = Task {
            for await peek in stream {
                collected.append(peek)
                break
            }
        }

        try await module.refresh()
        await reader.value

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected.first?.title, "Standup")
        XCTAssertEqual(collected.first?.actionTitle, "Join")
        XCTAssertEqual(collected.first?.actionURL, "https://meet.google.com/xyz-abcd-efg")

        let activity = try XCTUnwrap(try module.collapsedActivity(at: t0))
        XCTAssertEqual(activity.text, "Join · 4m")
        XCTAssertTrue(activity.isAlert)
    }

    func testCalendarModuleFailureMarksUnavailableWithoutCrash() async {
        let module = CalendarModule(
            source: StubCalendarSource(result: .failure(StubError.denied)),
            clock: { [t0] in t0 }
        )
        do {
            try await module.refresh()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(module.status, .unavailable(reason: "Calendar permission denied"))
        }
    }

    // MARK: - Auto DND

    func testAutoDNDTracksMeetingEntryAndExit() {
        var tracker = AutoDNDTracker()
        let meet = MeetingEvent(
            id: "m1",
            title: "Sync",
            startDate: t0,
            endDate: t0.addingTimeInterval(1800),
            joinURL: URL(string: "https://meet.google.com/aaa-bbbb-ccc")
        )
        let allDay = MeetingEvent(
            id: "allday",
            title: "Holiday",
            startDate: t0,
            endDate: t0.addingTimeInterval(86400),
            isAllDay: true
        )

        // All-day event never triggers DND.
        XCTAssertEqual(tracker.update(enabled: true, ongoingMeeting: allDay), .none)
        // Video meeting enables DND once.
        XCTAssertEqual(tracker.update(enabled: true, ongoingMeeting: meet), .enable(meet))
        XCTAssertEqual(tracker.update(enabled: true, ongoingMeeting: meet), .none)
        // Ending meeting disables DND.
        XCTAssertEqual(tracker.update(enabled: true, ongoingMeeting: nil), .disable)
        XCTAssertEqual(tracker.update(enabled: true, ongoingMeeting: nil), .none)
        // Turning off setting while active disables DND.
        XCTAssertEqual(tracker.update(enabled: true, ongoingMeeting: meet), .enable(meet))
        XCTAssertEqual(tracker.update(enabled: false, ongoingMeeting: meet), .disable)
    }

    // MARK: - Transform planners

    func testTransformPathPlannersAndFileClassifiers() {
        let existing: Set<String> = [
            "/tmp/clip compressed.mp4",
            "/tmp/Combined.pdf",
            "/tmp/photo no-bg.png",
        ]
        let actions = TrayActions(fileExists: { existing.contains($0) })

        XCTAssertEqual(actions.compressVideoOutput("/tmp/clip.mov"), "/tmp/clip compressed 2.mp4")
        XCTAssertEqual(actions.combinePDFOutput(directory: "/tmp"), "/tmp/Combined 2.pdf")
        XCTAssertEqual(actions.removeBackgroundOutput("/tmp/photo.heic"), "/tmp/photo no-bg 2.png")

        XCTAssertTrue(TrayActions.isImageExtension("HEIC"))
        XCTAssertTrue(TrayActions.isVideoExtension("mov"))
        XCTAssertTrue(TrayActions.isPDFExtension("PDF"))
        XCTAssertFalse(TrayActions.isVideoExtension("png"))

        XCTAssertEqual(TrayActions.formatOCRStatus(lineCount: 0), "No text found")
        XCTAssertEqual(TrayActions.formatOCRStatus(lineCount: 1), "Copied 1 line of text")
        XCTAssertEqual(TrayActions.formatOCRStatus(lineCount: 4), "Copied 4 lines of text")
    }
}
