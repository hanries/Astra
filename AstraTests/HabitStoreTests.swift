import Testing
import Foundation
import SwiftData
@testable import Astra

@MainActor
struct HabitStoreTests {

    /// Passing no rule uses the app's own default, so these exercise what ships.
    /// This helper used to default to `AnyKeptDayRule` itself, which meant a
    /// test could assert award behaviour and never touch the shipped rule.
    private func makeStore(rule: AwardRule? = nil) throws -> (HabitStore, ModelContext) {
        let container = try ModelContainer(
            for: Habit.self, Completion.self, Award.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let store = rule.map { HabitStore(context: context, rule: $0) }
            ?? HabitStore(context: context)
        return (store, context)
    }

    // MARK: - Habits

    @Test func addsAndListsHabits() throws {
        let (store, _) = try makeStore()
        try store.addHabit(name: "Read", colorIndex: 0)
        try store.addHabit(name: "Run", colorIndex: 1)

        let habits = try store.allHabits()
        #expect(habits.map(\.name) == ["Read", "Run"])
        #expect(habits.map(\.sortOrder) == [0, 1])
    }

    @Test func trimsWhitespaceFromNames() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "  Stretch\n", colorIndex: 0)
        #expect(habit.name == "Stretch")
    }

    @Test func refusesMoreThanFiveActiveHabits() throws {
        let (store, _) = try makeStore()
        for i in 0..<HabitStore.maxActiveHabits {
            try store.addHabit(name: "Habit \(i)", colorIndex: i)
        }
        #expect(throws: HabitStoreError.self) {
            try store.addHabit(name: "One too many", colorIndex: 0)
        }
    }

    /// The cap is on *active* habits — retiring one makes room.
    @Test func archivingFreesASlot() throws {
        let (store, _) = try makeStore()
        var made: [Habit] = []
        for i in 0..<HabitStore.maxActiveHabits {
            made.append(try store.addHabit(name: "Habit \(i)", colorIndex: i))
        }
        try store.archive(made[0])
        try store.addHabit(name: "Replacement", colorIndex: 0)
        #expect(try store.allHabits().count == HabitStore.maxActiveHabits)
    }

    @Test func archivingKeepsHistory() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        habit.createdOn = store.today().advanced(by: -7)
        let yesterday = store.today().advanced(by: -1)
        try store.setKept(habit, on: yesterday, kept: true)

        try store.archive(habit)

        #expect(habit.isArchived)
        #expect(store.isKept(habit, on: yesterday))
        #expect(try store.allHabits().isEmpty)
        #expect(try store.allHabits(includingArchived: true).count == 1)
    }

    @Test func reorderRewritesSortOrder() throws {
        let (store, _) = try makeStore()
        let a = try store.addHabit(name: "A", colorIndex: 0)
        let b = try store.addHabit(name: "B", colorIndex: 1)
        let c = try store.addHabit(name: "C", colorIndex: 2)

        try store.reorder([c, a, b])
        #expect(try store.allHabits().map(\.name) == ["C", "A", "B"])
    }

    @Test func renameAndRecolour() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Reed", colorIndex: 0)

        try store.rename(habit, to: "  Read before bed  ")
        try store.setColor(habit, to: 3)
        #expect(habit.name == "Read before bed")
        #expect(habit.colorIndex == 3)
    }

    // MARK: - Removing

    /// A habit added by mistake goes completely. Leaving a typo sitting in an
    /// archive forever isn't a kindness.
    @Test func deletesAHabitWithNoHistory() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Typoo", colorIndex: 0)
        #expect(store.canDelete(habit))

        try store.delete(habit)
        #expect(try store.allHabits(includingArchived: true).isEmpty)
    }

    /// A habit with days against it can only stop, never vanish — deleting
    /// would quietly rewrite days the user actually kept.
    @Test func refusesToDeleteAHabitWithHistory() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        try store.setKept(habit, on: store.today(), kept: true)

        #expect(store.canDelete(habit) == false)
        #expect(throws: HabitStoreError.self) { try store.delete(habit) }
        #expect(try store.allHabits().count == 1)
    }

    /// Deleting leaves the ledger alone: a star belongs to the day it was
    /// earned, not to a habit.
    @Test func deletingNeverTakesBackAStar() throws {
        let (store, _) = try makeStore()
        let keeper = try store.addHabit(name: "Read", colorIndex: 0)
        try store.setKept(keeper, on: store.today(), kept: true)
        #expect(try store.awardCount() == 1)

        let spare = try store.addHabit(name: "Mistake", colorIndex: 1)
        try store.delete(spare)
        #expect(try store.awardCount() == 1)
    }

    /// Stopping a habit can finish the day — two habits with one kept becomes
    /// one habit, kept. Without reconciling on archive the screen would read
    /// "everything kept" while no star was ever granted.
    @Test func archivingCanCompleteTheDay() throws {
        let (store, _) = try makeStore()
        let today = store.today()
        let read = try store.addHabit(name: "Read", colorIndex: 0)
        let run = try store.addHabit(name: "Run", colorIndex: 1)

        try store.setKept(read, on: today, kept: true)
        #expect(try store.awardCount() == 0)

        try store.archive(run)
        #expect(try store.awardCount() == 1, "the day never paid out after the other habit stopped")
    }

    @Test func unarchiveRestoresAHabit() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        try store.archive(habit)
        #expect(try store.allHabits().isEmpty)

        try store.unarchive(habit)
        #expect(try store.allHabits().count == 1)
        #expect(habit.isArchived == false)
    }

    @Test func unarchiveRefusesWhenSlotsAreFull() throws {
        let (store, _) = try makeStore()
        let retired = try store.addHabit(name: "Old", colorIndex: 0)
        try store.archive(retired)
        for i in 0..<HabitStore.maxActiveHabits {
            try store.addHabit(name: "Habit \(i)", colorIndex: i)
        }
        #expect(throws: HabitStoreError.self) { try store.unarchive(retired) }
    }

    // MARK: - Keeping

    @Test func togglesToday() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        let today = store.today()

        #expect(store.isKept(habit, on: today) == false)
        #expect(try store.toggle(habit, on: today) == true)
        #expect(store.isKept(habit, on: today))
        #expect(try store.toggle(habit, on: today) == false)
        #expect(store.isKept(habit, on: today) == false)
    }

    @Test func markingTwiceDoesNotDuplicate() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        let today = store.today()

        try store.setKept(habit, on: today, kept: true)
        try store.setKept(habit, on: today, kept: true)
        #expect(habit.completions.count == 1)
    }

    /// Forgetting to log before bed shouldn't cost you the day.
    @Test func backfillsPastDays() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        habit.createdOn = store.today().advanced(by: -10)

        let threeDaysAgo = store.today().advanced(by: -3)
        try store.setKept(habit, on: threeDaysAgo, kept: true)
        #expect(store.isKept(habit, on: threeDaysAgo))
    }

    /// `createdOn` is the floor on backfilling, and it is load-bearing: because
    /// kept days pay out unlocks, a habit that accepted arbitrary past dates
    /// would let a brand-new user mark a year of history on install and collect
    /// 365 unlocks for nothing. You can correct days you were tracking; you
    /// can't claim days you weren't.
    @Test func refusesDaysBeforeTheHabitExisted() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        let beforeItExisted = habit.createdOn.advanced(by: -1)

        #expect(throws: HabitStoreError.self) {
            try store.setKept(habit, on: beforeItExisted, kept: true)
        }
        #expect(try store.awardCount() == 0)
    }

    @Test func refusesDaysAfterArchiving() throws {
        let (store, _) = try makeStore()
        let habit = try store.addHabit(name: "Read", colorIndex: 0)
        habit.createdOn = store.today().advanced(by: -10)
        habit.archivedOn = store.today().advanced(by: -5)

        #expect(throws: HabitStoreError.self) {
            try store.setKept(habit, on: store.today(), kept: true)
        }
        // The day before archiving is still fair game.
        try store.setKept(habit, on: store.today().advanced(by: -6), kept: true)
    }

    @Test func reportsKeptHabitsForADay() throws {
        let (store, _) = try makeStore()
        let read = try store.addHabit(name: "Read", colorIndex: 0)
        let run = try store.addHabit(name: "Run", colorIndex: 1)
        try store.addHabit(name: "Stretch", colorIndex: 2)
        let today = store.today()

        try store.setKept(read, on: today, kept: true)
        try store.setKept(run, on: today, kept: true)

        #expect(Set(try store.keptHabits(on: today).map(\.name)) == ["Read", "Run"])
    }

    @Test func firstTrackedDayIsTheEarliestHabit() throws {
        let (store, _) = try makeStore()
        let old = try store.addHabit(name: "Old", colorIndex: 0)
        old.createdOn = DayKey(rawValue: 20260101)
        try store.addHabit(name: "New", colorIndex: 1)

        #expect(try store.firstTrackedDay() == DayKey(rawValue: 20260101))
    }
}
