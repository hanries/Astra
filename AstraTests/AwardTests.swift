import Testing
import Foundation
import SwiftData
@testable import Astra

@MainActor
struct AwardTests {

    /// Passing no rule uses the app's own default, so these tests exercise what
    /// actually ships. The helper used to default to `AnyKeptDayRule` itself,
    /// which quietly meant no test ever checked the shipped rule at all.
    private func makeStore(rule: AwardRule? = nil) throws -> HabitStore {
        let container = try ModelContainer(
            for: Habit.self, Completion.self, Award.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        if let rule {
            return HabitStore(context: context, rule: rule)
        }
        return HabitStore(context: context)
    }

    @Test func keepingADayEarnsAnUnlock() throws {
        let store = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)

        #expect(try store.awardCount() == 0)
        try store.setKept(habit, on: store.today(), kept: true)
        #expect(try store.awardCount() == 1)
    }

    /// A complete day pays once however many habits it took, so adding a habit
    /// is never a way to farm the collection.
    @Test func oneUnlockPerDayRegardlessOfHabitCount() throws {
        let store = try makeStore()
        let today = store.today()
        for i in 0..<4 {
            let habit = try store.addHabit(name: "Habit \(i)", colorIndex: i)
            try store.setKept(habit, on: today, kept: true)
        }
        #expect(try store.awardCount() == 1)
    }

    /// The shipped default requires the whole day. Pinned here because it's a
    /// behavioural choice rather than an implementation detail — a star means
    /// "I did everything I set out to", and silently loosening that would
    /// change what every star in the sky stands for.
    @Test func theDefaultRuleRequiresACompleteDay() throws {
        let store = try makeStore()
        let today = store.today()
        let read = try store.addHabit(name: "Read", colorIndex: 0)
        let run = try store.addHabit(name: "Run", colorIndex: 1)
        let stretch = try store.addHabit(name: "Stretch", colorIndex: 2)

        try store.setKept(read, on: today, kept: true)
        try store.setKept(run, on: today, kept: true)
        #expect(try store.awardCount() == 0, "two of three paid out")

        try store.setKept(stretch, on: today, kept: true)
        #expect(try store.awardCount() == 1)
    }

    /// What a partial day costs is the next star, never one already in the sky.
    @Test func anIncompleteDayLeavesEarlierStarsAlone() throws {
        let store = try makeStore()
        let today = store.today()
        let read = try store.addHabit(name: "Read", colorIndex: 0)
        read.createdOn = today.advanced(by: -3)

        // A complete day two days ago.
        try store.setKept(read, on: today.advanced(by: -2), kept: true)
        #expect(try store.awardCount() == 1)

        // A second habit arrives, and today goes unfinished.
        let run = try store.addHabit(name: "Run", colorIndex: 1)
        try store.setKept(read, on: today, kept: true)
        #expect(try store.awardCount() == 1, "an unfinished day took back a star")

        try store.setKept(run, on: today, kept: true)
        #expect(try store.awardCount() == 2)
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

    /// The strict alternative: a partial day earns nothing, and the star only
    /// arrives once everything is kept.
    @Test func allKeptRuleWaitsForTheWholeDay() throws {
        let store = try makeStore(rule: AllKeptDayRule())
        let today = store.today()
        let read = try store.addHabit(name: "Read", colorIndex: 0)
        let run = try store.addHabit(name: "Run", colorIndex: 1)

        try store.setKept(read, on: today, kept: true)
        #expect(try store.awardCount() == 0, "a partial day paid out")

        try store.setKept(run, on: today, kept: true)
        #expect(try store.awardCount() == 1)
    }

    /// ...and once earned it stays earned, like every other unlock here.
    @Test func allKeptRuleStillNeverRevokes() throws {
        let store = try makeStore(rule: AllKeptDayRule())
        let today = store.today()
        let read = try store.addHabit(name: "Read", colorIndex: 0)
        let run = try store.addHabit(name: "Run", colorIndex: 1)

        try store.setKept(read, on: today, kept: true)
        try store.setKept(run, on: today, kept: true)
        try store.setKept(run, on: today, kept: false)
        #expect(try store.awardCount() == 1)
    }

    /// A habit added today must not retroactively make a finished day
    /// incomplete — only habits that were live on a day can be required of it.
    @Test func allKeptRuleIgnoresHabitsThatDidNotExistYet() throws {
        let store = try makeStore(rule: AllKeptDayRule())
        let yesterday = store.today().advanced(by: -1)

        let read = try store.addHabit(name: "Read", colorIndex: 0)
        read.createdOn = yesterday
        try store.setKept(read, on: yesterday, kept: true)
        #expect(try store.awardCount() == 1)

        try store.addHabit(name: "Run", colorIndex: 1)
        try store.reconcileAwards(on: yesterday)
        #expect(try store.awardCount() == 1, "yesterday was un-completed by a new habit")
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
