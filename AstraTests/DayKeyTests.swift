import Testing
import Foundation
@testable import Astra

struct DayKeyTests {

    @Test func packsComponents() {
        let day = DayKey(rawValue: 20260730)
        #expect(day.year == 2026)
        #expect(day.month == 7)
        #expect(day.day == 30)
        #expect(day.description == "2026-07-30")
    }

    @Test func ordersChronologically() {
        #expect(DayKey(rawValue: 20260101) < DayKey(rawValue: 20260102))
        #expect(DayKey(rawValue: 20251231) < DayKey(rawValue: 20260101))
        #expect(DayKey(rawValue: 20260930) < DayKey(rawValue: 20261001))
    }

    @Test func advancesAcrossMonthBoundary() {
        #expect(DayKey(rawValue: 20260131).advanced(by: 1) == DayKey(rawValue: 20260201))
        #expect(DayKey(rawValue: 20260301).advanced(by: -1) == DayKey(rawValue: 20260228))
    }

    @Test func advancesAcrossYearBoundary() {
        #expect(DayKey(rawValue: 20261231).advanced(by: 1) == DayKey(rawValue: 20270101))
        #expect(DayKey(rawValue: 20260101).advanced(by: -1) == DayKey(rawValue: 20251231))
    }

    @Test func handlesLeapDay() {
        #expect(DayKey(rawValue: 20280228).advanced(by: 1) == DayKey(rawValue: 20280229))
        #expect(DayKey(rawValue: 20260228).advanced(by: 1) == DayKey(rawValue: 20260301))
    }

    @Test func countsDaysBetween() {
        #expect(DayKey(rawValue: 20260101).days(to: DayKey(rawValue: 20260131)) == 30)
        #expect(DayKey(rawValue: 20260131).days(to: DayKey(rawValue: 20260101)) == -30)
        #expect(DayKey(rawValue: 20260101).days(to: DayKey(rawValue: 20260101)) == 0)
    }

    @Test func buildsInclusiveRanges() {
        let span = DayKey(rawValue: 20260228).through(DayKey(rawValue: 20260302))
        #expect(span.map(\.rawValue) == [20260228, 20260301, 20260302])
    }

    @Test func rangeIsEmptyWhenReversed() {
        #expect(DayKey(rawValue: 20260302).through(DayKey(rawValue: 20260228)).isEmpty)
    }

    /// The reason days are integers at all: the same instant read in two
    /// timezones is two different days, so the day has to be decided once and
    /// then left alone.
    @Test func sameInstantIsDifferentDaysInDifferentZones() {
        // 2026-07-30 16:00 UTC — still the 30th in LA, already the 31st in Tokyo.
        let instant = Date(timeIntervalSince1970: 1_785_427_200)

        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        #expect(DayKey(instant, in: la) == DayKey(rawValue: 20260730))
        #expect(DayKey(instant, in: tokyo) == DayKey(rawValue: 20260731))
    }

    /// Advancing goes through noon so a spring-forward transition can't shave
    /// the day back to where it started.
    @Test func survivesDaylightSavingTransition() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        // US DST begins 2026-03-08.
        let before = DayKey(rawValue: 20260307)
        #expect(before.advanced(by: 1, in: la) == DayKey(rawValue: 20260308))
        #expect(before.advanced(by: 2, in: la) == DayKey(rawValue: 20260309))
    }
}
