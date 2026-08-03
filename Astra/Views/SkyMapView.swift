import SwiftUI
import SwiftData

/// The sky tab: the user's whole universe, and the proof of what filled it.
///
/// The chart is the screen. Everything else — the counts, the current figure —
/// sits over it as light chrome, because the thing worth looking at is the
/// spread of lit stars against the dark.
struct SkyMapView: View {
    @Query(sort: [SortDescriptor(\Award.ordinal)]) private var awards: [Award]

    let progression: SkyProgression
    /// Set when the user has just come here from lighting a star. Cleared once
    /// the map has pointed at it, so it doesn't replay on every later visit.
    @Binding var arrivingStar: Star?

    /// Presented with `sheet(item:)` rather than `sheet(isPresented:)`: the
    /// latter builds its content from whatever the state was when the flag
    /// flipped, which races the star being set in the same update and shows an
    /// empty sheet.
    @State private var selectedStar: Star?

    private let catalog = StarCatalog.shared

    private var active: (constellation: Constellation, litCount: Int)? {
        progression.active(awardCount: awards.count)
    }

    private var completedCount: Int {
        progression.completed(awardCount: awards.count).count
    }

    /// Share of the reachable sky finished.
    ///
    /// This replaced a "degrees reached" figure, which was honest only while
    /// the progression ran outward from the anchor. Now that figures unlock
    /// smallest-first they land all over the sky, and the furthest one says
    /// nothing about how much has been done.
    private var skyShare: Double {
        guard !progression.constellations.isEmpty else { return 0 }
        return Double(completedCount) / Double(progression.constellations.count)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SkyChartView(
                    progression: progression,
                    catalog: catalog,
                    litCount: awards.count,
                    arrivingStar: arrivingStar
                ) { star in
                    selectedStar = star
                }
                .ignoresSafeArea(edges: .bottom)
                .task(id: arrivingStar?.hr) {
                    guard arrivingStar != nil else { return }
                    // Let the last ring finish, then the sky goes back to being
                    // just the sky — a marker that stays becomes furniture.
                    try? await Task.sleep(for: .seconds(3.4))
                    arrivingStar = nil
                }

                if awards.isEmpty {
                    emptyState
                } else {
                    stats
                }
            }
            .background(Theme.background)
            .navigationTitle("Sky")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Chrome

    /// The numbers that make the work legible. Stars lit is the headline
    /// because it's exactly the number of days shown up — one star, one day.
    private var stats: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                statTile(value: "\(awards.count)", label: awards.count == 1 ? "star lit" : "stars lit")
                divider
                statTile(value: "\(completedCount)", label: completedCount == 1 ? "figure done" : "figures done")
                divider
                statTile(
                    value: skyShare.formatted(.percent.precision(.fractionLength(0))),
                    label: "of the sky"
                )
            }
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))

            if let active {
                Text("\(active.constellation.name) · \(active.litCount) of \(active.constellation.starCount)")
                    .font(.footnote)
                    .foregroundStyle(Theme.subdued)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.starlight)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.subdued)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.unlit.opacity(0.4))
            .frame(width: 0.5, height: 28)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Your sky is dark.")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.starlight)
            Text("Keep a habit today and the first star lights.")
                .font(.callout)
                .foregroundStyle(Theme.subdued)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    // MARK: - Lookups

    private func isLit(_ star: Star) -> Bool {
        for entry in progression.litStars(awardCount: awards.count)
        where entry.constellation.abbreviation == star.constellation {
            return entry.constellation.stars.prefix(entry.litCount).contains { $0.hr == star.hr }
        }
        return false
    }

    private func litDay(_ star: Star) -> DayKey? {
        for award in awards
        where progression.star(forOrdinal: award.ordinal)?.star.hr == star.hr {
            return award.day
        }
        return nil
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // The portrait leads. A star you've earned should look like a
                // star, not like a bullet point.
                StarPortrait(star: star, diameter: 190)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    // Unlit stars are shown as they *will* look, dimmed —
                    // something to walk towards rather than a blank.
                    .opacity(isLit ? 1 : 0.35)
                    .saturation(isLit ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(star.displayName)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Theme.starlight)
                    if let bayer = star.bayer, star.name != nil {
                        Text(bayer)
                            .font(.subheadline)
                            .foregroundStyle(Theme.subdued)
                    }
                    if let litOn {
                        Text("Lit on \(litOn.date().formatted(.dateTime.month(.wide).day()))")
                            .font(.footnote)
                            .foregroundStyle(Theme.subdued)
                            .padding(.top, 4)
                    } else if !isLit {
                        Text("Not yet lit")
                            .font(.footnote)
                            .foregroundStyle(Theme.subdued)
                            .padding(.top, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(factLines, id: \.self) { line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(Theme.starlight.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                StarScaleComparison(star: star)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Theme.background)
    }

    /// True sentences from catalogue fields. No adjective the data doesn't
    /// support.
    private var factLines: [String] {
        var lines: [String] = []

        if let constellationName = StarCatalog.constellationNames[star.constellation] {
            lines.append("A star of \(constellationName).")
        }

        if let distance = star.distanceLightYears {
            let years = Int(distance.rounded())
            let departed = Calendar.current.component(.year, from: .now) - years
            lines.append("Its light left \(years) years ago — the star as it was in \(departed).")
        }

        if let kelvin = star.temperatureKelvin {
            let sun = 5_772.0
            let rounded = Int((kelvin / 100).rounded() * 100)
            if kelvin > sun * 1.3 {
                lines.append("Around \(rounded) K at the surface — far hotter than the Sun, which is why it burns blue-white.")
            } else if kelvin < sun * 0.75 {
                lines.append("Around \(rounded) K at the surface — cooler than the Sun, glowing orange-red.")
            } else {
                lines.append("Around \(rounded) K at the surface — close to our own Sun's temperature.")
            }
        }

        let magnitude = star.magnitude.formatted(.number.precision(.fractionLength(1)))
        if star.magnitude < 1.5 {
            lines.append("At magnitude \(magnitude), among the brightest stars in the whole sky.")
        } else if star.magnitude < 4 {
            lines.append("Magnitude \(magnitude) — visible to the naked eye even from a town.")
        } else {
            lines.append("Magnitude \(magnitude) — you'll want a dark sky to pick it out unaided.")
        }

        return lines
    }
}
