import XCTest
@testable import UfuqCore

final class PrayerSnapshotTests: XCTestCase {
    private let location = PrayerLocation.jakarta
    private let zone = PrayerTestSupport.jakartaZone

    private func snapshot(_ d: Int, _ h: Int, _ m: Int) -> PrayerSnapshot {
        PrayerSnapshots.at(PrayerTestSupport.at(2026, 10, d, h, m), location: location)!
    }

    func testNextPrayerAtNoonIsAsharWithTodaysSixTimes() {
        let s = snapshot(21, 12, 0)
        XCTAssertEqual(s.next.prayer, .ashar)
        XCTAssertEqual(s.nextSlot, .ashar)
        XCTAssertEqual(s.today.map(\.prayer), Prayer.allCases)
        XCTAssertFalse(s.next.isJumuah)
    }

    func testDzuhurOnFridayIsJumuah() {
        let s = snapshot(23, 9, 0)
        XCTAssertEqual(s.next.prayer, .dzuhur)
        XCTAssertTrue(s.next.isJumuah)
        XCTAssertEqual(s.next.displayName, "Jumat")
    }

    func testAfterIshaTheNextPrayerIsTomorrowsSubuh() {
        let s = snapshot(21, 23, 0)
        XCTAssertEqual(s.next.prayer, .subuh)
        XCTAssertEqual(CivilDate(s.next.time, in: zone).day, 22)
        XCTAssertNil(s.nextSlot)
    }

    func testTerbitIsNeverTheNextPrayer() {
        let s = snapshot(21, 4, 30)  // after Subuh, before Terbit
        XCTAssertEqual(s.next.prayer, .dzuhur)
    }

    func testRefreshAfterIshaIsMidnight() {
        let now = PrayerTestSupport.at(2026, 10, 21, 23, 0)
        let s = PrayerSnapshots.at(now, location: location)!
        XCTAssertEqual(PrayerSnapshots.nextRefresh(after: now, snapshot: s), PrayerTestSupport.at(2026, 10, 22, 0, 0))
    }

    func testRefreshBeforeIshaIsTheNextTime() {
        let now = PrayerTestSupport.at(2026, 10, 21, 12, 0)
        let s = PrayerSnapshots.at(now, location: location)!
        XCTAssertEqual(PrayerSnapshots.nextRefresh(after: now, snapshot: s), s.next.time)
    }

    func testCountdownRemaining() {
        let s = snapshot(21, 12, 0)
        let now = PrayerTestSupport.at(2026, 10, 21, 12, 0)
        XCTAssertEqual(s.next.remaining(from: now), s.next.time.timeIntervalSince(now))
        XCTAssertEqual(s.next.remaining(from: s.next.time.addingTimeInterval(5)), 0)
    }

    func testNoSnapshotInThePolarNight() {
        let pole = PrayerLocation(name: "Pole", latitude: 85, longitude: 0, timeZone: TimeZone(secondsFromGMT: 0)!)
        let now = PrayerTestSupport.at(2026, 6, 21, 12, 0, zone: pole.timeZone)
        XCTAssertNil(PrayerSnapshots.at(now, location: pole, settings: CalculationSettings(method: .mwl)))
    }
}

final class PrayerWindowsTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let day = CivilDate(year: 2026, month: 10, day: 21)

    private func t(_ h: Int, _ m: Int, dayOffset: Int = 0) -> Date {
        PrayerTestSupport.at(2026, 10, 21 + dayOffset, h, m, zone: utc)
    }

    private lazy var today = PrayerSchedule(
        date: day, timeZone: utc, subuh: t(4, 10), terbit: t(5, 30), dzuhur: t(11, 50),
        ashar: t(15, 10), maghrib: t(17, 55), isya: t(19, 5))
    private lazy var yesterday = PrayerSchedule(
        date: day.plusDays(-1), timeZone: utc, subuh: t(4, 11, dayOffset: -1), terbit: t(5, 31, dayOffset: -1),
        dzuhur: t(11, 50, dayOffset: -1), ashar: t(15, 10, dayOffset: -1), maghrib: t(17, 55, dayOffset: -1),
        isya: t(19, 6, dayOffset: -1))
    private lazy var windows =
        PrayerWindows.forDay(today: today, tomorrowSubuh: t(4, 9, dayOffset: 1), sunriseRiseMinutes: 15, zawalMinutes: 10)
        + PrayerWindows.forDay(today: yesterday, tomorrowSubuh: today.subuh, sunriseRiseMinutes: 15, zawalMinutes: 10)

    private func active(_ h: Int, _ m: Int) -> [WindowType] {
        PrayerWindows.active(at: t(h, m), in: windows).map(\.type)
    }

    func testMorningAdhkarRunsFromSubuhToSunrise() {
        XCTAssertTrue(active(4, 10).contains(.morningAdhkar))
        XCTAssertTrue(active(5, 29).contains(.morningAdhkar))
        XCTAssertFalse(active(5, 30).contains(.morningAdhkar))
        XCTAssertFalse(active(4, 9).contains(.morningAdhkar))
    }

    func testEveningAdhkarRunsFromAsharToMaghrib() {
        XCTAssertTrue(active(15, 10).contains(.eveningAdhkar))
        XCTAssertTrue(active(17, 54).contains(.eveningAdhkar))
        XCTAssertFalse(active(17, 55).contains(.eveningAdhkar))
    }

    func testProhibitedAfterSubuhLastsUntilTheSunHasRisen() {
        XCTAssertTrue(active(5, 40).contains(.prohibitedAfterSubuh))
        XCTAssertFalse(active(5, 45).contains(.prohibitedAfterSubuh))
    }

    func testZawalSitsJustBeforeDzuhur() {
        XCTAssertEqual(active(11, 45).first, .prohibitedZawal)
        XCTAssertFalse(active(11, 39).contains(.prohibitedZawal))
        XCTAssertFalse(active(11, 50).contains(.prohibitedZawal))
    }

    func testProhibitedAfterAsharLastsUntilMaghrib() {
        XCTAssertTrue(active(17, 0).contains(.prohibitedAfterAshar))
        XCTAssertFalse(active(17, 55).contains(.prohibitedAfterAshar))
    }

    func testDuhaRunsBetweenTheSunriseProhibitionAndZawal() {
        XCTAssertFalse(active(5, 44).contains(.duha))
        XCTAssertTrue(active(5, 45).contains(.duha))
        XCTAssertTrue(active(11, 39).contains(.duha))
        XCTAssertFalse(active(11, 40).contains(.duha))
    }

    func testWitrRunsFromIsyaUntilTheNextSubuhAcrossMidnight() {
        XCTAssertTrue(active(19, 5).contains(.witr))
        XCTAssertTrue(active(23, 59).contains(.witr))
        XCTAssertTrue(active(2, 0).contains(.witr))  // yesterday's window
        XCTAssertFalse(active(4, 10).contains(.witr))
        XCTAssertFalse(active(19, 4).contains(.witr))
    }

    func testMorningAdhkarTakesPriorityOverTheProhibitionLabel() {
        XCTAssertEqual(active(4, 30), [.morningAdhkar, .prohibitedAfterSubuh])
    }

    func testNoWindowAtMiddayOutsideZawal() {
        XCTAssertEqual(active(13, 0), [])
    }
}

final class TimetableTests: XCTestCase {
    private let calculator = PrayerCalculator()
    private let schedule: (CivilDate) -> PrayerSchedule? = { PrayerCalculator().schedule(date: $0, location: .jakarta) }

    func testAMonthHasOneRowPerDayAndEachRowEqualsTheCalculatorsDay() {
        let rows = Timetable.month(year: 2026, month: 2, hijriAdjustment: 0, schedule: schedule)
        XCTAssertEqual(rows.count, 28)
        XCTAssertEqual(rows.first?.date, CivilDate(year: 2026, month: 2, day: 1))
        XCTAssertEqual(rows.last?.date, CivilDate(year: 2026, month: 2, day: 28))
        XCTAssertEqual(rows[13].schedule, schedule(CivilDate(year: 2026, month: 2, day: 14)))
    }

    func testRamadanFromOutsideIsTheNextOneFromInsideIsTheSameOne() throws {
        let next = try XCTUnwrap(Timetable.ramadan(from: CivilDate(year: 2026, month: 11, day: 19), hijriAdjustment: 0, schedule: schedule))
        XCTAssertTrue((29...30).contains(next.count), "days \(next.count)")
        XCTAssertEqual(next.first?.hijri.day, 1)
        XCTAssertTrue(next.allSatisfy { $0.hijri.month == 9 })
        XCTAssertEqual(next.map(\.date), next.indices.map { next[0].date.plusDays($0) })
        let inside = try XCTUnwrap(Timetable.ramadan(from: next[12].date, hijriAdjustment: 0, schedule: schedule))
        XCTAssertEqual(next.map(\.date), inside.map(\.date))
    }

    func testTheHijriAdjustmentMovesTheFirstDayOfRamadan() throws {
        let from = CivilDate(year: 2026, month: 11, day: 19)
        let plain = try XCTUnwrap(Timetable.ramadan(from: from, hijriAdjustment: 0, schedule: schedule))
        let later = try XCTUnwrap(Timetable.ramadan(from: from, hijriAdjustment: -1, schedule: schedule))
        XCTAssertEqual(plain[0].date.plusDays(1), later[0].date)
    }
}
