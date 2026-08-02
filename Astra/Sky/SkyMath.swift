import Foundation

/// Where a star sits on the sky, in the coordinates catalogues use.
///
/// Fixed to the celestial sphere: a star's equatorial coordinates are the same
/// for every observer on Earth. Turning them into "where do I look, and when"
/// needs an observer and a clock — that's `horizontal(from:at:)`.
struct EquatorialCoordinate: Hashable, Sendable {
    /// Right ascension in degrees, 0..<360. Catalogues quote hours; multiply by 15.
    var rightAscension: Double
    /// Declination in degrees, -90...90.
    var declination: Double

    init(rightAscensionDegrees: Double, declinationDegrees: Double) {
        self.rightAscension = rightAscensionDegrees
        self.declination = declinationDegrees
    }

    init(rightAscensionHours: Double, declinationDegrees: Double) {
        self.rightAscension = rightAscensionHours * 15
        self.declination = declinationDegrees
    }
}

/// Where to actually point, for one observer at one moment.
struct HorizontalCoordinate: Hashable, Sendable {
    /// Degrees above the horizon. Negative means below it — not currently visible.
    var altitude: Double
    /// Degrees clockwise from due north: 90 is east, 180 south, 270 west.
    var azimuth: Double

    var isAboveHorizon: Bool { altitude > 0 }
}

/// Somewhere to stand.
struct ObserverPosition: Hashable, Sendable {
    /// Degrees, north positive.
    var latitude: Double
    /// Degrees, east positive.
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// What a star does over a day for one observer.
enum RiseSet: Equatable, Sendable {
    /// Rises and sets. Hour angles are degrees from the meridian.
    case risesAndSets(riseHourAngle: Double)
    /// Never sets — above the horizon all day.
    case circumpolar
    /// Never rises from this latitude.
    case neverRises
}

/// Standard spherical astronomy. Meeus, *Astronomical Algorithms*, chapters 12
/// and 13, at the precision an app that says "look east around ten" needs —
/// tenths of a degree, no nutation or aberration terms.
enum SkyMath {

    /// Refraction lifts a star's apparent position slightly, so it appears to
    /// rise fractionally before it geometrically does.
    static let horizonRefraction = -0.5667

    // MARK: - Time

    /// Julian Date — days since noon UTC on 1 January 4713 BC, the epoch every
    /// astronomical formula below is written against.
    static func julianDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5
    }

    /// Greenwich mean sidereal time in degrees, 0..<360.
    ///
    /// Sidereal time runs against the stars rather than the sun, which is why
    /// it gains about four minutes a day on a clock and why a given star rises
    /// four minutes earlier each night.
    static func greenwichMeanSiderealTime(_ date: Date) -> Double {
        let d = julianDate(date) - 2_451_545.0
        return normalizedDegrees(280.46061837 + 360.98564736629 * d)
    }

    /// Local sidereal time in degrees — the right ascension currently on the
    /// observer's meridian.
    static func localSiderealTime(_ date: Date, longitude: Double) -> Double {
        normalizedDegrees(greenwichMeanSiderealTime(date) + longitude)
    }

    /// How far past the meridian a star is, in degrees. Negative means it hasn't
    /// transited yet.
    static func hourAngle(_ coordinate: EquatorialCoordinate, at date: Date, longitude: Double) -> Double {
        let h = localSiderealTime(date, longitude: longitude) - coordinate.rightAscension
        return normalizedDegrees(h + 180) - 180
    }

    // MARK: - Pointing

    static func horizontal(
        _ coordinate: EquatorialCoordinate,
        from position: ObserverPosition,
        at date: Date
    ) -> HorizontalCoordinate {
        let h  = radians(hourAngle(coordinate, at: date, longitude: position.longitude))
        let dec = radians(coordinate.declination)
        let lat = radians(position.latitude)

        let sinAltitude = sin(dec) * sin(lat) + cos(dec) * cos(lat) * cos(h)
        let altitude = asin(min(max(sinAltitude, -1), 1))

        let azimuth = atan2(
            -sin(h) * cos(dec),
            sin(dec) * cos(lat) - cos(dec) * cos(h) * sin(lat)
        )

        return HorizontalCoordinate(
            altitude: degrees(altitude),
            azimuth: normalizedDegrees(degrees(azimuth))
        )
    }

    // MARK: - Rising and setting

    /// Whether a star rises at all from this latitude, and if so how far from
    /// the meridian it does so.
    ///
    /// Depends only on declination and latitude — not on the date. Whether a
    /// star is *up* changes hourly; whether it *can* be up doesn't.
    static func riseSet(
        declination: Double,
        latitude: Double,
        horizon: Double = horizonRefraction
    ) -> RiseSet {
        let dec = radians(declination)
        let lat = radians(latitude)
        let denominator = cos(lat) * cos(dec)

        // At the pole, or for a star exactly at the celestial pole, the star
        // neither rises nor sets — it sits at a fixed altitude all day.
        guard abs(denominator) > 1e-12 else {
            return degrees(asin(min(max(sin(dec) * sin(lat), -1), 1))) > horizon
                ? .circumpolar : .neverRises
        }

        let cosH = (sin(radians(horizon)) - sin(dec) * sin(lat)) / denominator
        if cosH < -1 { return .circumpolar }
        if cosH > 1 { return .neverRises }
        return .risesAndSets(riseHourAngle: degrees(acos(cosH)))
    }

    /// When the star next crosses the observer's meridian — its highest point,
    /// and the easiest moment to find it.
    static func nextTransit(
        _ coordinate: EquatorialCoordinate,
        from position: ObserverPosition,
        after date: Date
    ) -> Date {
        let h = hourAngle(coordinate, at: date, longitude: position.longitude)
        // Sidereal degrees per second of clock time.
        let siderealRate = 360.98564736629 / 86_400
        let degreesToGo = h <= 0 ? -h : 360 - h
        return date.addingTimeInterval(degreesToGo / siderealRate)
    }

    /// The altitude a star reaches at transit — the best view an observer at
    /// this latitude will ever get of it.
    static func maximumAltitude(declination: Double, latitude: Double) -> Double {
        90 - abs(latitude - declination)
    }

    // MARK: - Angles

    /// Great-circle separation between two points on the sphere, in degrees.
    ///
    /// Uses the haversine form rather than the cosine rule, which loses its
    /// precision for the small separations that matter when ordering
    /// neighbouring constellations.
    static func angularSeparation(_ a: EquatorialCoordinate, _ b: EquatorialCoordinate) -> Double {
        let dec1 = radians(a.declination)
        let dec2 = radians(b.declination)
        let dDec = dec2 - dec1
        let dRA = radians(b.rightAscension - a.rightAscension)

        let h = sin(dDec / 2) * sin(dDec / 2)
            + cos(dec1) * cos(dec2) * sin(dRA / 2) * sin(dRA / 2)
        return degrees(2 * asin(min(sqrt(h), 1)))
    }

    // MARK: - Projection

    /// A star's place on a flat chart, in degrees from the chart's centre.
    struct ProjectedPoint: Hashable, Sendable {
        /// Degrees east-west. Positive is left on screen, because that's where
        /// east is when you're lying on your back looking up.
        var x: Double
        /// Degrees north-south. Positive is up.
        var y: Double
        /// Great-circle degrees from the centre. Equals `hypot(x, y)`.
        var angularDistance: Double
    }

    /// Azimuthal equidistant projection about an arbitrary centre.
    ///
    /// Chosen over stereographic or gnomonic because distance from the centre
    /// of the chart *is* angular distance from the anchor — and since the
    /// unlock order is itself sorted by angular distance from the anchor, a
    /// user's lit region grows as a filled disc spreading outward. The map
    /// explains the progression without a legend.
    ///
    /// Everything within 180° projects, so the entire sphere fits on one chart,
    /// with the antipode smeared around the rim. That distortion is real but
    /// lands where nothing is yet unlocked.
    static func project(
        _ coordinate: EquatorialCoordinate,
        from center: EquatorialCoordinate
    ) -> ProjectedPoint {
        let dec = radians(coordinate.declination)
        let dec0 = radians(center.declination)
        let deltaRA = radians(coordinate.rightAscension - center.rightAscension)

        let cosC = sin(dec0) * sin(dec) + cos(dec0) * cos(dec) * cos(deltaRA)
        let c = acos(min(max(cosC, -1), 1))

        // At the centre itself the bearing is undefined and the radius is zero.
        guard c > 1e-9 else { return ProjectedPoint(x: 0, y: 0, angularDistance: 0) }

        let bearing = atan2(
            sin(deltaRA) * cos(dec),
            cos(dec0) * sin(dec) - sin(dec0) * cos(dec) * cos(deltaRA)
        )
        let radius = degrees(c)
        return ProjectedPoint(
            x: radius * sin(bearing),
            y: radius * cos(bearing),
            angularDistance: radius
        )
    }

    /// The point directly overhead for an observer at a given moment.
    static func zenith(for position: ObserverPosition, at date: Date) -> EquatorialCoordinate {
        EquatorialCoordinate(
            rightAscensionDegrees: localSiderealTime(date, longitude: position.longitude),
            declinationDegrees: position.latitude
        )
    }

    // MARK: - Helpers

    static func normalizedDegrees(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
