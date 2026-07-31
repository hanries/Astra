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
        struct Payload: Decodable { let stars: [Star] }
        let decoded = try JSONDecoder().decode(Payload.self, from: data)
        self.init(stars: decoded.stars)
    }

    init(stars: [Star]) {
        self.stars = stars
        self.starsByHR = Dictionary(stars.map { ($0.hr, $0) }, uniquingKeysWith: { first, _ in first })

        let grouped = Dictionary(grouping: stars, by: \.constellation)
        self.constellations = grouped
            .map { abbreviation, members in
                Constellation(
                    abbreviation: abbreviation,
                    name: Self.constellationNames[abbreviation] ?? abbreviation,
                    stars: members.sorted { $0.magnitude < $1.magnitude }
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

    /// The order a user unlocks the sky in: whatever is overhead first, then
    /// outward by angular distance.
    ///
    /// Constellations can't be ordered by how far away they are — Orion's stars
    /// run from 250 to 1,300 light-years, so distance tears every figure apart.
    /// "Outward" has to mean outward across the sky from directly above you.
    ///
    /// Anything that never rises from this latitude is dropped, so a user is
    /// never given a target they can't go outside and look at.
    ///
    /// Compute once and store the result: the zenith moves hourly and the sky
    /// turns through the year, so recomputing later would reshuffle a
    /// progression the user is partway through.
    func constellationsOutward(
        from position: ObserverPosition,
        at date: Date,
        minimumStars: Int = 3
    ) -> [Constellation] {
        let zenith = SkyMath.zenith(for: position, at: date)

        var reachable: [(constellation: Constellation, separation: Double)] = []
        for constellation in constellations {
            guard constellation.starCount >= minimumStars else { continue }
            guard constellation.isEverVisible(fromLatitude: position.latitude) else { continue }
            let separation = SkyMath.angularSeparation(zenith, constellation.center)
            reachable.append((constellation, separation))
        }

        reachable.sort { left, right in
            // Ties broken by abbreviation so the order is reproducible.
            if left.separation == right.separation {
                return left.constellation.abbreviation < right.constellation.abbreviation
            }
            return left.separation < right.separation
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
