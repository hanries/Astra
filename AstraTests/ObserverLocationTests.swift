import Testing
import Foundation
@testable import Astra

struct ObserverLocationTests {

    private func position(_ identifier: String) throws -> ObserverPosition {
        let zone = try #require(TimeZone(identifier: identifier))
        return try #require(ObserverLocation.approximate(from: zone))
    }

    @Test func resolvesCommonZones() throws {
        let london = try position("Europe/London")
        #expect(abs(london.latitude - 51.51) < 0.01)
        #expect(abs(london.longitude - -0.13) < 0.01)

        let tokyo = try position("Asia/Tokyo")
        #expect(abs(tokyo.latitude - 35.68) < 0.01)
    }

    /// Hemisphere is the part that has to be right — it decides whether a user
    /// ever sees Crux or Ursa Major at all.
    @Test func hemispheresAreCorrect() throws {
        for northern in ["Europe/London", "America/New_York", "Asia/Tokyo", "Africa/Cairo"] {
            #expect(try position(northern).latitude > 0, "\(northern) should be northern")
        }
        for southern in ["Australia/Sydney", "America/Sao_Paulo", "Africa/Johannesburg", "Pacific/Auckland"] {
            #expect(try position(southern).latitude < 0, "\(southern) should be southern")
        }
    }

    @Test func unknownZoneYieldsNil() throws {
        let obscure = try #require(TimeZone(identifier: "Indian/Chagos"))
        #expect(ObserverLocation.approximate(from: obscure) == nil)
    }

    @Test func everyEntryIsAValidCoordinate() throws {
        for identifier in ObserverLocation.knownZoneIdentifiers {
            let place = try position(identifier)
            #expect((-90...90).contains(place.latitude), "\(identifier) latitude out of range")
            #expect((-180...180).contains(place.longitude), "\(identifier) longitude out of range")
        }
    }

    /// Every identifier in the table has to be one the system actually knows,
    /// or it can never match `TimeZone.current` and the entry is dead weight.
    @Test func everyEntryIsARealTimeZone() {
        for identifier in ObserverLocation.knownZoneIdentifiers {
            #expect(TimeZone(identifier: identifier) != nil, "\(identifier) is not a known zone")
        }
    }

    /// A zone's coordinates should be in the rough neighbourhood its UTC offset
    /// implies — a catch for a mistyped sign or a transposed pair.
    @Test func coordinatesAgreeWithUTCOffset() throws {
        for identifier in ObserverLocation.knownZoneIdentifiers {
            let zone = try #require(TimeZone(identifier: identifier))
            let place = try position(identifier)
            let implied = ObserverLocation.longitude(fromSecondsFromGMT: zone.secondsFromGMT())

            var gap = abs(implied - place.longitude)
            if gap > 180 { gap = 360 - gap }
            #expect(gap < 40, "\(identifier): table says \(place.longitude), offset implies \(implied)")
        }
    }

    @Test func longitudeFromOffsetMapsHoursToDegrees() {
        #expect(ObserverLocation.longitude(fromSecondsFromGMT: 0) == 0)
        #expect(ObserverLocation.longitude(fromSecondsFromGMT: 9 * 3_600) == 135)
        #expect(ObserverLocation.longitude(fromSecondsFromGMT: -5 * 3_600) == -75)
    }

    @Test func longitudeFromOffsetStaysOnTheGlobe() {
        #expect(ObserverLocation.longitude(fromSecondsFromGMT: 20 * 3_600) == 180)
        #expect(ObserverLocation.longitude(fromSecondsFromGMT: -20 * 3_600) == -180)
    }

    /// The whole point of the table: a real device's zone should resolve without
    /// a permission prompt. Not asserted for the simulator's zone specifically,
    /// only that the lookup path runs.
    @Test func currentZoneLookupDoesNotCrash() {
        _ = ObserverLocation.approximate()
    }
}
