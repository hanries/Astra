import Foundation

/// A calendar day, stored as `yyyyMMdd` — 30 July 2026 is `20260730`.
///
/// Days are integers rather than `Date`s on purpose. A `Date` is an instant, so
/// "which day is that?" depends on the timezone you ask in. Store instants and a
/// user who flies from Tokyo to LA can watch yesterday's log slide onto a
/// different row. An integer day is decided once, in the user's calendar at the
/// moment they tap, and is never re-derived from a timezone again.
struct DayKey: Hashable, Comparable, Codable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(_ date: Date, in calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = (c.year ?? 1970) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    static func today(in calendar: Calendar = .current) -> DayKey {
        DayKey(.now, in: calendar)
    }

    var year:  Int { rawValue / 10_000 }
    var month: Int { (rawValue / 100) % 100 }
    var day:   Int { rawValue % 100 }

    /// Noon on this day, so that adding or subtracting days can't trip over a
    /// DST transition and land on the day before.
    func date(in calendar: Calendar = .current) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        return calendar.date(from: c) ?? .distantPast
    }

    func advanced(by days: Int, in calendar: Calendar = .current) -> DayKey {
        guard days != 0 else { return self }
        let moved = calendar.date(byAdding: .day, value: days, to: date(in: calendar))
        return DayKey(moved ?? date(in: calendar), in: calendar)
    }

    /// Whole days from `self` to `other`. Negative when `other` is earlier.
    func days(to other: DayKey, in calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(in: calendar), to: other.date(in: calendar)).day ?? 0
    }

    /// Every day from `self` through `end`, inclusive. Empty if `end` precedes `self`.
    func through(_ end: DayKey, in calendar: Calendar = .current) -> [DayKey] {
        guard self <= end else { return [] }
        var days: [DayKey] = []
        var cursor = self
        while cursor <= end {
            days.append(cursor)
            cursor = cursor.advanced(by: 1, in: calendar)
        }
        return days
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension DayKey: CustomStringConvertible {
    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
