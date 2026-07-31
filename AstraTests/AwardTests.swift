import Testing
import Foundation
import SwiftData
@testable import Astra

@MainActor
struct AwardTests {

    private func makeStore(rule: AwardRule = AnyKeptDayRule()) throws -> HabitStore {
        let container = try ModelContainer(
            for: Habit.self, Completion.self, Award.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return HabitStore(context: ModelContext(container), rule: rule)
    }

    @Test func keepingADayEarnsAnUnlock() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)

        #expect(try store.awardCount() == 0)
        try store.setKept(habit, on: store.today(), kept: true)
        #expect(try store.awardCount() == 1)
    }

    /// Five habits and one habit unlock at the same rate, so adding a habit is
    /// never a way to farm the collection.
    @Test func oneUnlockPerDayRegardlessOfHabitCount() throws {
        let store = try makeStore()
        let today = store.today()
        for i in 0..<4 {
            let habit = try store.addHabit(name: "Habit \(i)", colorIndex: i)
            try store.setKept(habit, on: today, kept: true)
        }
        #expect(try store.awardCount() == 1)
    }

    @Test func perHabitRuleUnlocksOncePerHabit() throws {
        let store = try makeStore(rule: PerHabitRule())
        let today = store.today()
        for i in 0..<3 {
            let habit = try store.addHabit(name: "Habit \(i)", colorIndex: i)
            try store.setKept(habit, on: today, kept: true)
        }
        #expect(try store.awardCount() == 3)
    }

    @Test func separateDaysEarnSeparateUnlocks() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        habit.createdOn = store.today().advanced(by: -5)

        for offset in 0..<4 {
            try store.setKept(habit, on: store.today().advanced(by: -offset), kept: true)
        }
        #expect(try store.awardCount() == 4)
    }

    /// The whole point of the ledger: nothing you earned is ever taken back.
    /// A broken week costs you future unlocks, not past ones.
    @Test func unmarkingADayDoesNotRevokeItsUnlock() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        let today = store.today()

        try store.setKept(habit, on: today, kept: true)
        #expect(try store.awardCount() == 1)

        try store.setKept(habit, on: today, kept: false)
        #expect(store.isKept(habit, on: today) == false)
        #expect(try store.awardCount() == 1)
    }

    /// ...and re-marking it doesn't pay a second time, so toggling isn't a farm.
    @Test func retogglingADayDoesNotPayTwice() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        let today = store.today()

        for _ in 0..<5 {
            try store.setKept(habit, on: today, kept: true)
            try store.setKept(habit, on: today, kept: false)
        }
        #expect(try store.awardCount() == 1)
    }

    /// Ordinals are handed out in discovery order, not date order. Backfilling
    /// last Tuesday must not renumber what the user already unlocked — ordinal
    /// 3 has to stay whatever object it was the day they saw it.
    @Test func backfillAppendsRatherThanRenumbering() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        habit.createdOn = store.today().advanced(by: -10)
        let today = store.today()

        try store.setKept(habit, on: today.advanced(by: -2), kept: true)
        try store.setKept(habit, on: today.advanced(by: -1), kept: true)
        try store.setKept(habit, on: today, kept: true)

        let beforeBackfill = try store.allAwards()
        #expect(beforeBackfill.map(\.ordinal) == [0, 1, 2])

        // Now remember a day from further back.
        try store.setKept(habit, on: today.advanced(by: -6), kept: true)

        let after = try store.allAwards()
        #expect(after.count == 4)
        #expect(after.map(\.ordinal) == [0, 1, 2, 3])

        // The three that already existed still point at the same days.
        for old in beforeBackfill {
            let match = after.first { $0.ordinal == old.ordinal }
            #expect(match?.dayRaw == old.dayRaw)
        }
        // The newcomer took the end of the queue despite being the oldest day.
        let newest = after.first { $0.ordinal == 3 }
        #expect(newest?.day == today.advanced(by: -6))
    }

    @Test func reconcileAllIsIdempotent() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        habit.createdOn = store.today().advanced(by: -4)

        for offset in 0..<3 {
            try store.setKept(habit, on: store.today().advanced(by: -offset), kept: true)
        }
        let before = try store.awardCount()

        try store.reconcileAllAwards()
        try store.reconcileAllAwards()

        #expect(try store.awardCount() == before)
    }
}
