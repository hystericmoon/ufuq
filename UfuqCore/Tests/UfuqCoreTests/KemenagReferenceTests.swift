import XCTest
@testable import UfuqCore

/// Compares the Kemenag preset with the official schedule for 16 cities in all three time zones,
/// on four dates across the year. The official tables use Kemenag's own city coordinates (we use
/// GeoNames centres), so up to one minute of difference is expected; anything larger means the
/// preset is wrong.
final class KemenagReferenceTests: XCTestCase {
    private struct Row {
        let city: String
        let lat: Double
        let lon: Double
        let zone: TimeZone
        let date: CivilDate
        let official: [Int]  // subuh, terbit, dzuhur, ashar, maghrib, isya in minutes
        let elevation: Int
    }

    private func load(_ name: String) throws -> [Row] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "tsv", subdirectory: "Fixtures"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, !line.hasPrefix("#") else { return nil }
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return Row(
                city: f[0], lat: Double(f[1])!, lon: Double(f[2])!, zone: TimeZone(identifier: f[3])!,
                date: CivilDate(f[4])!, official: (5...10).map { PrayerTestSupport.parse(f[$0]) },
                elevation: f.count > 11 ? Int(f[11]) ?? 0 : 0)
        }
    }

    private func deltas(_ rows: [Row]) -> [(Row, [Int])] {
        let calculator = PrayerCalculator()
        return rows.map { row in
            let s = calculator.schedule(
                date: row.date, latitude: row.lat, longitude: row.lon, timeZone: row.zone,
                settings: CalculationSettings(), elevation: row.elevation)!
            let ours = s.all.map { PrayerTestSupport.minutes($0.time, in: row.zone) }
            return (row, zip(ours, row.official).map { $0 - $1 })
        }
    }

    func testKemenagPresetMatchesTheOfficialScheduleWithinOneMinute() throws {
        let rows = try load("kemenag_reference") + load("kemenag_official")
        XCTAssertGreaterThanOrEqual(rows.count, 80)
        let results = deltas(rows)
        let worst = results.flatMap(\.1).map { abs($0) }.max() ?? 0
        print("KEMENAG rows=\(rows.count) cities=\(Set(rows.map(\.city)).count) maxDelta=\(worst)")
        for (row, d) in results where d.contains(where: { abs($0) > 1 }) {
            XCTFail("\(row.city) \(row.date): deltas \(d) (ours - official)")
        }
        XCTAssertLessThanOrEqual(worst, 1)
    }

    func testJakartaRowsAreCovered() throws {
        let rows = try load("kemenag_reference") + load("kemenag_official")
        let jakarta = rows.filter { $0.city == "Jakarta" || $0.city == "1301" }
        let days = Set(jakarta.map(\.date))
        print("KEMENAG jakartaDays=\(days.count)")
        XCTAssertGreaterThanOrEqual(days.count, 4)
        let results = deltas(jakarta)
        XCTAssertLessThanOrEqual(results.flatMap(\.1).map { abs($0) }.max() ?? 0, 1)
    }
}
