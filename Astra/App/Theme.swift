import SwiftUI

/// Astra's visual constants.
///
/// The app is a night sky, so the theme is fixed dark — there is no light mode
/// to design twice for. Restraint is the aesthetic: near-black, soft starlight
/// text, and colour reserved for two things only — habit identity and the
/// stars themselves, whose colours come from their measured B−V index rather
/// than from taste.
enum Theme {
    /// Not pure black: a whisper of blue keeps large fields from reading flat.
    static let background = Color(red: 0.04, green: 0.05, blue: 0.08)
    /// Cards and sheets, one step off the background.
    static let surface = Color(red: 0.08, green: 0.10, blue: 0.14)
    static let starlight = Color(red: 0.93, green: 0.94, blue: 0.97)
    static let subdued = Color(red: 0.55, green: 0.58, blue: 0.66)
    /// Faint outline for stars not yet lit.
    static let unlit = Color(red: 0.25, green: 0.28, blue: 0.36)

    /// The five habit colours, tuned to read against the dark background.
    /// `Habit.colorIndex` indexes this array — always through `habitColor(_:)`,
    /// which clamps, so a stale index can never crash.
    static let habitPalette: [Color] = [
        Color(red: 0.98, green: 0.75, blue: 0.30),  // amber
        Color(red: 0.45, green: 0.72, blue: 0.99),  // sky blue
        Color(red: 0.94, green: 0.51, blue: 0.48),  // coral
        Color(red: 0.55, green: 0.85, blue: 0.63),  // mint
        Color(red: 0.78, green: 0.62, blue: 0.98),  // violet
    ]

    static func habitColor(_ index: Int) -> Color {
        habitPalette[max(0, min(index, habitPalette.count - 1))]
    }

    /// A star's rendered colour, from its measured B−V colour index.
    ///
    /// Piecewise-linear through the anchors astronomers actually quote: Rigel
    /// at −0.03 is blue-white, the Sun at 0.65 is yellow-white, Betelgeuse at
    /// 1.85 is orange-red. Stars without an index render as plain starlight.
    static func starColor(bv: Double?) -> Color {
        guard let bv else { return starlight }
        let anchors: [(Double, (Double, Double, Double))] = [
            (-0.30, (0.61, 0.72, 1.00)),
            ( 0.00, (0.78, 0.84, 1.00)),
            ( 0.30, (0.94, 0.95, 1.00)),
            ( 0.65, (1.00, 0.96, 0.88)),
            ( 1.00, (1.00, 0.87, 0.68)),
            ( 1.50, (1.00, 0.76, 0.52)),
            ( 2.00, (1.00, 0.64, 0.42)),
        ]
        let clamped = max(anchors.first!.0, min(bv, anchors.last!.0))
        for i in 1..<anchors.count where clamped <= anchors[i].0 {
            let (b0, c0) = anchors[i - 1]
            let (b1, c1) = anchors[i]
            let t = (clamped - b0) / (b1 - b0)
            return Color(
                red: c0.0 + (c1.0 - c0.0) * t,
                green: c0.1 + (c1.1 - c0.1) * t,
                blue: c0.2 + (c1.2 - c0.2) * t
            )
        }
        return starlight
    }

    /// A star's rendered radius in points, from its magnitude. Brighter is
    /// bigger, on a gentle curve — a linear map makes Sirius a golf ball or
    /// every faint star invisible.
    static func starRadius(magnitude: Double, in span: ClosedRange<Double> = 1.5...7) -> Double {
        // Magnitude runs backwards: -1.5 (Sirius) to ~8 (faintest bundled).
        let brightness = max(0, min(1, (6.5 - magnitude) / 8))
        return span.lowerBound + (span.upperBound - span.lowerBound) * pow(brightness, 1.6)
    }
}
