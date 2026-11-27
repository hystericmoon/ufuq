import Foundation

public enum CalcMethod: String, CaseIterable, Sendable, Codable {
    /// Kemenag RI: Fajr 20°, Isha 18°, ihtiyat, rounded up to the minute. The default.
    case kemenag
    case mwl
    case ummAlQura
    case custom
}

public enum AsrMethod: String, CaseIterable, Sendable, Codable {
    case standard
    case hanafi
}

/// Per-prayer user offsets in minutes (Imsak does not exist in this engine).
public struct PrayerOffsets: Equatable, Sendable, Codable {
    public var subuh: Int
    public var terbit: Int
    public var dzuhur: Int
    public var ashar: Int
    public var maghrib: Int
    public var isya: Int

    public init(subuh: Int = 0, terbit: Int = 0, dzuhur: Int = 0, ashar: Int = 0, maghrib: Int = 0, isya: Int = 0) {
        self.subuh = subuh
        self.terbit = terbit
        self.dzuhur = dzuhur
        self.ashar = ashar
        self.maghrib = maghrib
        self.isya = isya
    }
}

public struct CalculationSettings: Equatable, Sendable, Codable {
    public var method: CalcMethod
    public var customFajrAngle: Double
    public var customIshaAngle: Double
    public var asr: AsrMethod
    public var offsets: PrayerOffsets
    /// Minutes after sunrise until the sun is considered fully risen.
    public var sunriseRiseMinutes: Int
    /// Length of the prohibited window before Dzuhur at zawal.
    public var zawalMinutes: Int

    public init(
        method: CalcMethod = .kemenag,
        customFajrAngle: Double = 20.0,
        customIshaAngle: Double = 18.0,
        asr: AsrMethod = .standard,
        offsets: PrayerOffsets = PrayerOffsets(),
        sunriseRiseMinutes: Int = 15,
        zawalMinutes: Int = 10
    ) {
        self.method = method
        self.customFajrAngle = customFajrAngle
        self.customIshaAngle = customIshaAngle
        self.asr = asr
        self.offsets = offsets
        self.sunriseRiseMinutes = sunriseRiseMinutes
        self.zawalMinutes = zawalMinutes
    }
}

/// Where prayer times are calculated for.
public struct PrayerLocation: Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZone: TimeZone
    /// Metres above sea level; only the Kemenag method uses it (horizon dip).
    public var elevation: Int

    public init(name: String, latitude: Double, longitude: Double, timeZone: TimeZone, elevation: Int = 0) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.elevation = elevation
    }

    /// Jakarta city centre, the primary user's home and the default.
    public static let jakarta = PrayerLocation(
        name: "Jakarta", latitude: -6.2146, longitude: 106.8451,
        timeZone: TimeZone(identifier: "Asia/Jakarta") ?? TimeZone(secondsFromGMT: 7 * 3600)!)
}
