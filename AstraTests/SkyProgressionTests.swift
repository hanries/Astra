import Testing
import Foundation
@testable import Astra

struct SkyProgressionTests {

    private func loadCatalog() throws -> StarCatalog {
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let catalog = try? StarCatalog(bundle: bundle) { return catalog }
        }
        throw StarCatalogError.resourceMissing("stars.json in any bundle")
    }

    private func progression() throws -> SkyProgression {
        let catalog = try loadCatalog()
        let position = ObserverPosition(latitude: 40.71, longitude: -74.01)
        let when = Date(timeIntervalSince1970: 946_728_000)
        return SkyProgression(
            constellations: catalog.constellationsOutward(from: position, at: when)
        )
    }

    @Test func ordinalZeroIsTheFirstConstellationsBrightestStar() throws {
        let sky = try progression()
        let first = try #require(sky.star(forOrdinal: 0))
        let opening = try #require(sky.constellations.first)
        #expect(first.constellation.abbreviation == opening.abbreviation)
        #expect(first.star.hr == opening.stars[0].hr)
    }

    /// The mapping fills one figure completely before starting the next —
    /// that's what makes "a few more days and Orion is done" a true sentence.
    @Test func constellationsFillCompletelyBeforeTheNextBegins() throws {
        let sky = try progression()
        let first = try #require(sky.constellations.first)
        let second = try #require(sky.constellations.dropFirst().first)

        let lastOfFirst = try #require(sky.star(forOrdinal: first.starCount - 1))
        #expect(lastOfFirst.constellation.abbreviation == first.abbreviation)

        let firstOfSecond = try #require(sky.star(forOrdinal: first.starCount))
        #expect(firstOfSecond.constellation.abbreviation == second.abbreviation)
        #expect(firstOfSecond.star.hr == second.stars[0].hr)
    }

    @Test func everyOrdinalMapsToExactlyOneStar() throws {
        let sky = try progression()
        var seen = Set<Int>()
        for ordinal in 0..<min(sky.totalStars, 500) {
            let hit = try #require(sky.star(forOrdinal: ordinal))
            #expect(seen.insert(hit.star.hr).inserted, "HR \(hit.star.hr) unlocked twice")
        }
    }

    @Test func ordinalsBeyondTheSkyAreNil() throws {
        let sky = try progression()
        #expect(sky.star(forOrdinal: -1) == nil)
        #expect(sky.star(forOrdinal: sky.totalStars) == nil)
    }

    @Test func litStarsAccountForEveryAward() throws {
        let sky = try progression()
        for count in [0, 1, 7, 40, 200] {
            let lit = sky.litStars(awardCount: count)
            #expect(lit.map(\.litCount).reduce(0, +) == min(count, sky.totalStars))
        }
    }

    @Test func activeConstellationAdvancesAtTheBoundary() throws {
        let sky = try progression()
        let first = try #require(sky.constellations.first)

        let midway = try #require(sky.active(awardCount: 1))
        #expect(midway.constellation.abbreviation == first.abbreviation)
        #expect(midway.litCount == 1)

        let after = try #require(sky.active(awardCount: first.starCount))
        #expect(after.constellation.abbreviation != first.abbreviation)
        #expect(after.litCount == 0)
    }

    @Test func completedListsOnlyFinishedFigures() throws {
        let sky = try progression()
        let first = try #require(sky.constellations.first)

        #expect(sky.completed(awardCount: first.starCount - 1).isEmpty)
        let done = sky.completed(awardCount: first.starCount)
        #expect(done.map(\.abbreviation) == [first.abbreviation])
    }

    // MARK: - Freezing

    @Test func storedOrderSurvivesRelocation() throws {
        let catalog = try loadCatalog()
        let defaults = try #require(UserDefaults(suiteName: "SkyProgressionTests-\(UUID())"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        let newYork = ObserverPosition(latitude: 40.71, longitude: -74.01)
        let frozen = SkyProgressionStore.load(
            catalog: catalog, defaults: defaults, position: newYork,
            now: Date(timeIntervalSince1970: 946_728_000)
        )

        // Six months later, from the other hemisphere: same order.
        let sydney = ObserverPosition(latitude: -33.87, longitude: 151.21)
        let reloaded = SkyProgressionStore.load(
            catalog: catalog, defaults: defaults, position: sydney,
            now: Date(timeIntervalSince1970: 962_452_800)
        )
        #expect(reloaded.constellations.map(\.abbreviation)
                == frozen.constellations.map(\.abbreviation))
    }

    @Test func corruptStoredOrderRefreezesInsteadOfShrinkingTheSky() throws {
        let catalog = try loadCatalog()
        let defaults = try #require(UserDefaults(suiteName: "SkyProgressionTests-\(UUID())"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }

        defaults.set(["UMa", "NotAConstellation", "Ori"], forKey: SkyProgressionStore.orderKey)
        let recovered = SkyProgressionStore.load(
            catalog: catalog, defaults: defaults,
            position: ObserverPosition(latitude: 40, longitude: 0)
        )
        #expect(recovered.constellations.count > 60)
    }
}
