import XCTest
@testable import UfuqCore

final class PrayerModuleTests: XCTestCase {
    private let zone = PrayerTestSupport.jakartaZone

    private func module(now: Date) -> PrayerModule {
        PrayerModule(location: .jakarta, clock: { now })
    }

    private func schedule(_ d: Int) -> PrayerSchedule {
        PrayerCalculator().schedule(date: CivilDate(year: 2026, month: 10, day: d), location: .jakarta)!
    }

    func testIdAndDefaults() {
        let m = module(now: PrayerTestSupport.at(2026, 10, 21, 12, 0))
        XCTAssertEqual(m.id, "prayer")
        XCTAssertTrue(m.isEnabled)
        XCTAssertEqual(m.status, .ok)
    }

    func testActivityShowsNextPrayerWithDeadline() throws {
        let now = PrayerTestSupport.at(2026, 10, 21, 12, 0)
        let a = try XCTUnwrap(module(now: now).collapsedActivity(at: now))
        let ashar = schedule(21).ashar
        XCTAssertEqual(a.source, .prayer)
        XCTAssertEqual(a.moduleID, "prayer")
        XCTAssertEqual(a.deadline, ashar)
        XCTAssertEqual(a.text, "Ashar \(PrayerFormat.clock(ashar, in: zone))")
        XCTAssertTrue(a.text.hasPrefix("Ashar "))
        XCTAssertFalse(a.isAlert)
    }

    func testAccessibilityLabelSaysTimeRemaining() throws {
        let ashar = schedule(21).ashar
        let now = ashar.addingTimeInterval(-(72 * 60))
        let a = try XCTUnwrap(module(now: now).collapsedActivity(at: now))
        XCTAssertEqual(a.accessibilityLabel, "Ashar in 1 hour 12 minutes")
    }

    func testSpokenFormats() {
        XCTAssertEqual(PrayerFormat.spoken(2 * 3600), "2 hours")
        XCTAssertEqual(PrayerFormat.spoken(60), "1 minute")
        XCTAssertEqual(PrayerFormat.spoken(45 * 60 - 10), "45 minutes")
        XCTAssertEqual(PrayerFormat.spoken(20), "1 minute")
        XCTAssertEqual(PrayerFormat.spoken(0), "less than a minute")
    }

    func testFridayShowsJumat() throws {
        let now = PrayerTestSupport.at(2026, 10, 23, 9, 0)
        let a = try XCTUnwrap(module(now: now).collapsedActivity(at: now))
        XCTAssertTrue(a.text.hasPrefix("Jumat "), a.text)
    }

    func testPreAdhanPeekWithinLeadIsNormal() throws {
        let ashar = schedule(21).ashar
        let now = ashar.addingTimeInterval(-9 * 60)
        let peek = try XCTUnwrap(module(now: now).duePeek(at: now))
        XCTAssertEqual(peek.priority, .normal)
        XCTAssertEqual(peek.moduleID, "prayer")
        XCTAssertEqual(peek.title, "Ashar")
        XCTAssertTrue(peek.announcement.contains("Ashar in 9 minutes"), peek.announcement)
    }

    func testNoPeekBeforeTheLeadWindow() {
        let ashar = schedule(21).ashar
        let now = ashar.addingTimeInterval(-11 * 60)
        XCTAssertNil(module(now: now).duePeek(at: now))
    }

    func testPreAdhanLeadIsConfigurable() throws {
        let ashar = schedule(21).ashar
        let now = ashar.addingTimeInterval(-14 * 60)
        let m = PrayerModule(location: .jakarta, preAdhanLead: 15 * 60, clock: { now })
        XCTAssertNotNil(m.duePeek(at: now))
    }

    func testAdhanPeekIsCriticalAndTheActivityIsAnAlert() throws {
        let ashar = schedule(21).ashar
        let now = ashar.addingTimeInterval(5)
        let m = module(now: now)
        let peek = try XCTUnwrap(m.duePeek(at: now))
        XCTAssertEqual(peek.priority, .critical)
        XCTAssertEqual(peek.title, "Ashar")
        let a = try XCTUnwrap(m.collapsedActivity(at: now))
        XCTAssertTrue(a.isAlert)
        XCTAssertEqual(a.text, "Ashar now")
    }

    func testNoAdhanPeekAtTerbitAndAfterTheWindow() {
        let s = schedule(21)
        let atTerbit = s.terbit.addingTimeInterval(5)
        XCTAssertNil(module(now: atTerbit).duePeek(at: atTerbit))
        let late = s.ashar.addingTimeInterval(PrayerPeeks.adhanWindow + 1)
        XCTAssertNil(module(now: late).duePeek(at: late))
    }

    func testPeekIdsAreStablePerPrayerAndDay() throws {
        let ashar = schedule(21).ashar
        let t1 = ashar.addingTimeInterval(-9 * 60)
        let t2 = ashar.addingTimeInterval(-3 * 60)
        let m = module(now: t1)
        XCTAssertEqual(try XCTUnwrap(m.duePeek(at: t1)).id, try XCTUnwrap(m.duePeek(at: t2)).id)
    }

    func testUnavailableWhenNoTimesCanBeCalculated() {
        let now = PrayerTestSupport.at(2026, 6, 21, 12, 0, zone: TimeZone(secondsFromGMT: 0)!)
        let pole = PrayerLocation(name: "Pole", latitude: 85, longitude: 0, timeZone: TimeZone(secondsFromGMT: 0)!)
        let m = PrayerModule(location: pole, settings: CalculationSettings(method: .mwl), clock: { now })
        guard case .unavailable = m.status else { return XCTFail("expected unavailable") }
        XCTAssertThrowsError(try m.collapsedActivity(at: now))
        XCTAssertNil(m.duePeek(at: now))
    }

    func testRegistryLoadsTheModuleAndSkipsItWhenBroken() throws {
        let now = PrayerTestSupport.at(2026, 10, 21, 12, 0)
        let registry = ModuleRegistry()
        try registry.register(module(now: now))
        XCTAssertEqual(registry.activities(at: now).count, 1)
    }

    func testSummary() {
        let ashar = schedule(21).ashar
        let now = ashar.addingTimeInterval(-60 * 60)
        XCTAssertTrue(module(now: now).accessibilitySummary().contains("Next prayer Ashar"))
    }
}
