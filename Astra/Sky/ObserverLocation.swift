import Foundation

/// Working out roughly where the user is without asking them.
///
/// The sky needs a latitude before it can decide which constellations are even
/// visible, but a location prompt on first launch is friction at the worst
/// possible moment. A time zone is already known, needs no permission, works
/// offline, and is easily good enough to order the sky and put rise times
/// within an hour.
///
/// Precise location stays worth asking for later — but contextually, the first
/// time someone taps "when can I see this?", where the request explains itself.
enum ObserverLocation {

    /// Latitude decides *what* you can see: which half of the sky is available
    /// at all, and what sits overhead. Longitude only decides *when*. So an
    /// approximation is much more forgiving in longitude than in latitude,
    /// which is why the table below is keyed by zone rather than derived from
    /// the GMT offset.
    static func approximate(from timeZone: TimeZone = .current) -> ObserverPosition? {
        if let known = zoneCentres[timeZone.identifier] {
            return known
        }
        return nil
    }

    /// Longitude implied by a UTC offset. Zones are about 15° wide, so this
    /// lands within roughly ±7.5° — fine for timing, useless for latitude.
    static func longitude(fromSecondsFromGMT seconds: Int) -> Double {
        let raw = Double(seconds) / 3_600 * 15
        return max(-180, min(180, raw))
    }

    /// Every zone the table knows, for tests and for a "pick your region"
    /// fallback when the identifier isn't recognised.
    static var knownZoneIdentifiers: [String] { Array(zoneCentres.keys) }

    /// Representative coordinates for each zone — the city the zone is named
    /// for, not a population centroid.
    private static let zoneCentres: [String: ObserverPosition] = [
        // Americas
        "America/New_York":                 .init(latitude:  40.71, longitude:  -74.01),
        "America/Chicago":                  .init(latitude:  41.88, longitude:  -87.63),
        "America/Denver":                   .init(latitude:  39.74, longitude: -104.99),
        "America/Phoenix":                  .init(latitude:  33.45, longitude: -112.07),
        "America/Los_Angeles":              .init(latitude:  34.05, longitude: -118.24),
        "America/Anchorage":                .init(latitude:  61.22, longitude: -149.90),
        "America/Toronto":                  .init(latitude:  43.65, longitude:  -79.38),
        "America/Vancouver":                .init(latitude:  49.28, longitude: -123.12),
        "America/Edmonton":                 .init(latitude:  53.55, longitude: -113.49),
        "America/Winnipeg":                 .init(latitude:  49.90, longitude:  -97.14),
        "America/Halifax":                  .init(latitude:  44.65, longitude:  -63.58),
        "America/Mexico_City":              .init(latitude:  19.43, longitude:  -99.13),
        "America/Guatemala":                .init(latitude:  14.63, longitude:  -90.51),
        "America/Havana":                   .init(latitude:  23.11, longitude:  -82.37),
        "America/Panama":                   .init(latitude:   8.98, longitude:  -79.52),
        "America/Bogota":                   .init(latitude:   4.71, longitude:  -74.07),
        "America/Caracas":                  .init(latitude:  10.48, longitude:  -66.90),
        "America/Lima":                     .init(latitude: -12.05, longitude:  -77.04),
        "America/Santiago":                 .init(latitude: -33.45, longitude:  -70.67),
        "America/Sao_Paulo":                .init(latitude: -23.55, longitude:  -46.63),
        "America/Argentina/Buenos_Aires":   .init(latitude: -34.60, longitude:  -58.38),
        "Pacific/Honolulu":                 .init(latitude:  21.31, longitude: -157.86),

        // Europe
        "Europe/London":                    .init(latitude:  51.51, longitude:   -0.13),
        "Europe/Dublin":                    .init(latitude:  53.35, longitude:   -6.26),
        "Europe/Lisbon":                    .init(latitude:  38.72, longitude:   -9.14),
        "Europe/Madrid":                    .init(latitude:  40.42, longitude:   -3.70),
        "Europe/Paris":                     .init(latitude:  48.86, longitude:    2.35),
        "Europe/Brussels":                  .init(latitude:  50.85, longitude:    4.35),
        "Europe/Amsterdam":                 .init(latitude:  52.37, longitude:    4.90),
        "Europe/Berlin":                    .init(latitude:  52.52, longitude:   13.40),
        "Europe/Zurich":                    .init(latitude:  47.38, longitude:    8.54),
        "Europe/Rome":                      .init(latitude:  41.90, longitude:   12.50),
        "Europe/Vienna":                    .init(latitude:  48.21, longitude:   16.37),
        "Europe/Prague":                    .init(latitude:  50.08, longitude:   14.44),
        "Europe/Budapest":                  .init(latitude:  47.50, longitude:   19.04),
        "Europe/Warsaw":                    .init(latitude:  52.23, longitude:   21.01),
        "Europe/Copenhagen":                .init(latitude:  55.68, longitude:   12.57),
        "Europe/Oslo":                      .init(latitude:  59.91, longitude:   10.75),
        "Europe/Stockholm":                 .init(latitude:  59.33, longitude:   18.07),
        "Europe/Helsinki":                  .init(latitude:  60.17, longitude:   24.94),
        "Europe/Athens":                    .init(latitude:  37.98, longitude:   23.73),
        "Europe/Bucharest":                 .init(latitude:  44.43, longitude:   26.10),
        "Europe/Istanbul":                  .init(latitude:  41.01, longitude:   28.98),
        "Europe/Kyiv":                      .init(latitude:  50.45, longitude:   30.52),
        "Europe/Moscow":                    .init(latitude:  55.76, longitude:   37.62),

        // Asia
        "Asia/Jerusalem":                   .init(latitude:  31.77, longitude:   35.21),
        "Asia/Riyadh":                      .init(latitude:  24.71, longitude:   46.68),
        "Asia/Tehran":                      .init(latitude:  35.69, longitude:   51.39),
        "Asia/Dubai":                       .init(latitude:  25.20, longitude:   55.27),
        "Asia/Karachi":                     .init(latitude:  24.86, longitude:   67.00),
        "Asia/Kolkata":                     .init(latitude:  22.57, longitude:   88.36),
        "Asia/Kathmandu":                   .init(latitude:  27.72, longitude:   85.32),
        "Asia/Dhaka":                       .init(latitude:  23.81, longitude:   90.41),
        "Asia/Bangkok":                     .init(latitude:  13.76, longitude:  100.50),
        "Asia/Ho_Chi_Minh":                 .init(latitude:  10.82, longitude:  106.63),
        "Asia/Kuala_Lumpur":                .init(latitude:   3.14, longitude:  101.69),
        "Asia/Singapore":                   .init(latitude:   1.35, longitude:  103.82),
        "Asia/Jakarta":                     .init(latitude:  -6.21, longitude:  106.85),
        "Asia/Manila":                      .init(latitude:  14.60, longitude:  120.98),
        "Asia/Hong_Kong":                   .init(latitude:  22.32, longitude:  114.17),
        "Asia/Taipei":                      .init(latitude:  25.03, longitude:  121.57),
        "Asia/Shanghai":                    .init(latitude:  31.23, longitude:  121.47),
        "Asia/Seoul":                       .init(latitude:  37.57, longitude:  126.98),
        "Asia/Tokyo":                       .init(latitude:  35.68, longitude:  139.65),

        // Africa
        "Africa/Casablanca":                .init(latitude:  33.57, longitude:   -7.59),
        "Africa/Algiers":                   .init(latitude:  36.75, longitude:    3.06),
        "Africa/Accra":                     .init(latitude:   5.60, longitude:   -0.19),
        "Africa/Lagos":                     .init(latitude:   6.52, longitude:    3.38),
        "Africa/Cairo":                     .init(latitude:  30.04, longitude:   31.24),
        "Africa/Addis_Ababa":               .init(latitude:   9.01, longitude:   38.76),
        "Africa/Nairobi":                   .init(latitude:  -1.29, longitude:   36.82),
        "Africa/Johannesburg":              .init(latitude: -26.20, longitude:   28.05),

        // Oceania
        "Australia/Perth":                  .init(latitude: -31.95, longitude:  115.86),
        "Australia/Adelaide":               .init(latitude: -34.93, longitude:  138.60),
        "Australia/Brisbane":               .init(latitude: -27.47, longitude:  153.03),
        "Australia/Sydney":                 .init(latitude: -33.87, longitude:  151.21),
        "Australia/Melbourne":              .init(latitude: -37.81, longitude:  144.96),
        "Pacific/Auckland":                 .init(latitude: -36.85, longitude:  174.76),
        "Pacific/Fiji":                     .init(latitude: -18.14, longitude:  178.44),
    ]
}
