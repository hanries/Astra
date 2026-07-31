import Testing
import Foundation
@testable import Astra

/// These check against facts that are true by definition or by navigation
/// practice, rather than against numbers copied out of an ephemeris — so a
/// failure means the maths is wrong, not that a reference value was mistyped.
struct SkyMathTests {

    /// 2000-01-01 12:00 UTC — the J2000.0 epoch, JD 2451545.0 exactly.
    private let j2000 = Date(timeIntervalSince1970: 946_728_000)

    // MARK: - Time

    @Test func julianDateAnchorsAtJ2000() {
        #expect(abs(SkyMath.julianDate(j2000) - 2_451_545.0) < 1e-9)
    }

    @Test func siderealTimeGainsOnSolarTimeEachDay() {
        let start = SkyMath.greenwichMeanSiderealTime(j2000)
        let dayLater = SkyMath.greenwichMeanSiderealTime(j2000.addingTimeInterval(86_400))
        // A solar day is about 361 sidereal degrees, not 360 — the extra ~0.986°
        // is why a star rises about four minutes earlier each night.
        let gained = SkyMath.normalizedDegrees(dayLater - start)
        #expect(abs(gained - 0.98564736629) < 1e-6)
    }

    @Test func longitudeShiftsSiderealTimeDegreeForDegree() {
        let greenwich = SkyMath.localSiderealTime(j2000, longitude: 0)
        let east30 = SkyMath.localSiderealTime(j2000, longitude: 30)
        #expect(abs(SkyMath.normalizedDegrees(east30 - greenwich) - 30) < 1e-9)
    }

    // MARK: - Pointing

    /// The oldest trick in celestial navigation: Polaris sits within a degree of
    /// the pole, so its altitude is your latitude, all night, every night.
    @Test func polarisAltitudeTracksLatitude() {
        let polaris = EquatorialCoordinate(rightAscensionHours: 2.5303, declinationDegrees: 89.2642)
        for latitude in [10.0, 25.0, 40.0, 55.0, 70.0] {
            let position = ObserverPosition(latitude: latitude, longitude: 0)
            for hour in stride(from: 0.0, to: 24.0, by: 1.0) {
                let when = j2000.addingTimeInterval(hour * 3_600)
                let horizontal = SkyMath.horizontal(polaris, from: position, at: when)
                #expect(abs(horizontal.altitude - latitude) < 0.8,
                        "lat \(latitude), hour \(hour): got \(horizontal.altitude)")
            }
        }
    }

    /// A star on the celestial equator transits due south for a northern
    /// observer, and due north for a southern one.
    @Test func transitAzimuthFollowsHemisphere() {
        let north = ObserverPosition(latitude: 40, longitude: 0)
        let equatorial = EquatorialCoordinate(
            rightAscensionDegrees: SkyMath.localSiderealTime(j2000, longitude: 0),
            declinationDegrees: 0
        )
        let seenFromNorth = SkyMath.horizontal(equatorial, from: north, at: j2000)
        #expect(abs(seenFromNorth.altitude - 50) < 1e-6)
        #expect(abs(seenFromNorth.azimuth - 180) < 1e-6)

        let south = ObserverPosition(latitude: -40, longitude: 0)
        let seenFromSouth = SkyMath.horizontal(equatorial, from: south, at: j2000)
        #expect(abs(seenFromSouth.altitude - 50) < 1e-6)
        #expect(abs(seenFromSouth.azimuth - 0) < 1e-6)
    }

    /// A star whose declination equals your latitude passes straight overhead.
    @Test func starAtObserverLatitudeTransitsOverhead() {
        let position = ObserverPosition(latitude: 33, longitude: 0)
        let overhead = EquatorialCoordinate(
            rightAscensionDegrees: SkyMath.localSiderealTime(j2000, longitude: 0),
            declinationDegrees: 33
        )
        let horizontal = SkyMath.horizontal(overhead, from: position, at: j2000)
        #expect(abs(horizontal.altitude - 90) < 1e-6)
    }

    @Test func hourAngleIsZeroOnTheMeridian() {
        let lst = SkyMath.localSiderealTime(j2000, longitude: 0)
        let onMeridian = EquatorialCoordinate(rightAscensionDegrees: lst, declinationDegrees: 20)
        #expect(abs(SkyMath.hourAngle(onMeridian, at: j2000, longitude: 0)) < 1e-6)
    }

    // MARK: - Rising and setting

    @Test func equatorialStarRisesNinetyDegreesFromMeridian() {
        for latitude in [-45.0, 0.0, 45.0] {
            let result = SkyMath.riseSet(declination: 0, latitude: latitude, horizon: 0)
            guard case .risesAndSets(let hourAngle) = result else {
                Issue.record("expected a rising star at latitude \(latitude)")
                continue
            }
            #expect(abs(hourAngle - 90) < 1e-6)
        }
    }

    /// From 60°N anything above +30° declination never sets, and anything below
    /// -30° never comes up at all.
    @Test func highLatitudeSplitsSkyIntoAlwaysAndNever() {
        #expect(SkyMath.riseSet(declination: 45, latitude: 60, horizon: 0) == .circumpolar)
        #expect(SkyMath.riseSet(declination: -45, latitude: 60, horizon: 0) == .neverRises)
        #expect(SkyMath.riseSet(declination: 45, latitude: -60, horizon: 0) == .neverRises)
        #expect(SkyMath.riseSet(declination: -45, latitude: -60, horizon: 0) == .circumpolar)
    }

    @Test func everythingRisesAndSetsAtTheEquator() {
        for declination in [-80.0, -30.0, 0.0, 30.0, 80.0] {
            let result = SkyMath.riseSet(declination: declination, latitude: 0, horizon: 0)
            guard case .risesAndSets = result else {
                Issue.record("declination \(declination) should rise at the equator")
                continue
            }
        }
    }

    @Test func refractionMakesStarsRiseSlightlyEarly() throws {
        let geometric = SkyMath.riseSet(declination: 0, latitude: 45, horizon: 0)
        let refracted = SkyMath.riseSet(declination: 0, latitude: 45)
        guard case .risesAndSets(let g) = geometric,
              case .risesAndSets(let r) = refracted else {
            Issue.record("expected both to rise")
            return
        }
        // A refracted star is up for slightly longer than geometry alone allows.
        #expect(r > g)
        #expect(r - g < 2)
    }

    @Test func maximumAltitudeMatchesTransit() {
        let position = ObserverPosition(latitude: 51.5, longitude: 0)
        let star = EquatorialCoordinate(
            rightAscensionDegrees: SkyMath.localSiderealTime(j2000, longitude: 0),
            declinationDegrees: 10
        )
        let atTransit = SkyMath.horizontal(star, from: position, at: j2000)
        let predicted = SkyMath.maximumAltitude(declination: 10, latitude: 51.5)
        #expect(abs(atTransit.altitude - predicted) < 1e-6)
    }

    @Test func nextTransitPutsStarOnTheMeridian() {
        let position = ObserverPosition(latitude: 35, longitude: -120)
        let star = EquatorialCoordinate(rightAscensionHours: 18.6, declinationDegrees: 38.8)

        let transit = SkyMath.nextTransit(star, from: position, after: j2000)
        #expect(transit > j2000)
        #expect(transit.timeIntervalSince(j2000) < 86_400)

        let hourAngle = SkyMath.hourAngle(star, at: transit, longitude: position.longitude)
        #expect(abs(hourAngle) < 0.01)
    }

    // MARK: - Angles

    @Test func separationIsZeroForTheSamePoint() {
        let star = EquatorialCoordinate(rightAscensionHours: 6.75, declinationDegrees: -16.7)
        #expect(SkyMath.angularSeparation(star, star) < 1e-9)
    }

    @Test func separationBetweenPolesIsHalfTheSky() {
        let north = EquatorialCoordinate(rightAscensionDegrees: 0, declinationDegrees: 90)
        let south = EquatorialCoordinate(rightAscensionDegrees: 0, declinationDegrees: -90)
        #expect(abs(SkyMath.angularSeparation(north, south) - 180) < 1e-6)
    }

    @Test func separationHandlesWrapAroundZeroHours() {
        let before = EquatorialCoordinate(rightAscensionDegrees: 359, declinationDegrees: 0)
        let after = EquatorialCoordinate(rightAscensionDegrees: 1, declinationDegrees: 0)
        #expect(abs(SkyMath.angularSeparation(before, after) - 2) < 1e-6)
    }

    @Test func separationAlongEquatorMatchesRightAscension() {
        let a = EquatorialCoordinate(rightAscensionDegrees: 10, declinationDegrees: 0)
        let b = EquatorialCoordinate(rightAscensionDegrees: 55, declinationDegrees: 0)
        #expect(abs(SkyMath.angularSeparation(a, b) - 45) < 1e-6)
    }

    /// The zenith is what "nearest constellation" is measured from, so it has to
    /// be the point that reads as directly overhead.
    @Test func zenithIsOverhead() {
        let position = ObserverPosition(latitude: 22, longitude: 114)
        let zenith = SkyMath.zenith(for: position, at: j2000)
        let horizontal = SkyMath.horizontal(zenith, from: position, at: j2000)
        #expect(abs(horizontal.altitude - 90) < 1e-6)
    }
}
