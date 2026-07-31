import SwiftUI
import SwiftData

/// The sky tab: what the user has lit, what they're lighting now, and what
/// comes after.
///
/// Every star is drawn from its catalogued position, magnitude, and colour —
/// there is no illustration anywhere in this file. The figure you see is the
/// figure that's actually above you.
struct SkyMapView: View {
    @Query(sort: [SortDescriptor(\Award.ordinal)]) private var awards: [Award]

    let progression: SkyProgression

    @State private var selectedStar: Star?

    private var lit: [(constellation: Constellation, litCount: Int)] {
        progression.litStars(awardCount: awards.count)
    }

    private var active: (constellation: Constellation, litCount: Int)? {
        progression.active(awardCount: awards.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let active {
                        activeSection(active)
                    } else if awards.isEmpty {
                        emptyState
                    }
                    completedSection
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Sky")
            .sheet(item: $selectedStar) { star in
                StarDetailSheet(
                    star: star,
                    isLit: isLit(star),
                    litOn: litDay(star)
                )
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Sections

    private func activeSection(_ current: (constellation: Constellation, litCount: Int)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(current.constellation.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.starlight)
                Spacer()
                Text("\(current.litCount) of \(current.constellation.starCount)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subdued)
                    .contentTransition(.numericText())
            }

            ConstellationCanvas(
                constellation: current.constellation,
                litCount: current.litCount,
                onTapStar: { selectedStar = $0 }
            )
            .frame(height: 320)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.surface.opacity(0.5))
            )

            Text(remainingLine(current))
                .font(.callout)
                .foregroundStyle(Theme.subdued)
        }
    }

    private func remainingLine(_ current: (constellation: Constellation, litCount: Int)) -> String {
        let left = current.constellation.starCount - current.litCount
        if left == 1 { return "One more day completes it." }
        return "\(left) more days complete it."
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your sky is dark.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.starlight)
            Text("Keep a habit today and the first star lights.")
                .font(.callout)
                .foregroundStyle(Theme.subdued)
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var completedSection: some View {
        let done = lit.filter { $0.litCount == $0.constellation.starCount }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Completed")
                    .font(.headline)
                    .foregroundStyle(Theme.subdued)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(done, id: \.constellation.id) { entry in
                        CompletedCard(constellation: entry.constellation) {
                            selectedStar = $0
                        }
                    }
                }
            }
        }
    }

    // MARK: - Lookups

    private func isLit(_ star: Star) -> Bool {
        for entry in lit {
            if entry.constellation.abbreviation == star.constellation {
                return entry.constellation.stars.prefix(entry.litCount).contains { $0.hr == star.hr }
            }
        }
        return false
    }

    /// The day a star was earned, via the award whose ordinal maps to it.
    private func litDay(_ star: Star) -> DayKey? {
        for award in awards {
            if progression.star(forOrdinal: award.ordinal)?.star.hr == star.hr {
                return award.day
            }
        }
        return nil
    }
}

// MARK: - Canvas

/// A constellation's stars, projected and drawn. Lit stars glow in their
/// measured colour; unlit ones wait as faint rings.
struct ConstellationCanvas: View {
    let constellation: Constellation
    let litCount: Int
    var onTapStar: ((Star) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let placed = Self.layout(constellation.stars, in: geometry.size)
            let litHRs = Set(constellation.stars.prefix(litCount).map(\.hr))

            Canvas { canvasContext, _ in
                for (star, point) in placed {
                    let radius = Theme.starRadius(magnitude: star.magnitude)
                    let color = Theme.starColor(bv: star.colorIndex)
                    let rect = CGRect(
                        x: point.x - radius, y: point.y - radius,
                        width: radius * 2, height: radius * 2
                    )
                    if litHRs.contains(star.hr) {
                        // Glow: a blurred disc under a solid core.
                        let glow = rect.insetBy(dx: -radius * 1.5, dy: -radius * 1.5)
                        canvasContext.drawLayer { layer in
                            layer.addFilter(.blur(radius: radius * 1.2))
                            layer.fill(Path(ellipseIn: glow), with: .color(color.opacity(0.5)))
                        }
                        canvasContext.fill(Path(ellipseIn: rect), with: .color(color))
                    } else {
                        canvasContext.stroke(
                            Path(ellipseIn: rect),
                            with: .color(Theme.unlit),
                            lineWidth: 1
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                // Generous hit target: nearest star within 30 points.
                let nearest = placed.min {
                    hypot($0.1.x - location.x, $0.1.y - location.y)
                        < hypot($1.1.x - location.x, $1.1.y - location.y)
                }
                if let nearest,
                   hypot(nearest.1.x - location.x, nearest.1.y - location.y) < 30 {
                    onTapStar?(nearest.0)
                }
            }
        }
    }

    /// Projects stars into view space.
    ///
    /// A plate carrée around the figure's centre, with right ascension scaled
    /// by cos(declination) so shapes keep their proportions away from the
    /// equator — full gnomonic projection buys nothing at constellation scale.
    /// East is left, as it is when you look up.
    static func layout(_ stars: [Star], in size: CGSize) -> [(Star, CGPoint)] {
        guard !stars.isEmpty else { return [] }

        let centerRA = averageRA(stars)
        let midDec = stars.map(\.coordinate.declination).reduce(0, +) / Double(stars.count)
        let cosDec = max(0.2, cos(midDec * .pi / 180))

        let points = stars.map { star -> (Star, CGPoint) in
            var dRA = star.coordinate.rightAscension - centerRA
            if dRA > 180 { dRA -= 360 }
            if dRA < -180 { dRA += 360 }
            return (star, CGPoint(x: -dRA * cosDec, y: -star.coordinate.declination))
        }

        let xs = points.map(\.1.x), ys = points.map(\.1.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }

        let inset = 32.0
        let spanX = max(maxX - minX, 0.001)
        let spanY = max(maxY - minY, 0.001)
        let scale = min(
            (size.width - inset * 2) / spanX,
            (size.height - inset * 2) / spanY
        )

        return points.map { star, raw in
            (star, CGPoint(
                x: (raw.x - (minX + maxX) / 2) * scale + size.width / 2,
                y: (raw.y - (minY + maxY) / 2) * scale + size.height / 2
            ))
        }
    }

    private static func averageRA(_ stars: [Star]) -> Double {
        var x = 0.0, y = 0.0
        for star in stars {
            let ra = star.coordinate.rightAscension * .pi / 180
            x += cos(ra); y += sin(ra)
        }
        return SkyMath.normalizedDegrees(atan2(y, x) * 180 / .pi)
    }
}

/// A finished figure, small and fully aglow.
private struct CompletedCard: View {
    let constellation: Constellation
    var onTapStar: ((Star) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConstellationCanvas(
                constellation: constellation,
                litCount: constellation.starCount,
                onTapStar: onTapStar
            )
            .frame(height: 110)
            Text(constellation.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.starlight)
            Text("\(constellation.starCount) stars")
                .font(.caption2)
                .foregroundStyle(Theme.subdued)
        }
        .padding(12)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Star detail

/// The facts panel — everything here is a catalogue field, phrased as a
/// sentence.
struct StarDetailSheet: View {
    let star: Star
    let isLit: Bool
    let litOn: DayKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                StarDot(
                    color: Theme.starColor(bv: star.colorIndex),
                    radius: Theme.starRadius(magnitude: star.magnitude),
                    isLit: isLit
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(star.displayName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.starlight)
                    if let bayer = star.bayer, star.name != nil {
                        Text(bayer)
                            .font(.subheadline)
                            .foregroundStyle(Theme.subdued)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(factLines, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(Theme.starlight.opacity(0.85))
                }
            }

            if let litOn {
                Text("Lit on \(litOn.date().formatted(.dateTime.month(.wide).day()))")
                    .font(.footnote)
                    .foregroundStyle(Theme.subdued)
            } else if !isLit {
                Text("Not yet lit")
                    .font(.footnote)
                    .foregroundStyle(Theme.subdued)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.background)
    }

    /// True sentences from catalogue fields. No adjectives the data doesn't
    /// support.
    private var factLines: [String] {
        var lines: [String] = []

        if let constellationName = StarCatalog.constellationNames[star.constellation] {
            lines.append("A star of \(constellationName).")
        }

        if let distance = star.distanceLightYears {
            let years = Int(distance.rounded())
            lines.append("Its light left \(years) years ago — that's the star as it was in \(Calendar.current.component(.year, from: .now) - years).")
        }

        if let kelvin = star.temperatureKelvin {
            let sun = 5_772.0
            if kelvin > sun * 1.3 {
                lines.append("Surface around \(Int(kelvin.rounded(toNearest: 100))) K — far hotter than the Sun, which is why it burns blue-white.")
            } else if kelvin < sun * 0.75 {
                lines.append("Surface around \(Int(kelvin.rounded(toNearest: 100))) K — cooler than the Sun, glowing orange-red.")
            } else {
                lines.append("Surface around \(Int(kelvin.rounded(toNearest: 100))) K — close to our own Sun's temperature.")
            }
        }

        if star.magnitude < 1.5 {
            lines.append("At magnitude \(star.magnitude.formatted(.number.precision(.fractionLength(1)))), it's among the brightest stars in the entire sky.")
        } else if star.magnitude < 4 {
            lines.append("Magnitude \(star.magnitude.formatted(.number.precision(.fractionLength(1)))) — visible to the naked eye even from a town.")
        } else {
            lines.append("Magnitude \(star.magnitude.formatted(.number.precision(.fractionLength(1)))) — you'll want a dark sky to pick it out unaided.")
        }

        return lines
    }
}

private extension Double {
    func rounded(toNearest step: Double) -> Double {
        (self / step).rounded() * step
    }
}
