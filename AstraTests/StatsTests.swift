import Testing
import Foundation
@testable import Astra

struct StatsTests {

    private func days(_ raws: [Int]) -> Set<DayKey> {
        Set(raws.map(DayKey.init(rawValue:)))
    }

    @Test func consistencyIsKeptOverWindow() throws {
        // 5 of the 10 days ending 2026-07-30.
        let kept = days([20260730, 20260729, 20260727, 20260725, 20260722])
        let value = try #require(Stats.consistency(
            keptDays: kept, window: 10, endingOn: DayKey(rawValue: 20260730)
        ))
        #expect(abs(value - 0.5) < 0.0001)
    }

    @Test func fullWindowIsOne() throws {
        let kept = days([20260728, 20260729, 20260730])
        let value = try #require(Stats.consistency(
            keptDays: kept, window: 3, endingOn: DayKey(rawValue: 20260730)
        ))
        #expect(value == 1.0)
    }

    @Test func emptyWindowIsZeroNotNil() throws {
        let value = try #require(Stats.consistency(
            keptDays: [], window: 7, endingOn: DayKey(rawValue: 20260730)
        ))
        #expect(value == 0.0)
    }

    /// A habit added yesterday should read "1 of 1", not "1 of 30". Without the
    /// floor, every new habit would open at 3% and look like a failure on day one.
    @Test func windowIsClampedToHabitStart() throws {
        let kept = days([20260730])
        let value = try #require(Stats.consistency(
            keptDays: kept,
            window: 30,
            endingOn: DayKey(rawValue: 20260730),
            startingNoEarlierThan: DayKey(rawValue: 20260730)
        ))
        #expect(value == 1.0)
    }

    @Test func floorLaterThanEndYieldsNil() {
        let value = Stats.consistency(
            keptDays: [],
            window: 30,
            endingOn: DayKey(rawValue: 20260730),
            startingNoEarlierThan: DayKey(rawValue: 20260801)
        )
        #expect(value == nil)
    }

    @Test func nonPositiveWindowYieldsNil() {
        #expect(Stats.consistency(keptDays: [], window: 0, endingOn: DayKey(rawValue: 20260730)) == nil)
    }

    @Test func consistencySpansMonthBoundary() throws {
        let kept = days([20260630, 20260701, 20260702])
        let value = try #require(Stats.consistency(
            keptDays: kept, window: 4, endingOn: DayKey(rawValue: 20260702)
        ))
        // Window is Jun 29 – Jul 2; three of those four were kept.
        #expect(abs(value - 0.75) < 0.0001)
    }

    @Test func countsKeptInRange() {
        let kept = days([20260701, 20260705, 20260710, 20260801])
        let count = Stats.keptCount(
            keptDays: kept,
            from: DayKey(rawValue: 20260701),
            to: DayKey(rawValue: 20260731)
        )
        #expect(count == 3)
    }

    @Test func lastKeptIsTheLatest() {
        #expect(Stats.lastKept(keptDays: days([20260701, 20260730, 20260705]))
                == DayKey(rawValue: 20260730))
        #expect(Stats.lastKept(keptDays: []) == nil)
    }

    @Test func unionsDaysAcrossHabits() {
        let union = Stats.daysWithAnyKeeping([
            days([20260701, 20260702]),
            days([20260702, 20260703]),
        ])
        #expect(union == days([20260701, 20260702, 20260703]))
    }
}
