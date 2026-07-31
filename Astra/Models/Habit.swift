import Foundation
import SwiftData

/// One thing the user is trying to keep.
///
/// Days are stored as `Int` rather than `DayKey` because `#Predicate` can only
/// compare primitives; the `DayKey` accessors are the interface everything else
/// should use.
@Model
final class Habit {
    var id: UUID
    var name: String
    /// Index into the app's fixed palette. The palette itself is a visual
    /// decision and lives with the artifact, not here.
    var colorIndex: Int
    var sortOrder: Int
    var createdOnRaw: Int
    /// Set instead of deleting, so the history a habit produced survives it.
    var archivedOnRaw: Int?

    @Relationship(deleteRule: .cascade, inverse: \Completion.habit)
    var completions: [Completion]

    init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        sortOrder: Int = 0,
        createdOn: DayKey = .today(),
        archivedOn: DayKey? = nil
    ) {
        self.id            = id
        self.name          = name
        self.colorIndex    = colorIndex
        self.sortOrder     = sortOrder
        self.createdOnRaw  = createdOn.rawValue
        self.archivedOnRaw = archivedOn?.rawValue
        self.completions   = []
    }

    var createdOn: DayKey {
        get { DayKey(rawValue: createdOnRaw) }
        set { createdOnRaw = newValue.rawValue }
    }

    var archivedOn: DayKey? {
        get { archivedOnRaw.map(DayKey.init(rawValue:)) }
        set { archivedOnRaw = newValue?.rawValue }
    }

    var isArchived: Bool { archivedOnRaw != nil }

    /// Whether this habit was live on a given day. Backfilling a day before the
    /// habit existed shouldn't be possible, and an archived habit stops
    /// accepting new marks without losing the ones it already has.
    func isActive(on day: DayKey) -> Bool {
        guard day >= createdOn else { return false }
        if let archivedOn { return day < archivedOn }
        return true
    }
}

/// A day on which a habit was kept.
///
/// Only kept days exist as rows — an absent row means "not kept", so a user who
/// tracks four habits for a year stores what they did, not a grid of mostly
/// nothing.
@Model
final class Completion {
    var dayRaw: Int
    var habit: Habit?

    init(day: DayKey, habit: Habit? = nil) {
        self.dayRaw = day.rawValue
        self.habit  = habit
    }

    var day: DayKey {
        get { DayKey(rawValue: dayRaw) }
        set { dayRaw = newValue.rawValue }
    }
}
