import Foundation

/// Pure functions over sets of kept days.
///
/// Separated from `HabitStore` so the arithmetic can be tested without standing
/// up a `ModelContext`, and so the rules stay readable in one place.
///
/// There is deliberately no `currentStreak` here. A streak is a number whose
/// only move is down, and protecting it is what makes people stop opening the
/// app after one bad week. `consistency` dips and recovers instead.
enum Stats {

    /// Share of days kept in the window ending on `endingOn`, as 0...1.
    ///
    /// The window is clamped to `startingNoEarlierThan` — usually the day the
    /// habit was created — so a habit added yesterday reads as "1 of 1", not
    /// "1 of 30". Returns nil when the window contains no days the habit could
    /// have been kept on, which is a different thing from 0%.
    static func consistency(
        keptDays: Set<DayKey>,
        window: Int,
        endingOn end: DayKey,
        startingNoEarlierThan floor: DayKey? = nil,
        calendar: Calendar = .current
    ) -> Double? {
        guard window > 0 else { return nil }
        var start = end.advanced(by: -(window - 1), in: calendar)
        if let floor, floor > start { start = floor }
        guard start <= end else { return nil }

        let span = start.through(end, in: calendar)
        guard !span.isEmpty else { return nil }
        let kept = span.count { keptDays.contains($0) }
        return Double(kept) / Double(span.count)
    }

    /// Days kept within an inclusive range.
    static func keptCount(keptDays: Set<DayKey>, from start: DayKey, to end: DayKey) -> Int {
        keptDays.count { $0 >= start && $0 <= end }
    }

    /// The most recent day kept, if any.
    static func lastKept(keptDays: Set<DayKey>) -> DayKey? {
        keptDays.max()
    }

    /// Days on which at least one habit was kept.
    static func daysWithAnyKeeping(_ perHabit: [Set<DayKey>]) -> Set<DayKey> {
        perHabit.reduce(into: Set<DayKey>()) { $0.formUnion($1) }
    }
}
