import Foundation
import SwiftData

enum HabitStoreError: LocalizedError {
    case tooManyHabits(limit: Int)
    case habitNotActive(on: DayKey)

    var errorDescription: String? {
        switch self {
        case .tooManyHabits(let limit):
            "You can track \(limit) habits at once."
        case .habitNotActive(let day):
            "That habit wasn't being tracked on \(day)."
        }
    }
}

/// Every mutation the app makes to habits, completions, and the award ledger.
///
/// Views read with `@Query` and write through here, so the rules about caps,
/// backfilling, and unlocks live in one testable place rather than in buttons.
final class HabitStore {

    /// Five columns is both the behavioural limit — people who add eight habits
    /// on day one have quit by day seven — and the visual one, past which rows
    /// get too thin to read.
    static let maxActiveHabits = 5

    private let context: ModelContext
    private let calendar: Calendar
    private let rule: AwardRule

    /// A star is earned for a *complete* day — every habit that was live on it,
    /// kept. A partial day earns nothing new.
    ///
    /// The forgiving part of the design lives elsewhere and still holds: a star
    /// once earned is never revoked, consistency dips and recovers rather than
    /// resetting, and any day can be corrected afterwards. What a partial day
    /// costs is the *next* star, never one already in the sky.
    init(context: ModelContext, calendar: Calendar = .current, rule: AwardRule = AllKeptDayRule()) {
        self.context  = context
        self.calendar = calendar
        self.rule     = rule
    }

    func today() -> DayKey { .today(in: calendar) }

    // MARK: - Habits

    func allHabits(includingArchived: Bool = false) throws -> [Habit] {
        let all = try context.fetch(
            FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdOnRaw)])
        )
        return includingArchived ? all : all.filter { !$0.isArchived }
    }

    @discardableResult
    func addHabit(name: String, colorIndex: Int) throws -> Habit {
        let active = try allHabits()
        guard active.count < Self.maxActiveHabits else {
            throw HabitStoreError.tooManyHabits(limit: Self.maxActiveHabits)
        }
        let habit = Habit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorIndex: colorIndex,
            sortOrder: (active.map(\.sortOrder).max() ?? -1) + 1,
            createdOn: today()
        )
        context.insert(habit)
        try context.save()
        return habit
    }

    func rename(_ habit: Habit, to name: String) throws {
        habit.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func setColor(_ habit: Habit, to colorIndex: Int) throws {
        habit.colorIndex = colorIndex
        try context.save()
    }

    /// Retires a habit without deleting what it recorded. Its past keeping still
    /// counts, and its awards are already spent — nothing the user earned goes
    /// away because they stopped tracking something.
    func archive(_ habit: Habit) throws {
        guard !habit.isArchived else { return }
        habit.archivedOn = today()
        try context.save()
    }

    func unarchive(_ habit: Habit) throws {
        guard habit.isArchived else { return }
        guard try allHabits().count < Self.maxActiveHabits else {
            throw HabitStoreError.tooManyHabits(limit: Self.maxActiveHabits)
        }
        habit.archivedOn = nil
        try context.save()
    }

    /// Applies the order of `ordered` to `sortOrder`.
    func reorder(_ ordered: [Habit]) throws {
        for (index, habit) in ordered.enumerated() {
            habit.sortOrder = index
        }
        try context.save()
    }

    // MARK: - Keeping

    func isKept(_ habit: Habit, on day: DayKey) -> Bool {
        habit.completions.contains { $0.dayRaw == day.rawValue }
    }

    /// Marks or unmarks a day.
    ///
    /// Any day the habit was live on can be edited, not just today — a tracker
    /// you can't correct after the fact is one people abandon the first time
    /// they forget to log before bed.
    func setKept(_ habit: Habit, on day: DayKey, kept: Bool) throws {
        guard habit.isActive(on: day) else {
            throw HabitStoreError.habitNotActive(on: day)
        }
        let existing = habit.completions.filter { $0.dayRaw == day.rawValue }

        if kept {
            guard existing.isEmpty else { return }
            let completion = Completion(day: day, habit: habit)
            context.insert(completion)
        } else {
            guard !existing.isEmpty else { return }
            for completion in existing { context.delete(completion) }
        }

        try context.save()
        try reconcileAwards(on: day)
    }

    @discardableResult
    func toggle(_ habit: Habit, on day: DayKey) throws -> Bool {
        let next = !isKept(habit, on: day)
        try setKept(habit, on: day, kept: next)
        return next
    }

    func keptHabits(on day: DayKey) throws -> [Habit] {
        try allHabits(includingArchived: true).filter { isKept($0, on: day) }
    }

    func keptDays(for habit: Habit) -> Set<DayKey> {
        Set(habit.completions.map(\.day))
    }

    /// The first day anything was tracked — where a timeline starts.
    func firstTrackedDay() throws -> DayKey? {
        try allHabits(includingArchived: true).map(\.createdOn).min()
    }

    // MARK: - Awards

    func allAwards() throws -> [Award] {
        try context.fetch(FetchDescriptor<Award>(sortBy: [SortDescriptor(\.ordinal)]))
    }

    func awardCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Award>())
    }

    /// Grants anything `day` has earned and isn't holding yet.
    ///
    /// Only ever appends. Unchecking a day you already collected for does not
    /// take the unlock back — the ledger is a record of days you showed up, and
    /// nothing in this app removes those. It also can't pay twice for the same
    /// day, so toggling isn't a way to farm.
    func reconcileAwards(on day: DayKey) throws {
        let keptIDs = try keptHabits(on: day).map(\.id)
        // What the day could have had, so a rule that cares about completeness
        // can tell "all three kept" from "one of three".
        let liveCount = try allHabits(includingArchived: true).count { $0.isActive(on: day) }
        let deserved = rule.slots(keptHabitIDs: keptIDs, activeHabitCount: liveCount)
        guard !deserved.isEmpty else { return }

        let raw = day.rawValue
        let held = try context.fetch(
            FetchDescriptor<Award>(predicate: #Predicate { $0.dayRaw == raw })
        )
        let heldSlots = Set(held.map(\.slot))
        let missing = deserved.filter { !heldSlots.contains($0) }
        guard !missing.isEmpty else { return }

        var next = try nextOrdinal()
        for slot in missing {
            context.insert(Award(ordinal: next, day: day, slot: slot))
            next += 1
        }
        try context.save()
    }

    /// Rebuilds the ledger across the whole history. For recovery and for
    /// migrations if the rule ever changes — not part of the normal path.
    func reconcileAllAwards() throws {
        guard let start = try firstTrackedDay() else { return }
        for day in start.through(today(), in: calendar) {
            try reconcileAwards(on: day)
        }
    }

    private func nextOrdinal() throws -> Int {
        var descriptor = FetchDescriptor<Award>(sortBy: [SortDescriptor(\.ordinal, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try context.fetch(descriptor).first?.ordinal ?? -1) + 1
    }
}
