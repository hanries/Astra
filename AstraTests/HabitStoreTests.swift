import Testing
import Foundation
import SwiftData
@testable import Astra

@MainActor
struct HabitStoreTests {

    private func makeStore(rule: AwardRule = AnyKeptDayRule()) throws -> (HabitStore, ModelContext) {
        let container = try ModelContainer(
            for: Habit.self, Completion.self, Award.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        return (HabitStore(context: context, rule: rule), context)
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
