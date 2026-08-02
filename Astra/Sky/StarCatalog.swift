import Foundation

enum StarCatalogError: Error {
    case resourceMissing(String)
}

/// The bundled sky.
///
/// Loaded once from `stars.json`, which `Tools/build_catalog.py` generates from
/// the Yale Bright Star Catalogue. Nothing here reaches the network — the whole
/// sky ships in the app.
struct StarCatalog: Sendable {
    let stars: [Star]
    let constellations: [Constellation]
    /// Figure lines per constellation, as pairs of catalogue numbers. Drawing
    /// convention rather than measurement — see `Tools/build_catalog.py`.
    let figures: [String: [(Int, Int)]]

    private let starsByHR: [Int: Star]
    private let constellationsByAbbreviation: [String: Constellation]

    static let shared: StarCatalog = {
        do { return try StarCatalog(bundle: .main) }
        catch { fatalError("bundled star catalogue failed to load: \(error)") }
    }()

    init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "stars", withExtension: "json") else {
            throw StarCatalogError.resourceMissing("stars.json")
        }
        try self.init(data: Data(contentsOf: url))
    }

    init(data: Data) throws {
        struct Payload: Decodable {
            let stars: [Star]
            let figures: [String: [[Int]]]?
        }
        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        let figures = (decoded.figures ?? [:]).mapValues { edges in
            edges.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
        }
        self.init(stars: decoded.stars, figures: figures)
    }

    init(stars: [Star], figures: [String: [(Int, Int)]] = [:]) {
        self.stars = stars
        self.figures = figures
        self.starsByHR = Dictionary(stars.map { ($0.hr, $0) }, uniquingKeysWith: { first, _ in first })

        // A constellation's unlockable stars are the ones its figure is drawn
        // from, not every star catalogued inside its boundary. The region
        // version made Ursa Major a 29-day constellation whose extra 22 stars
        // were invisible in the shape; the figure version is the seven of the
        // Plough, and finishing it finishes something you can see.
        let grouped = Dictionary(grouping: stars, by: \.constellation)
        self.constellations = grouped
            .map { abbreviation, members in
                let inFigure = Set((figures[abbreviation] ?? []).flatMap { [$0.0, $0.1] })
                let drawn = members.filter { inFigure.contains($0.hr) }
                return Constellation(
                    abbreviation: abbreviation,
                    name: Self.constellationNames[abbreviation] ?? abbreviation,
                    stars: drawn.sorted { $0.magnitude < $1.magnitude }
                )
            }
            .sorted { $0.abbreviation < $1.abbreviation }
        self.constellationsByAbbreviation = Dictionary(
            constellations.map { ($0.abbreviation, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func star(hr: Int) -> Star? { starsByHR[hr] }

    func constellation(_ abbreviation: String) -> Constellation? {
        constellationsByAbbreviation[abbreviation]
    }

    /// Size bands the progression moves through, easiest first.
    ///
    /// Bands rather than exact star counts, because the band is what buys the
    /// sky its shape. Sorting on exact counts makes tiers of three or four
    /// figures, so the order hops back to the zenith every couple of unlocks
    /// and the lit region scatters. A band holds twenty-odd figures, which is
    /// long enough for a visible sweep outward before the next one begins.
    static let sizeBands: [ClosedRange<Int>] = [2...4, 5...7, 8...11, 12...Int.max]

    /// The order a user unlocks the sky in.
    ///
    /// Two rules at once. Figures get harder: everything in the 2-to-4-star
    /// band comes before anything in the 5-to-7 band, so the opening
    /// constellations close in a couple of days while the habit is still
    /// fragile and a fortnight-long figure only arrives once someone has shown
    /// they'll come back. And the sky grows outward: within a band the nearest
    /// overhead comes first, so each band sweeps from the user's own zenith out
    /// to the horizon before the next begins.
    ///
    /// Anything that never rises from this latitude is dropped, so a user is
    /// never given a target they can't go outside and look at.
    ///
    /// Compute once and store the result: the zenith moves hourly and the sky
    /// turns through the year, so recomputing later would reshuffle a
    /// progression the user is partway through.
    func constellationsInUnlockOrder(
        from position: ObserverPosition,
        at date: Date,
        minimumStars: Int = 2
    ) -> [Constellation] {
        let zenith = SkyMath.zenith(for: position, at: date)

        var reachable: [(constellation: Constellation, band: Int, separation: Double)] = []
        for constellation in constellations {
            guard constellation.starCount >= minimumStars else { continue }
            guard constellation.isEverVisible(fromLatitude: position.latitude) else { continue }
            let band = Self.sizeBands.firstIndex { $0.contains(constellation.starCount) }
                ?? Self.sizeBands.count
            let separation = SkyMath.angularSeparation(zenith, constellation.center)
            reachable.append((constellation, band, separation))
        }

        reachable.sort { left, right in
            if left.band != right.band { return left.band < right.band }
            if left.separation != right.separation { return left.separation < right.separation }
            // Abbreviation last, so the order is fully reproducible.
            return left.constellation.abbreviation < right.constellation.abbreviation
        }
        return reachable.map(\.constellation)
    }

    /// IAU constellation names, keyed by the abbreviation the catalogue uses.
    static let constellationNames: [String: String] = [
        "And": "Andromeda",        "Ant": "Antlia",           "Aps": "Apus",
        "Aql": "Aquila",           "Aqr": "Aquarius",         "Ara": "Ara",
        "Ari": "Aries",            "Aur": "Auriga",           "Boo": "Boötes",
        "Cae": "Caelum",           "Cam": "Camelopardalis",   "Cap": "Capricornus",
        "Car": "Carina",           "Cas": "Cassiopeia",       "Cen": "Centaurus",
        "Cep": "Cepheus",          "Cet": "Cetus",            "Cha": "Chamaeleon",
        "Cir": "Circinus",         "CMa": "Canis Major",      "CMi": "Canis Minor",
        "Cnc": "Cancer",           "Col": "Columba",          "Com": "Coma Berenices",
        "CrA": "Corona Australis", "CrB": "Corona Borealis",  "Crt": "Crater",
        "Cru": "Crux",             "Crv": "Corvus",           "CVn": "Canes Venatici",
        "Cyg": "Cygnus",           "Del": "Delphinus",        "Dor": "Dorado",
        "Dra": "Draco",            "Equ": "Equuleus",         "Eri": "Eridanus",
        "For": "Fornax",           "Gem": "Gemini",           "Gru": "Grus",
        "Her": "Hercules",         "Hor": "Horologium",       "Hya": "Hydra",
        "Hyi": "Hydrus",           "Ind": "Indus",            "Lac": "Lacerta",
        "Leo": "Leo",              "Lep": "Lepus",            "Lib": "Libra",
        "LMi": "Leo Minor",        "Lup": "Lupus",            "Lyn": "Lynx",
        "Lyr": "Lyra",             "Men": "Mensa",            "Mic": "Microscopium",
        "Mon": "Monoceros",        "Mus": "Musca",            "Nor": "Norma",
        "Oct": "Octans",           "Oph": "Ophiuchus",        "Ori": "Orion",
        "Pav": "Pavo",             "Peg": "Pegasus",          "Per": "Perseus",
        "Phe": "Phoenix",          "Pic": "Pictor",           "PsA": "Piscis Austrinus",
        "Psc": "Pisces",           "Pup": "Puppis",           "Pyx": "Pyxis",
        "Ret": "Reticulum",        "Scl": "Sculptor",         "Sco": "Scorpius",
        "Sct": "Scutum",           "Ser": "Serpens",          "Sex": "Sextans",
        "Sge": "Sagitta",          "Sgr": "Sagittarius",      "Tau": "Taurus",
        "Tel": "Telescopium",      "TrA": "Triangulum Australe", "Tri": "Triangulum",
        "Tuc": "Tucana",           "UMa": "Ursa Major",       "UMi": "Ursa Minor",
        "Vel": "Vela",             "Vir": "Virgo",            "Vol": "Volans",
        "Vul": "Vulpecula",
    ]
}
