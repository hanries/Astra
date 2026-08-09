import Testing
import Foundation
@testable import Astra

/// The handoff from app to widget.
///
/// The app publishes a run of unlocks; the widget indexes into it by how many
/// stars are lit. The widget can light one itself, so the two are not always
/// looking at the same award count — which is the whole reason the run carries
/// its base rather than just naming the next star.
struct UpcomingRunTests {

    private func run(base: Int, _ names: [String]) -> AstraStore.UpcomingRun {
        AstraStore.UpcomingRun(
            base: base,
            unlocks: names.enumerated().map { offset, name in
                AstraStore.Unlock(star: name, figure: "Lyra", lit: offset, total: names.count)
            }
        )
    }

    @Test func namesTheStarForTheCurrentCount() {
        let published = run(base: 4, ["Vega", "Beta Lyr", "Gamma Lyr"])

        #expect(published.unlock(forAwardCount: 4)?.star == "Vega")
        #expect(published.unlock(forAwardCount: 5)?.star == "Beta Lyr")
        #expect(published.unlock(forAwardCount: 6)?.star == "Gamma Lyr")
    }

    /// The case the run exists for: the widget marked the last habit itself, so
    /// it is a star ahead of the app that published this.
    @Test func followsAStarLitByTheWidget() {
        let published = run(base: 0, ["Vega", "Beta Lyr"])

        #expect(published.unlock(forAwardCount: 1)?.star == "Beta Lyr")
    }

    /// Past the end, nothing. Naming a star that is already lit would be worse
    /// than an empty corner of the widget.
    @Test func staysSilentPastTheEnd() {
        let published = run(base: 0, ["Vega"])

        #expect(published.unlock(forAwardCount: 1) == nil)
        #expect(published.unlock(forAwardCount: 99) == nil)
    }

    /// Reinstalling, or clearing the sky, can leave a widget asking about a
    /// count below the run. It must not wrap around to the end of the array.
    @Test func staysSilentBelowTheBase() {
        let published = run(base: 3, ["Vega", "Beta Lyr"])

        #expect(published.unlock(forAwardCount: 2) == nil)
        #expect(published.unlock(forAwardCount: 0) == nil)
    }

    @Test func survivesTheTripThroughDefaults() throws {
        let published = run(base: 2, ["Vega", "Beta Lyr"])

        let data = try JSONEncoder().encode(published)
        let restored = try JSONDecoder().decode(AstraStore.UpcomingRun.self, from: data)

        #expect(restored == published)
        #expect(restored.unlock(forAwardCount: 3)?.star == "Beta Lyr")
    }
}
