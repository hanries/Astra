#if DEBUG
import Foundation
import SwiftData
import SwiftUI

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

    /// Deletes fetched instances rather than using `delete(model:)`.
    ///
    /// The batch form fails here with "mandatory OTO nullify inverse on
    /// Completion/habit" — it doesn't resolve the cascade from `Habit` to its
    /// completions, so the store rejects the delete. Removing each completion
    /// first, saving, then removing the habits works because by then nothing
    /// points at them.
    /// Sends the app back to first launch.
    ///
    /// Only clears the seen flag — the frozen sky order and anything already
    /// tracked stay put, so the flow can be replayed against real data. For a
    /// true cold start, clear first and then replay.
    static func replayOnboarding() {
        UserDefaults.standard.set(false, forKey: OnboardingView.seenKey)
    }

    /// Everything back to a genuinely new install: habits, ledger, the frozen
    /// sky order and the onboarding flag.
    static func resetEverything(context: ModelContext) throws {
        try clear(context: context)
        UserDefaults.standard.removeObject(forKey: SkyProgressionStore.orderKey)
        UserDefaults.standard.removeObject(forKey: SkyProgressionStore.anchorKey)
        replayOnboarding()
    }

    static func clear(context: ModelContext) throws {
        for completion in try context.fetch(FetchDescriptor<Completion>()) {
            context.delete(completion)
        }
        try context.save()

        for award in try context.fetch(FetchDescriptor<Award>()) {
            context.delete(award)
        }
        for habit in try context.fetch(FetchDescriptor<Habit>()) {
            context.delete(habit)
        }
        try context.save()
    }
}
#endif
