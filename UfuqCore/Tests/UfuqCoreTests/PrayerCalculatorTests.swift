import XCTest
@testable import UfuqCore

final class PrayerCalculatorTests: XCTestCase {
    private let calculator = PrayerCalculator()
    private let zone = PrayerTestSupport.jakartaZone
    private let date = CivilDate(year: 2026, month: 10, day: 21)

    private func jakarta(_ settings: CalculationSettings = CalculationSettings()) -> PrayerSchedule {
        calculator.schedule(date: date, latitude: -6.2146, longitude: 106.8451, timeZone: zone, settings: settings)!
    }

    private func local(_ d: Date) -> Int { PrayerTestSupport.minutes(d, in: zone) }

    func testKemenagIsTheDefaultMethod() {
        XCTAssertEqual(CalculationSettings().method, .kemenag)
    }

    func testTimesAreInOrderAndPlausibleForJakarta() {
        let s = jakarta()
        let times = s.all.map(\.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertTrue((3 * 60 + 50...4 * 60 + 30).contains(local(s.subuh)), "subuh \(local(s.subuh))")
        XCTAssertTrue((11 * 60 + 30...12 * 60 + 10).contains(local(s.dzuhur)), "dzuhur \(local(s.dzuhur))")
        XCTAssertTrue((17 * 60 + 40...18 * 60 + 20).contains(local(s.maghrib)), "maghrib \(local(s.maghrib))")
    }

    func testKemenagTimesAreWholeMinutes() {
        for (_, t) in jakarta().all {
            XCTAssertEqual(Int64(t.timeIntervalSince1970) % 60, 0, "not rounded: \(t)")
        }
    }

    func testKemenagDiffersFromMWLByItsAnglesAndIhtiyat() {
        let kemenag = jakarta()
        let mwl = jakarta(CalculationSettings(method: .mwl))
        // Subuh at 20 degrees is earlier than at 18 degrees, even after +2 minutes ihtiyat.
        XCTAssertLessThan(kemenag.subuh, mwl.subuh)
        // Maghrib: same astronomy, Kemenag adds 3 minutes and rounds up.
        let diff = Int(kemenag.maghrib.timeIntervalSince(mwl.maghrib) / 60)
        XCTAssertTrue((2...4).contains(diff), "maghrib diff \(diff)")
    }

    func testUserOffsetsShiftEachPrayer() {
        let base = jakarta()
        let shifted = jakarta(CalculationSettings(offsets: PrayerOffsets(subuh: 3, isya: -2)))
        XCTAssertEqual(shifted.subuh.timeIntervalSince(base.subuh), 3 * 60)
        XCTAssertEqual(shifted.isya.timeIntervalSince(base.isya), -2 * 60)
        XCTAssertEqual(base.dzuhur, shifted.dzuhur)
    }

    func testHanafiAsharIsLaterThanStandard() {
        let standard = jakarta()
        let hanafi = jakarta(CalculationSettings(asr: .hanafi))
        XCTAssertGreaterThan(hanafi.ashar, standard.ashar)
        XCTAssertEqual(standard.dzuhur, hanafi.dzuhur)
    }

    func testCustomAnglesAreUsed() {
        let a = jakarta(CalculationSettings(method: .custom, customFajrAngle: 20, customIshaAngle: 18))
        let b = jakarta(CalculationSettings(method: .custom, customFajrAngle: 15, customIshaAngle: 15))
        XCTAssertLessThan(a.subuh, b.subuh)
        XCTAssertGreaterThan(a.isya, b.isya)
    }

    func testUmmAlQuraIshaIsNinetyMinutesAfterMaghrib() {
        let s = jakarta(CalculationSettings(method: .ummAlQura))
        let gap = s.isya.timeIntervalSince(s.maghrib) / 60
        XCTAssertEqual(gap, 90, accuracy: 1)
    }

    func testHighLatitudeFallsBackInsteadOfFailing() throws {
        // Oslo in June: the sun never reaches -18 degrees, so Isya/Subuh use the night fraction.
        let oslo = TimeZone(identifier: "Europe/Oslo")!
        let s = try XCTUnwrap(calculator.schedule(
            date: CivilDate(year: 2026, month: 6, day: 21), latitude: 59.91, longitude: 10.75,
            timeZone: oslo, settings: CalculationSettings(method: .mwl)))
        let times = s.all.map(\.time)
        XCTAssertEqual(times, times.sorted())
    }

    func testNoTimesInsideTheArcticCircleAtMidnightSun() {
        let s = calculator.schedule(
            date: CivilDate(year: 2026, month: 6, day: 21), latitude: 80, longitude: 15,
            timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!, settings: CalculationSettings(method: .mwl))
        XCTAssertNil(s)
    }

    func testInvalidLatitudeIsNil() {
        XCTAssertNil(calculator.schedule(date: date, latitude: 95, longitude: 0, timeZone: zone))
    }
}

final class CivilDateTests: XCTestCase {
    func testRoundTripAndArithmetic() {
        let d = CivilDate(year: 2026, month: 10, day: 21)
        XCTAssertEqual(CivilDate(daysSinceEpoch: d.daysSinceEpoch), d)
        XCTAssertEqual(d.plusDays(11), CivilDate(year: 2026, month: 11, day: 1))
        XCTAssertEqual(CivilDate(year: 2024, month: 3, day: 1).plusDays(-1), CivilDate(year: 2024, month: 2, day: 29))
        XCTAssertEqual(d.dayOfYear, 294)
        XCTAssertEqual(CivilDate("2026-10-21"), d)
        XCTAssertEqual(d.description, "2026-10-21")
    }

    func testWeekday() {
        XCTAssertTrue(CivilDate(year: 2026, month: 10, day: 23).isFriday)
        XCTAssertFalse(CivilDate(year: 2026, month: 10, day: 21).isFriday)
        XCTAssertEqual(CivilDate(year: 1970, month: 1, day: 1).isoWeekday, 4)
    }

    func testDateInZone() {
        let late = PrayerTestSupport.at(2026, 10, 21, 23, 30)
        XCTAssertEqual(CivilDate(late, in: PrayerTestSupport.jakartaZone), CivilDate(year: 2026, month: 10, day: 21))
        XCTAssertEqual(CivilDate(late, in: TimeZone(secondsFromGMT: 0)!), CivilDate(year: 2026, month: 10, day: 21))
        XCTAssertEqual(CivilDate(year: 2026, month: 10, day: 21).startOfDay(in: PrayerTestSupport.jakartaZone),
                       PrayerTestSupport.at(2026, 10, 21, 0, 0))
    }
}

final class HijriCalendarTests: XCTestCase {
    func testAdjustmentShiftsByOneDayAndIsClamped() {
        let date = CivilDate(year: 2026, month: 10, day: 21)
        let base = HijriCalendar.of(date, adjustmentDays: 0)
        let plus = HijriCalendar.of(date, adjustmentDays: 1)
        XCTAssertEqual(plus, HijriCalendar.of(date.plusDays(1), adjustmentDays: 0))
        XCTAssertEqual(HijriCalendar.of(date, adjustmentDays: 5), plus)
        XCTAssertEqual(HijriCalendar.of(date.plusDays(-1), adjustmentDays: 0), HijriCalendar.of(date, adjustmentDays: -1))
        XCTAssertGreaterThan(base.year, 1440)
    }

    func testKnownUmmAlQuraDate() {
        // 1 Muharram 1447 AH (Umm al-Qura) fell on 2025-06-26.
        XCTAssertEqual(HijriCalendar.of(CivilDate(year: 2025, month: 6, day: 26), adjustmentDays: 0),
                       HijriDate(day: 1, month: 1, year: 1447))
        XCTAssertEqual(HijriCalendar.of(CivilDate(year: 2025, month: 6, day: 25), adjustmentDays: 0).month, 12)
    }
}
