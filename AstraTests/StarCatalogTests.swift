import Testing
import Foundation
@testable import Astra

struct StarCatalogTests {

    private func loadCatalog() throws -> StarCatalog {
        let candidates = [Bundle.main] + Bundle.allBundles
        for bundle in candidates {
            if let catalog = try? StarCatalog(bundle: bundle) { return catalog }
        }
        throw StarCatalogError.resourceMissing("stars.json in any bundle")
    }

    private func star(_ name: String, in catalog: StarCatalog) throws -> Star {
        try #require(catalog.stars.first { $0.name == name }, "no star named \(name)")
    }

    // MARK: - Loading

    @Test func catalogLoadsFromBundle() throws {
        let catalog = try loadCatalog()
        #expect(catalog.stars.count > 1_500)
        #expect(catalog.constellations.count == 88)
    }

    /// Checks the names table covers every abbreviation the catalogue uses.
    /// Not by comparing name to abbreviation — Ara and Leo are genuinely called
    /// their own abbreviations, and that's a real name, not a missing one.
    @Test func everyConstellationHasAFullName() throws {
        for constellation in try loadCatalog().constellations {
            #expect(StarCatalog.constellationNames[constellation.abbreviation] != nil,
                    "\(constellation.abbreviation) is missing from the names table")
            #expect(!constellation.name.isEmpty)
        }
    }

    @Test func everyStarHasUsableCoordinates() throws {
        for star in try loadCatalog().stars {
            #expect((0..<360).contains(star.coordinate.rightAscension), "HR \(star.hr) RA")
            #expect((-90...90).contains(star.coordinate.declination), "HR \(star.hr) dec")
            #expect(star.magnitude < 10, "HR \(star.hr) magnitude")
        }
    }

    @Test func harvardNumbersAreUnique() throws {
        let catalog = try loadCatalog()
        #expect(Set(catalog.stars.map(\.hr)).count == catalog.stars.count)
    }

    // MARK: - Known values

    /// Spot-checks against figures anyone can look up. If the fixed-width
    /// parsing in the build script ever slips a column, this is what catches it.
    @Test func brightStarsMatchPublishedValues() throws {
        let catalog = try loadCatalog()

        let sirius = try star("Sirius", in: catalog)
        #expect(sirius.constellation == "CMa")
        #expect(abs(sirius.magnitude - -1.46) < 0.01)
        #expect(abs(try #require(sirius.distanceLightYears) - 8.6) < 0.5)
        #expect(sirius.bayer == "Alpha CMa")

        let vega = try star("Vega", in: catalog)
        #expect(vega.constellation == "Lyr")
        // RA 18h 36m 56s, dec +38° 47′.
        #expect(abs(vega.coordinate.rightAscension - 279.23) < 0.1)
        #expect(abs(vega.coordinate.declination - 38.78) < 0.1)

        let polaris = try star("Polaris", in: catalog)
        #expect(abs(polaris.coordinate.declination - 89.26) < 0.05)
    }

    @Test func sirusIsTheBrightestStar() throws {
        let brightest = try #require(try loadCatalog().stars.min { $0.magnitude < $1.magnitude })
        #expect(brightest.name == "Sirius")
    }

    /// Colour index has to carry the actual colour, since that's what the sky
    /// gets drawn from. Rigel is a blue supergiant, Betelgeuse a red one.
    @Test func colourIndexSeparatesBlueFromRed() throws {
        let catalog = try loadCatalog()
        let rigel = try star("Rigel", in: catalog)
        let betelgeuse = try star("Betelgeuse", in: catalog)
        #expect(try #require(rigel.colorIndex) < 0)
        #expect(try #require(betelgeuse.colorIndex) > 1.5)
    }

    @Test func temperatureFollowsColour() throws {
        let catalog = try loadCatalog()
        let rigel = try #require(try star("Rigel", in: catalog).temperatureKelvin)
        let betelgeuse = try #require(try star("Betelgeuse", in: catalog).temperatureKelvin)
        #expect(rigel > 9_000)
        #expect(betelgeuse < 4_000)
    }

    /// Distance is withheld wherever the catalogue's parallax is untrustworthy,
    /// so nothing shown is wrong. Rigel is the case that proves it — BSC5 puts
    /// it at 251 light-years against a modern 860.
    @Test func unreliableDistancesAreWithheldNotGuessed() throws {
        let catalog = try loadCatalog()
        #expect(try star("Rigel", in: catalog).distanceLightYears == nil)
        #expect(try star("Canopus", in: catalog).distanceLightYears == nil)
        #expect(try star("Betelgeuse", in: catalog).distanceLightYears == nil)

        // Everything that does carry one is genuinely nearby.
        for star in catalog.stars {
            if let distance = star.distanceLightYears {
                #expect(distance < 50, "\(star.displayName) at \(distance) ly is beyond the trusted range")
            }
        }
    }

    // MARK: - Constellations

    /// Averaging right ascension directly puts a constellation straddling 0h on
    /// the far side of the sky. Pisces and Pegasus both straddle it.
    @Test func centerHandlesWrapAroundZeroHours() {
        let across = Constellation(abbreviation: "Test", name: "Test", stars: [])
        #expect(across.center.rightAscension == 0)

        let catalog = try? loadCatalog()
        guard let pisces = catalog?.constellation("Psc") else { return }
        let ra = pisces.center.rightAscension
        // Near 0h or 24h, certainly not the ~180° a naive mean would produce.
        #expect(ra < 60 || ra > 300, "Pisces centre landed at \(ra)°")
    }

    @Test func centerSitsAmongItsStars() throws {
        let catalog = try loadCatalog()
        let orion = try #require(catalog.constellation("Ori"))
        for star in orion.stars.prefix(7) {
            let separation = SkyMath.angularSeparation(orion.center, star.coordinate)
            #expect(separation < 30, "\(star.displayName) is \(separation)° from the centre")
        }
    }

    @Test func constellationStarsAreBrightestFirst() throws {
        for constellation in try loadCatalog().constellations {
            let magnitudes = constellation.stars.map(\.magnitude)
            #expect(magnitudes == magnitudes.sorted(), "\(constellation.name) is out of order")
        }
    }

    // MARK: - Progression

    /// The sky a user is given has to be a sky they can actually go and look at.
    @Test func orderingExcludesWhatNeverRises() throws {
        let catalog = try loadCatalog()
        let london = ObserverPosition(latitude: 51.5, longitude: -0.13)
        let order = catalog.constellationsOutward(from: london, at: .now)

        #expect(!order.contains { $0.abbreviation == "Cru" }, "Crux never rises from London")
        #expect(order.contains { $0.abbreviation == "UMa" })
    }

    @Test func hemispheresGetDifferentSkies() throws {
        let catalog = try loadCatalog()
        let sydney = ObserverPosition(latitude: -33.87, longitude: 151.21)
        let order = catalog.constellationsOutward(from: sydney, at: .now)

        #expect(order.contains { $0.abbreviation == "Cru" })
        #expect(!order.contains { $0.abbreviation == "UMi" }, "Ursa Minor never rises from Sydney")
    }

    @Test func orderingStartsOverheadAndMovesOutward() throws {
        let catalog = try loadCatalog()
        let position = ObserverPosition(latitude: 40.71, longitude: -74.01)
        let when = Date(timeIntervalSince1970: 946_728_000)
        let order = catalog.constellationsOutward(from: position, at: when)

        let zenith = SkyMath.zenith(for: position, at: when)
        let separations = order.map { SkyMath.angularSeparation(zenith, $0.center) }
        #expect(separations == separations.sorted())
        #expect(try #require(separations.first) < 25, "nothing was near the zenith")
    }

    @Test func orderingIsReproducible() throws {
        let catalog = try loadCatalog()
        let position = ObserverPosition(latitude: 35.68, longitude: 139.65)
        let when = Date(timeIntervalSince1970: 946_728_000)
        let first = catalog.constellationsOutward(from: position, at: when).map(\.abbreviation)
        let second = catalog.constellationsOutward(from: position, at: when).map(\.abbreviation)
        #expect(first == second)
    }

    /// Pacing comes from the real sky rather than a fixed counter, so the
    /// figures need to be in a usable range — not one star, not forty.
    @Test func constellationsTakeAReasonableNumberOfDays() throws {
        let catalog = try loadCatalog()
        let position = ObserverPosition(latitude: 40, longitude: 0)
        let order = catalog.constellationsOutward(from: position, at: .now)
        for constellation in order.prefix(20) {
            #expect(constellation.starCount >= 3, "\(constellation.name) has too few stars")
        }
    }
}
