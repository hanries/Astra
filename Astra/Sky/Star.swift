import Foundation

/// One star, as the Bright Star Catalogue has it.
///
/// Everything here is measured rather than invented, which is the point: a star
/// renders from its own magnitude and colour index, so the sky needs no
/// illustration to look like itself.
struct Star: Identifiable, Hashable, Sendable, Decodable {
    /// Harvard Revised number. Stable across catalogue revisions, so it's what
    /// an unlocked star is recorded as.
    let hr: Int
    /// Three-letter IAU constellation abbreviation, e.g. `Ori`.
    let constellation: String
    let coordinate: EquatorialCoordinate
    /// Apparent visual magnitude. Lower is brighter; naked-eye limit is about 6
    /// in true dark and closer to 4 in a city.
    let magnitude: Double
    /// Bayer designation with the constellation, e.g. `Alpha Ori`.
    let bayer: String?
    /// IAU proper name, for the ~100 stars that have one.
    let name: String?
    /// B−V colour index. Negative is blue, positive red.
    let colorIndex: Double?
    let spectralType: String?
    /// Nil when the catalogue's parallax is too small to trust — see
    /// `Tools/build_catalog.py`. A missing distance is deliberate, not a hole.
    let distanceLightYears: Double?

    var id: Int { hr }

    /// What to call it: proper name if it has one, else the Bayer designation.
    var displayName: String {
        name ?? bayer ?? "HR \(hr)"
    }

    /// Surface temperature in kelvin, from the colour index.
    ///
    /// Ballesteros' formula, which fits the blackbody relation closely enough
    /// across the main sequence. Nil without a colour index.
    var temperatureKelvin: Double? {
        guard let colorIndex else { return nil }
        let a = 0.92 * colorIndex
        return 4_600 * (1 / (a + 1.7) + 1 / (a + 0.62))
    }

    /// Whether this star ever clears the horizon from a given latitude.
    func isEverVisible(fromLatitude latitude: Double) -> Bool {
        SkyMath.riseSet(declination: coordinate.declination, latitude: latitude) != .neverRises
    }

    // MARK: - Physical character

    /// Harvard spectral class — O, B, A, F, G, K or M, hottest to coolest.
    var spectralClass: Character? {
        spectralType?.first { "OBAFGKM".contains($0) }
    }

    /// How swollen the star is, from the Roman numeral in its spectral type.
    enum LuminosityClass: String, Sendable {
        case supergiant = "I"
        case brightGiant = "II"
        case giant = "III"
        case subgiant = "IV"
        case mainSequence = "V"

        /// Rough multiplier on a main-sequence star of the same class.
        var radiusFactor: Double {
            switch self {
            case .supergiant:   180
            case .brightGiant:   45
            case .giant:         18
            case .subgiant:       2.5
            case .mainSequence:   1
            }
        }
    }

    /// Parsed from the spectral type. Longest numeral first, or `III` reads as
    /// `I` and every giant becomes a supergiant.
    var luminosityClass: LuminosityClass? {
        guard let spectralType else { return nil }
        // Skip the leading class letter and temperature digits before looking
        // for numerals, so the `I` in a peculiarity suffix isn't picked up.
        for candidate: LuminosityClass in [.giant, .subgiant, .brightGiant, .mainSequence, .supergiant] {
            if spectralType.contains(candidate.rawValue) { return candidate }
        }
        return nil
    }

    /// Radius in solar radii, approximated from spectral and luminosity class.
    ///
    /// An estimate, not a measurement — the catalogue carries no radii, and
    /// these come from the standard class averages. Good enough to show that
    /// Betelgeuse would swallow the inner solar system and Sirius wouldn't,
    /// which is the only claim the comparison view makes.
    var approximateSolarRadii: Double? {
        guard let spectralClass else { return nil }
        let mainSequence: Double = switch spectralClass {
        case "O": 8
        case "B": 4
        case "A": 1.8
        case "F": 1.3
        case "G": 1.0
        case "K": 0.8
        default:  0.4       // M
        }
        return mainSequence * (luminosityClass?.radiusFactor ?? 1)
    }

    /// How coarse the convection cells look, 0...1.
    ///
    /// Cool stars have deep convection zones and correspondingly huge
    /// granules — the Sun's are about 1,000 km across, a red supergiant's can
    /// be a sizeable fraction of the whole star. Hot stars have radiative
    /// envelopes and much finer surface structure.
    var granulationCoarseness: Double {
        guard let kelvin = temperatureKelvin else { return 0.5 }
        // 3,000 K reads as fully coarse, 12,000 K as nearly smooth.
        return max(0.08, min(1, (12_000 - kelvin) / 9_000))
    }

    private enum CodingKeys: String, CodingKey {
        case hr, constellation, ra, dec, magnitude, bayer, name, bv, spectral, ly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hr = try container.decode(Int.self, forKey: .hr)
        constellation = try container.decode(String.self, forKey: .constellation)
        coordinate = EquatorialCoordinate(
            rightAscensionDegrees: try container.decode(Double.self, forKey: .ra),
            declinationDegrees: try container.decode(Double.self, forKey: .dec)
        )
        magnitude = try container.decode(Double.self, forKey: .magnitude)
        bayer = try container.decodeIfPresent(String.self, forKey: .bayer)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        colorIndex = try container.decodeIfPresent(Double.self, forKey: .bv)
        spectralType = try container.decodeIfPresent(String.self, forKey: .spectral)
        distanceLightYears = try container.decodeIfPresent(Double.self, forKey: .ly)
    }
}

/// A constellation and the catalogued stars inside it.
struct Constellation: Identifiable, Hashable, Sendable {
    /// Three-letter IAU abbreviation — the identity used everywhere.
    let abbreviation: String
    let name: String
    /// Brightest first.
    let stars: [Star]

    var id: String { abbreviation }

    var brightestStar: Star? { stars.first }

    /// How many kept days it takes to finish, which is just how many stars it
    /// has. Pacing comes from the real sky rather than a fixed counter — Crux
    /// is a short week, Ursa Major a long one.
    var starCount: Int { stars.count }

    /// The figure's middle, averaged as unit vectors rather than as raw
    /// coordinates. Averaging right ascension directly puts a constellation
    /// straddling 0h — Pisces, Pegasus — on the opposite side of the sky.
    var center: EquatorialCoordinate {
        guard !stars.isEmpty else {
            return EquatorialCoordinate(rightAscensionDegrees: 0, declinationDegrees: 0)
        }
        var x = 0.0, y = 0.0, z = 0.0
        for star in stars {
            let ra = star.coordinate.rightAscension * .pi / 180
            let dec = star.coordinate.declination * .pi / 180
            x += cos(dec) * cos(ra)
            y += cos(dec) * sin(ra)
            z += sin(dec)
        }
        let count = Double(stars.count)
        x /= count; y /= count; z /= count

        let hypotenuse = (x * x + y * y).squareRoot()
        let declination = atan2(z, hypotenuse) * 180 / .pi
        let rightAscension = SkyMath.normalizedDegrees(atan2(y, x) * 180 / .pi)
        return EquatorialCoordinate(
            rightAscensionDegrees: rightAscension,
            declinationDegrees: declination
        )
    }

    /// Whether any of it ever rises from a latitude. A southern user is never
    /// shown Ursa Minor as something to work towards.
    func isEverVisible(fromLatitude latitude: Double) -> Bool {
        stars.contains { $0.isEverVisible(fromLatitude: latitude) }
    }
}
