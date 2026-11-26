import Foundation

// Solar position and event times, after Jean Meeus, "Astronomical Algorithms", as used by the
// Adhan library (MIT, Batoul Apps) that the Adwam Android app calculates with. All angles are
// in degrees unless a name says radians. Internal: the public entry point is `PrayerCalculator`.

@inline(__always) func rad(_ d: Double) -> Double { d * .pi / 180 }
@inline(__always) func deg(_ r: Double) -> Double { r * 180 / .pi }
/// Normalises to 0..<360.
func unwound(_ d: Double) -> Double { d - 360 * floor(d / 360) }
/// Normalises to -180...180.
func quadrantShifted(_ d: Double) -> Double {
    if d >= -180 && d <= 180 { return d }
    return d - 360 * (d / 360).rounded()
}

enum Astronomical {
    static func meanSolarLongitude(_ T: Double) -> Double {
        unwound(280.4664567 + 36000.76983 * T + 0.0003032 * T * T)
    }

    static func meanLunarLongitude(_ T: Double) -> Double {
        unwound(218.3165 + 481267.8813 * T)
    }

    static func ascendingLunarNodeLongitude(_ T: Double) -> Double {
        unwound(125.04452 - 1934.136261 * T + 0.0020708 * T * T + pow(T, 3) / 450000)
    }

    static func meanSolarAnomaly(_ T: Double) -> Double {
        unwound(357.52911 + 35999.05029 * T - 0.0001537 * T * T)
    }

    static func solarEquationOfTheCenter(_ T: Double, meanAnomaly M: Double) -> Double {
        let m = rad(M)
        return (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(m)
            + (0.019993 - 0.000101 * T) * sin(2 * m)
            + 0.000289 * sin(3 * m)
    }

    static func apparentSolarLongitude(_ T: Double, meanLongitude L0: Double) -> Double {
        let longitude = L0 + solarEquationOfTheCenter(T, meanAnomaly: meanSolarAnomaly(T))
        let omega = 125.04 - 1934.136 * T
        return unwound(longitude - 0.00569 - 0.00478 * sin(rad(omega)))
    }

    static func meanObliquityOfTheEcliptic(_ T: Double) -> Double {
        23.439291 - 0.013004167 * T - 0.0000001639 * T * T + 0.0000005036 * pow(T, 3)
    }

    static func apparentObliquityOfTheEcliptic(_ T: Double, mean e0: Double) -> Double {
        e0 + 0.00256 * cos(rad(125.04 - 1934.136 * T))
    }

    static func meanSiderealTime(_ T: Double) -> Double {
        let jd = T * 36525 + 2451545.0
        return unwound(280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * T * T - pow(T, 3) / 38710000)
    }

    static func nutationInLongitude(solar L0: Double, lunar Lp: Double, node omega: Double) -> Double {
        (-17.2 / 3600) * sin(rad(omega))
            - (1.32 / 3600) * sin(2 * rad(L0))
            - (0.23 / 3600) * sin(2 * rad(Lp))
            + (0.21 / 3600) * sin(2 * rad(omega))
    }

    static func nutationInObliquity(solar L0: Double, lunar Lp: Double, node omega: Double) -> Double {
        (9.2 / 3600) * cos(rad(omega))
            + (0.57 / 3600) * cos(2 * rad(L0))
            + (0.10 / 3600) * cos(2 * rad(Lp))
            - (0.09 / 3600) * cos(2 * rad(omega))
    }

    static func altitudeOfCelestialBody(latitude: Double, declination: Double, hourAngle: Double) -> Double {
        let t1 = sin(rad(latitude)) * sin(rad(declination))
        let t2 = cos(rad(latitude)) * cos(rad(declination)) * cos(rad(hourAngle))
        return deg(asin(t1 + t2))
    }

    static func approximateTransit(longitude L: Double, siderealTime theta0: Double, rightAscension a2: Double) -> Double {
        let m0 = unwound(a2 - L - theta0) / 360
        // Near the date line the wrapped value can be a day off; compare with the mean transit.
        let expected = unwound((12.0 - L / 15.0) / 24.0 * 360) / 360
        if m0 - expected > 0.5 { return m0 - 1 }
        if expected - m0 > 0.5 { return m0 + 1 }
        return m0
    }

    /// Solar transit, in hours of universal time from 0h UT of the day.
    static func correctedTransit(
        approximateTransit m0: Double, longitude L: Double, siderealTime theta0: Double,
        rightAscension a2: Double, previousRightAscension a1: Double, nextRightAscension a3: Double
    ) -> Double {
        let theta = unwound(theta0 + 360.985647 * m0)
        let alpha = unwound(interpolateAngles(a2, a1, a3, m0))
        let H = quadrantShifted(theta + L - alpha)
        return (m0 - H / 360) * 24
    }

    /// Hours of universal time at which the sun reaches `angle` (altitude, degrees).
    /// Returns NaN when it never does that day.
    static func correctedHourAngle(
        approximateTransit m0: Double, angle h0: Double, latitude: Double, longitude L: Double,
        afterTransit: Bool, siderealTime theta0: Double,
        rightAscension a2: Double, previousRightAscension a1: Double, nextRightAscension a3: Double,
        declination d2: Double, previousDeclination d1: Double, nextDeclination d3: Double
    ) -> Double {
        let term1 = sin(rad(h0)) - sin(rad(latitude)) * sin(rad(d2))
        let term2 = cos(rad(latitude)) * cos(rad(d2))
        let H0 = deg(acos(term1 / term2))
        let m = afterTransit ? m0 + H0 / 360 : m0 - H0 / 360
        let theta = unwound(theta0 + 360.985647 * m)
        let alpha = unwound(interpolateAngles(a2, a1, a3, m))
        let delta = interpolate(d2, d1, d3, m)
        let H = theta + L - alpha
        let h = altitudeOfCelestialBody(latitude: latitude, declination: delta, hourAngle: H)
        let term3 = h - h0
        let term4 = 360 * cos(rad(delta)) * cos(rad(latitude)) * sin(rad(H))
        return (m + term3 / term4) * 24
    }

    static func interpolate(_ y2: Double, _ y1: Double, _ y3: Double, _ n: Double) -> Double {
        let a = y2 - y1
        let b = y3 - y2
        let c = b - a
        return y2 + (n / 2) * (a + b + n * c)
    }

    static func interpolateAngles(_ y2: Double, _ y1: Double, _ y3: Double, _ n: Double) -> Double {
        let a = unwound(y2 - y1)
        let b = unwound(y3 - y2)
        let c = b - a
        return y2 + (n / 2) * (a + b + n * c)
    }

    static func julianDay(year: Int, month: Int, day: Int, hours: Double = 0) -> Double {
        let Y = month > 2 ? year : year - 1
        let M = month > 2 ? month : month + 12
        let D = Double(day) + hours / 24
        let A = Y / 100
        let B = 2 - A + A / 4
        let i0 = Int(365.25 * (Double(Y) + 4716))
        let i1 = Int(30.6001 * (Double(M) + 1))
        return Double(i0) + Double(i1) + D + Double(B) - 1524.5
    }

    static func julianCentury(_ jd: Double) -> Double { (jd - 2451545.0) / 36525 }
}

struct SolarCoordinates {
    let declination: Double
    let rightAscension: Double
    let apparentSiderealTime: Double

    init(julianDay: Double) {
        let T = Astronomical.julianCentury(julianDay)
        let L0 = Astronomical.meanSolarLongitude(T)
        let Lp = Astronomical.meanLunarLongitude(T)
        let omega = Astronomical.ascendingLunarNodeLongitude(T)
        let lambda = rad(Astronomical.apparentSolarLongitude(T, meanLongitude: L0))
        let theta0 = Astronomical.meanSiderealTime(T)
        let dPsi = Astronomical.nutationInLongitude(solar: L0, lunar: Lp, node: omega)
        let dEps = Astronomical.nutationInObliquity(solar: L0, lunar: Lp, node: omega)
        let eps0 = Astronomical.meanObliquityOfTheEcliptic(T)
        let epsApp = rad(Astronomical.apparentObliquityOfTheEcliptic(T, mean: eps0))

        declination = deg(asin(sin(epsApp) * sin(lambda)))
        rightAscension = unwound(deg(atan2(cos(epsApp) * sin(lambda), cos(lambda))))
        apparentSiderealTime = theta0 + (dPsi * 3600 * cos(rad(eps0 + dEps))) / 3600
    }
}

/// Transit, sunrise and sunset of one day at one place, plus the means to find other solar angles.
/// Results are hours of universal time from 0h UT of the date (may be negative or above 24 in
/// far-east or far-west zones).
struct SolarTime {
    let latitude: Double
    let longitude: Double
    let solar: SolarCoordinates
    let prevSolar: SolarCoordinates
    let nextSolar: SolarCoordinates
    let approxTransit: Double
    let transit: Double
    let sunrise: Double
    let sunset: Double

    init(date: CivilDate, latitude: Double, longitude: Double) {
        let jd = Astronomical.julianDay(year: date.year, month: date.month, day: date.day)
        prevSolar = SolarCoordinates(julianDay: jd - 1)
        solar = SolarCoordinates(julianDay: jd)
        nextSolar = SolarCoordinates(julianDay: jd + 1)
        self.latitude = latitude
        self.longitude = longitude
        approxTransit = Astronomical.approximateTransit(
            longitude: longitude, siderealTime: solar.apparentSiderealTime, rightAscension: solar.rightAscension)
        transit = Astronomical.correctedTransit(
            approximateTransit: approxTransit, longitude: longitude, siderealTime: solar.apparentSiderealTime,
            rightAscension: solar.rightAscension, previousRightAscension: prevSolar.rightAscension,
            nextRightAscension: nextSolar.rightAscension)
        // Refraction 34' plus the sun's semi-diameter 16'.
        let horizon = -50.0 / 60.0
        sunrise = SolarTime.hours(
            approxTransit, horizon, latitude, longitude, false, solar, prevSolar, nextSolar)
        sunset = SolarTime.hours(
            approxTransit, horizon, latitude, longitude, true, solar, prevSolar, nextSolar)
    }

    private static func hours(
        _ m0: Double, _ angle: Double, _ lat: Double, _ lon: Double, _ after: Bool,
        _ s: SolarCoordinates, _ p: SolarCoordinates, _ n: SolarCoordinates
    ) -> Double {
        Astronomical.correctedHourAngle(
            approximateTransit: m0, angle: angle, latitude: lat, longitude: lon, afterTransit: after,
            siderealTime: s.apparentSiderealTime,
            rightAscension: s.rightAscension, previousRightAscension: p.rightAscension, nextRightAscension: n.rightAscension,
            declination: s.declination, previousDeclination: p.declination, nextDeclination: n.declination)
    }

    /// Hours of the sun reaching `angle` degrees of altitude (negative below the horizon).
    func timeForSolarAngle(_ angle: Double, afterTransit: Bool) -> Double {
        SolarTime.hours(approxTransit, angle, latitude, longitude, afterTransit, solar, prevSolar, nextSolar)
    }

    /// Asr: when a shadow is `shadowLength` times the object's height plus its noon shadow.
    func afternoon(shadowLength: Double) -> Double {
        let tangent = abs(latitude - solar.declination)
        let inverse = shadowLength + tan(rad(tangent))
        let angle = deg(atan(1.0 / inverse))
        return timeForSolarAngle(angle, afterTransit: true)
    }
}
