import SwiftUI

/// A star's face, generated from its catalogued properties.
///
/// No image ships with this app. `StarImage` draws the disc pixel by pixel from
/// the star's measured colour index and the temperature it implies, so every
/// star looks like itself — Betelgeuse churns in coarse red cells, Sirius burns
/// fine and blue-white, and neither was drawn by anyone.
///
/// The disc rotates slowly, which is both the cheapest way to give it life and
/// the true one: stars rotate.
struct StarPortrait: View {
    let star: Star
    var diameter: CGFloat = 220
    var showsCorona = true
    var isAnimated = true

    /// Stable per star, so it looks the same every time it's opened.
    private var seed: UInt64 { UInt64(star.hr) }
    private var tint: Color { Theme.starColor(bv: star.colorIndex) }

    private var disc: CGImage? {
        StarImage.disc(
            rgb: Theme.starRGB(bv: star.colorIndex),
            coarseness: star.granulationCoarseness,
            seed: seed
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isAnimated)) { timeline in
            let spin = timeline.date.timeIntervalSinceReferenceDate * 1.4
            ZStack {
                if showsCorona { corona }
                if let disc {
                    Image(decorative: disc, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: diameter, height: diameter)
                        .rotationEffect(.degrees(isAnimated ? spin : 0))
                        .clipShape(Circle())
                        .shadow(color: tint.opacity(0.55), radius: diameter * 0.10)
                } else {
                    Circle()
                        .fill(tint)
                        .frame(width: diameter, height: diameter)
                }
            }
            .frame(width: diameter * 1.7, height: diameter * 1.7)
        }
        .accessibilityLabel("\(star.displayName), drawn from its measured colour and temperature")
    }

    /// The faint envelope outside the disc. A soft gradient rather than
    /// anything structured — at this size, detail in the corona reads as noise.
    private var corona: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.11), .clear],
                    center: .center,
                    startRadius: diameter * 0.47,
                    endRadius: diameter * 0.85
                )
            )
            .frame(width: diameter * 1.7, height: diameter * 1.7)
            .blur(radius: diameter * 0.03)
            .allowsHitTesting(false)
    }
}

/// This star beside the Sun, at relative scale.
///
/// The comparison is the fact that lands — a red supergiant next to the Sun
/// needs no sentence explaining that it's large.
struct StarScaleComparison: View {
    let star: Star

    /// Drawn on a log scale. Betelgeuse is roughly 700 times the Sun's width;
    /// linearly, at any size that fits a phone, the Sun would be a fraction of
    /// one pixel.
    private var starDiameter: CGFloat {
        guard let radii = star.approximateSolarRadii else { return 60 }
        return max(22, min(132, 26 * (log10(max(radii, 1)) + 1.3)))
    }

    private var sunDiameter: CGFloat { 26 * 1.3 }

    var body: some View {
        if let radii = star.approximateSolarRadii {
            VStack(alignment: .leading, spacing: 16) {
                MarginLabel(text: "Against the Sun")

                // Both discs stand on one baseline so the comparison is read
                // by height, the way a scale figure works on a chart.
                HStack(alignment: .bottom, spacing: 34) {
                    labelled(caption: sizeCaption(radii), width: starDiameter) {
                        StarPortrait(
                            star: star,
                            diameter: starDiameter,
                            showsCorona: false,
                            isAnimated: false
                        )
                        .frame(width: starDiameter, height: starDiameter)
                    }
                    labelled(caption: "the Sun", width: sunDiameter) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 1, green: 0.97, blue: 0.86),
                                        Color(red: 1, green: 0.78, blue: 0.34),
                                    ],
                                    center: .init(x: 0.4, y: 0.38),
                                    startRadius: 0,
                                    endRadius: sunDiameter * 0.75
                                )
                            )
                            .frame(width: sunDiameter, height: sunDiameter)
                            .shadow(color: Color(red: 1, green: 0.8, blue: 0.4).opacity(0.55), radius: 7)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Logarithmic scale. Size estimated from spectral class, not measured.")
                    .font(Theme.figure(10))
                    .foregroundStyle(Theme.unlit)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labelled<Content: View>(
        caption: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 10) {
            content()
            Rectangle()
                .fill(Theme.rule)
                .frame(width: max(width, 44), height: Theme.hairline)
            Text(caption)
                .font(Theme.figure(10))
                .foregroundStyle(Theme.subdued)
                .frame(width: max(width, 72))
                .multilineTextAlignment(.center)
        }
    }

    private func sizeCaption(_ radii: Double) -> String {
        if radii >= 10 {
            "\(Int(radii.rounded()))× wider"
        } else if radii >= 1.15 {
            "\(radii.formatted(.number.precision(.fractionLength(1))))× wider"
        } else if radii <= 0.85 {
            "smaller"
        } else {
            "about equal"
        }
    }
}
