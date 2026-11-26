import Foundation

/// The six times of the day, with the Indonesian names Kemenag and the source app use.
/// There is deliberately no Imsak. Terbit (sunrise) is a time, not a prayer.
public enum Prayer: String, CaseIterable, Sendable, Codable {
    case subuh, terbit, dzuhur, ashar, maghrib, isya

    public var displayName: String {
        switch self {
        case .subuh: return "Subuh"
        case .terbit: return "Terbit"
        case .dzuhur: return "Dzuhur"
        case .ashar: return "Ashar"
        case .maghrib: return "Maghrib"
        case .isya: return "Isya"
        }
    }

    /// The five obligatory prayers, in order (everything but Terbit).
    public static let five: [Prayer] = [.subuh, .dzuhur, .ashar, .maghrib, .isya]
}

/// One day's prayer times at a location.
public struct PrayerSchedule: Equatable, Sendable {
    public var date: CivilDate
    public var timeZone: TimeZone
    public var subuh: Date
    public var terbit: Date
    public var dzuhur: Date
    public var ashar: Date
    public var maghrib: Date
    public var isya: Date

    public init(date: CivilDate, timeZone: TimeZone, subuh: Date, terbit: Date, dzuhur: Date, ashar: Date, maghrib: Date, isya: Date) {
        self.date = date
        self.timeZone = timeZone
        self.subuh = subuh
        self.terbit = terbit
        self.dzuhur = dzuhur
        self.ashar = ashar
        self.maghrib = maghrib
        self.isya = isya
    }

    public func time(_ prayer: Prayer) -> Date {
        switch prayer {
        case .subuh: return subuh
        case .terbit: return terbit
        case .dzuhur: return dzuhur
        case .ashar: return ashar
        case .maghrib: return maghrib
        case .isya: return isya
        }
    }

    /// All six times in order.
    public var all: [(prayer: Prayer, time: Date)] { Prayer.allCases.map { ($0, time($0)) } }
}

/// Calculates prayer times with the Adhan solar algorithm, then applies the method's precautionary
/// minutes (ihtiyat), the user's per-prayer offsets and the method's rounding.
///
/// Kemenag RI is not a standard preset: Subuh 20°, Isya 18°, ihtiyat +2 minutes on Subuh, Ashar and
/// Isya, +3 on Dzuhur and Maghrib (the extra minute stands in for the semi-diameter and horizon
/// corrections Kemenag applies), -3 on Terbit; rounded up to the minute (Terbit down). Kemenag also
/// lowers the horizon for the observer's height (dip = 1.76' * sqrt(h)), which makes sunrise earlier
/// and Maghrib later by about 3-4 minutes in a highland city like Bandung; the preset applies the
/// same correction above 100 m of elevation. Calibrated against the official schedule: within one
/// minute for 16 cities in all three time zones (see KemenagReferenceTests).
public struct PrayerCalculator: Sendable {
    private static let dipBaselineMeters = 100

    public init() {}

    /// Null only where the sun never rises or sets (polar regions) or Asr cannot be computed.
    public func schedule(
        date: CivilDate,
        latitude: Double,
        longitude: Double,
        timeZone: TimeZone,
        settings: CalculationSettings = CalculationSettings(),
        elevation: Int = 0
    ) -> PrayerSchedule? {
        guard abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        let spec = Self.spec(for: settings)
        let solar = SolarTime(date: date, latitude: latitude, longitude: longitude)
        let tomorrow = SolarTime(date: date.plusDays(1), latitude: latitude, longitude: longitude)
        let midnight = Int64(date.daysSinceEpoch) * 86_400

        func seconds(_ hours: Double) -> Int64? {
            hours.isFinite ? midnight + Int64(floor(hours * 3600)) : nil
        }
        guard let sunrise = seconds(solar.sunrise), let sunset = seconds(solar.sunset),
              let dhuhr = seconds(solar.transit), let tomorrowSunrise = seconds(tomorrow.sunrise).map({ $0 + 86_400 }),
              let asr = seconds(solar.afternoon(shadowLength: settings.asr == .hanafi ? 2 : 1))
        else { return nil }

        // High latitudes: Fajr/Isha may not occur or fall unreasonably far into the night.
        let night = Double(tomorrowSunrise - sunset)
        let portion = abs(latitude) > 48 ? 1.0 / 7.0 : 0.5
        let safeFajr = sunrise - Int64((portion * night).rounded(.towardZero))
        var fajr = seconds(solar.timeForSolarAngle(-spec.fajrAngle, afterTransit: false))
        if fajr == nil || fajr! < safeFajr { fajr = safeFajr }

        let safeIsha = sunset + Int64((portion * night).rounded(.towardZero))
        var isha = seconds(solar.timeForSolarAngle(-spec.ishaAngle, afterTransit: true))
        if let interval = spec.ishaIntervalMinutes {
            isha = sunset + Int64(interval) * 60
        } else if isha == nil || isha! > safeIsha {
            isha = safeIsha
        }

        guard let fajr, let isha, fajr < sunrise, sunrise < dhuhr, dhuhr < asr, asr < sunset, sunset < isha else { return nil }

        let dip = spec.horizonDip ? Self.dipSeconds(date: date, latitude: latitude, dhuhr: dhuhr, maghrib: sunset, elevation: elevation) : 0
        let user = settings.offsets
        let ih = spec.ihtiyat

        func adjust(_ t: Int64, _ ihtiyat: Int, _ offset: Int, roundDown: Bool = false, dipSign: Int = 0) -> Date {
            let shifted = t + Int64(ihtiyat + offset) * 60 + Int64(dipSign) * dip
            return Date(timeIntervalSince1970: Double(spec.rounding.apply(shifted, roundDown: roundDown)))
        }

        return PrayerSchedule(
            date: date,
            timeZone: timeZone,
            subuh: adjust(fajr, ih.subuh, user.subuh),
            terbit: adjust(sunrise, ih.terbit, user.terbit, roundDown: true, dipSign: -1),
            dzuhur: adjust(dhuhr, ih.dzuhur, user.dzuhur),
            ashar: adjust(asr, ih.ashar, user.ashar),
            maghrib: adjust(sunset, ih.maghrib, user.maghrib, dipSign: 1),
            isya: adjust(isha, ih.isya, user.isya))
    }

    public func schedule(date: CivilDate, location: PrayerLocation, settings: CalculationSettings = CalculationSettings()) -> PrayerSchedule? {
        schedule(date: date, latitude: location.latitude, longitude: location.longitude,
                 timeZone: location.timeZone, settings: settings, elevation: location.elevation)
    }

    // MARK: - Methods

    private struct MethodSpec {
        var fajrAngle: Double
        var ishaAngle: Double
        /// Fixed Isha delay after Maghrib (Umm al-Qura) instead of an angle.
        var ishaIntervalMinutes: Int?
        var ihtiyat = PrayerOffsets()
        var rounding = MinuteRounding.nearest
        var horizonDip = false
    }

    private static func spec(for s: CalculationSettings) -> MethodSpec {
        switch s.method {
        case .kemenag:
            return MethodSpec(
                fajrAngle: 20, ishaAngle: 18,
                ihtiyat: PrayerOffsets(subuh: 2, terbit: -3, dzuhur: 3, ashar: 2, maghrib: 3, isya: 2),
                rounding: .up, horizonDip: true)
        case .mwl:
            return MethodSpec(fajrAngle: 18, ishaAngle: 17, ihtiyat: PrayerOffsets(dzuhur: 1))
        case .ummAlQura:
            return MethodSpec(fajrAngle: 18.5, ishaAngle: 0, ishaIntervalMinutes: 90)
        case .custom:
            return MethodSpec(fajrAngle: s.customFajrAngle, ishaAngle: s.customIshaAngle)
        }
    }

    /// How much earlier the sun rises (and later it sets) for an observer `elevation` metres up:
    /// the extra depression of the horizon divided by the sun's vertical speed at the horizon.
    private static func dipSeconds(date: CivilDate, latitude: Double, dhuhr: Int64, maghrib: Int64, elevation: Int) -> Int64 {
        // Kemenag doesn't publish the heights it uses per city. Its tables show the correction in
        // highland cities (Bandung, ~700 m) but not in low ones (Yogyakarta, ~110 m), and the
        // sea-level ihtiyat already absorbs the first metres; so only the height above the
        // baseline counts. Calibrated in KemenagReferenceTests.
        let above = elevation - dipBaselineMeters
        if above <= 0 { return 0 }
        let dipDeg = 1.76 / 60.0 * Double(above).squareRoot()
        // Hour angle at sunset, from the computed times (4 minutes of time per degree).
        let halfDayMinutes = Double(maghrib - dhuhr) / 60.0
        let hourAngle = rad(halfDayMinutes / 4.0)
        let declination = rad(23.44 * sin(rad(360.0 / 365.0 * Double(date.dayOfYear - 81))))
        let rate = cos(rad(latitude)) * cos(declination) * sin(hourAngle)  // degrees of altitude per degree of hour angle
        if rate < 0.05 { return 0 }
        return Int64((dipDeg / rate * 4 * 60).rounded(.towardZero))
    }

    private enum MinuteRounding {
        case nearest, up

        func apply(_ t: Int64, roundDown: Bool) -> Int64 {
            let rem = floorMod(t, 60)
            if rem == 0 { return t }
            let floor = t - rem
            switch self {
            case .up: return roundDown ? floor : floor + 60
            case .nearest: return rem >= 30 ? floor + 60 : floor
            }
        }
    }
}
