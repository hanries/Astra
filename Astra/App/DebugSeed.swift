#if DEBUG
import Foundation
import SwiftData

/// Fills the store with plausible history so long-horizon views can be looked
/// at without waiting months for them.
///
/// A progression measured in figures completed can't be designed against a
/// single lit star — the question "does this feel earned at six weeks?" needs
/// six weeks on screen. DEBUG only; never compiled into a release build.
enum DebugSeed {

    /// Backdates the habits and marks `days` of history, keeping roughly
    /// `keepRate` of them so the calendar shows gaps rather than a perfect wall.
    static func fill(
        context: ModelContext,
        days: Int = 60,
        keepRate: Double = 0.8
    ) throws {
        let store = HabitStore(context: context)
        var habits = try store.allHabits()

        if habits.isEmpty {
            try store.addHabit(name: "Work out for an hour", colorIndex: 0)
            try store.addHabit(name: "Read before bed", colorIndex: 1)
            habits = try store.allHabits()
        }

        let today = store.today()
        for habit in habits {
            habit.createdOn = today.advanced(by: -days)
        }

        // Seeded rather than random so the same build always produces the same
        // sky — comparing two screenshots should show design changes, not noise.
        var seed: UInt64 = 20_260_802
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }

        for offset in stride(from: days, through: 0, by: -1) {
            let day = today.advanced(by: -offset)
            for habit in habits where next() < keepRate {
                try store.setKept(habit, on: day, kept: true)
            }
        }
    }

    static func clear(context: ModelContext) throws {
        try context.delete(model: Completion.self)
        try context.delete(model: Award.self)
        try context.delete(model: Habit.self)
        try context.save()
    }
}
#endif
