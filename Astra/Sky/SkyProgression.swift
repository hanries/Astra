import Foundation

/// Maps the award ledger onto actual stars.
///
/// `Award.ordinal` is just a count; this is what turns ordinal 12 into "Merak,
/// the second star of Ursa Major". The mapping walks a *frozen* constellation
/// order, lighting each figure brightest-star-first before moving outward to
/// the next.
///
/// Frozen because the zenith moves hourly and the sky turns through the year:
/// recomputing the order later would silently reshuffle a progression the user
/// is partway through, and ordinal 12 must stay Merak forever once it has been
/// seen. The order is computed once, on first use, from where the user was
/// standing when they started — their sky, anchored to their beginning.
struct SkyProgression: Sendable {
    let constellations: [Constellation]
    private let cumulativeStarCounts: [Int]

    /// The point the sky is centred and ordered on — the user's zenith at first
    /// launch. Everything unlocks outward from here, so it's also where the
    /// chart is drawn from.
    var anchor: EquatorialCoordinate {
        constellations.first?.center
            ?? EquatorialCoordinate(rightAscensionDegrees: 0, declinationDegrees: 0)
    }

    init(constellations: [Constellation]) {
        self.constellations = constellations
        var running = 0
        var cumulative: [Int] = []
        for constellation in constellations {
            running += constellation.starCount
            cumulative.append(running)
        }
        self.cumulativeStarCounts = cumulative
    }

    var totalStars: Int { cumulativeStarCounts.last ?? 0 }

    /// The star a given award ordinal lit. Nil once the whole sky is done.
    func star(forOrdinal ordinal: Int) -> (constellation: Constellation, star: Star)? {
        guard ordinal >= 0, ordinal < totalStars else { return nil }
        // Binary search would be O(log n); with 88 entries a scan reads better.
        for (index, cumulative) in cumulativeStarCounts.enumerated() where ordinal < cumulative {
            let constellation = constellations[index]
            let previous = index == 0 ? 0 : cumulativeStarCounts[index - 1]
            return (constellation, constellation.stars[ordinal - previous])
        }
        return nil
    }

    /// Everything unlocked so far, grouped by constellation, given how many
    /// awards the ledger holds.
    func litStars(awardCount: Int) -> [(constellation: Constellation, litCount: Int)] {
        guard awardCount > 0 else { return [] }
        var result: [(Constellation, Int)] = []
        var remaining = awardCount
        for constellation in constellations {
            guard remaining > 0 else { break }
            let lit = min(remaining, constellation.starCount)
            result.append((constellation, lit))
            remaining -= lit
        }
        return result
    }

    /// The constellation currently being filled in, and progress through it.
    /// Nil when every bundled star is lit.
    func active(awardCount: Int) -> (constellation: Constellation, litCount: Int)? {
        var remaining = awardCount
        for constellation in constellations {
            if remaining < constellation.starCount {
                return (constellation, remaining)
            }
            remaining -= constellation.starCount
        }
        return nil
    }

    /// Constellations completed outright.
    func completed(awardCount: Int) -> [Constellation] {
        litStars(awardCount: awardCount)
            .filter { $0.litCount == $0.constellation.starCount }
            .map(\.constellation)
    }
}

/// Loads the frozen order, computing and storing it on first use.
enum SkyProgressionStore {
    static let orderKey = "sky.progression.order.v1"

    /// The fallback observer when the time zone isn't in the table: the
    /// equator, the one latitude from which every constellation rises.
    static let fallbackPosition = ObserverPosition(latitude: 0, longitude: 0)

    static func load(
        catalog: StarCatalog,
        defaults: UserDefaults = .standard,
        position: ObserverPosition? = nil,
        now: Date = .now
    ) -> SkyProgression {
        if let stored = defaults.stringArray(forKey: orderKey) {
            let ordered = stored.compactMap { catalog.constellation($0) }
            // Only trust the stored order if it still matches the catalogue —
            // a catalogue update that renamed or dropped figures falls through
            // and refreezes rather than silently shrinking the sky.
            if ordered.count == stored.count, !ordered.isEmpty {
                return SkyProgression(constellations: ordered)
            }
        }

        let anchor = position ?? ObserverLocation.approximate() ?? fallbackPosition
        let ordered = catalog.constellationsInUnlockOrder(from: anchor, at: now)
        defaults.set(ordered.map(\.abbreviation), forKey: orderKey)
        return SkyProgression(constellations: ordered)
    }
}
