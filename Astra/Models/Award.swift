import Foundation
import SwiftData

/// One unlock, earned by keeping a habit.
///
/// This is deliberately empty of meaning. It records *that* something was
/// unlocked and in what order — never what the thing looks like. Whatever the
/// artifact turns out to be (a star, a tile, a species) maps `ordinal` to its
/// own catalog, so the reward ledger doesn't have to be rewritten when that
/// decision lands.
@Model
final class Award {
    /// Order of discovery, 0-based. The catalog's index.
    ///
    /// Discovery order, not chronological order: backfilling a day from last
    /// week hands out the *next* ordinal rather than inserting one in the
    /// middle. Renumbering would silently change what the user already
    /// unlocked, so ordinals are only ever appended.
    var ordinal: Int
    /// The day whose keeping earned it.
    var dayRaw: Int
    /// What earned it within that day — empty for a whole-day award, otherwise
    /// a habit's `id`. Together with `dayRaw` this is what stops one day from
    /// paying out twice.
    var slot: String
    var earnedAt: Date

    init(ordinal: Int, day: DayKey, slot: String = "", earnedAt: Date = .now) {
        self.ordinal  = ordinal
        self.dayRaw   = day.rawValue
        self.slot     = slot
        self.earnedAt = earnedAt
    }

    var day: DayKey {
        get { DayKey(rawValue: dayRaw) }
        set { dayRaw = newValue.rawValue }
    }
}

/// Decides what a day's keeping is worth.
///
/// Swappable because the exchange rate is a design question that isn't settled:
/// one unlock per day you showed up at all, or one per habit kept, changes how
/// fast a collection fills and how much five habits inflate it.
protocol AwardRule {
    /// The slots earned on a day. One `Award` per returned element; the strings
    /// become `Award.slot` and must be stable across runs for the same input.
    func slots(keptHabitIDs: [UUID]) -> [String]
}

/// One unlock for any day you kept at least one habit.
///
/// The default. Keeps a five-habit user and a one-habit user earning at the
/// same rate, so adding a habit never feels like farming.
struct AnyKeptDayRule: AwardRule {
    func slots(keptHabitIDs: [UUID]) -> [String] {
        keptHabitIDs.isEmpty ? [] : [""]
    }
}

/// One unlock per habit kept.
struct PerHabitRule: AwardRule {
    func slots(keptHabitIDs: [UUID]) -> [String] {
        keptHabitIDs.map(\.uuidString).sorted()
    }
}
