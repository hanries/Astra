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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("SKY")
                            .font(Theme.label(11))
                            .kerning(1.8)
                            .foregroundStyle(Theme.starlight)
                        // The epoch every real chart carries. It's true, it's
                        // small, and it tells you the thing was made from data.
                        Text("J2000.0")
                            .font(Theme.figure(9))
                            .kerning(0.5)
                            .foregroundStyle(Theme.unlit)
                    }
                }
            }
            .atlasSheet(item: $selectedStar, detents: [.large]) { star in
                StarDetailSheet(
                    star: star,
                    isLit: isLit(star),
                    litOn: litDay(star)
                )
            }
        }
    }

    // MARK: - Chrome

    /// The numbers that make the work legible. Stars lit is the headline
    /// because it's exactly the number of days shown up — one star, one day.
    /// The chart's readings, ruled off top and bottom over the field.
    ///
    /// Rules rather than a floating rounded panel: the chart is the content,
    /// and a card hovering over it would hide sky. A pair of hairlines states
    /// the figures without taking a rectangle out of the view.
    private var stats: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                statTile(value: "\(awards.count)", label: awards.count == 1 ? "star" : "stars")
                divider
                statTile(value: "\(completedCount)", label: "figures")
                divider
                statTile(
                    value: "\(Int((skyShare * 100).rounded()))%",
                    label: "of sky"
                )
            }
            .padding(.vertical, 11)
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)

            if let active {
                HStack(spacing: 8) {
                    Text(active.constellation.name.uppercased())
                        .font(Theme.label(10))
                        .kerning(1.4)
                        .foregroundStyle(Theme.subdued)
                    Text("\(active.litCount)/\(active.constellation.starCount)")
                        .font(Theme.figure(10))
                        .foregroundStyle(Theme.unlit)
                }
                .padding(.top, 9)
            }
        }
        .padding(.horizontal, 20)
        .background {
            // Only enough scrim to keep the figures legible where the field is
            // dense — not a panel.
            LinearGradient(
                colors: [Theme.background, Theme.background.opacity(0.82), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .padding(.horizontal, -20)
            .padding(.top, -40)
            .padding(.bottom, -24)
        }
        .allowsHitTesting(false)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.figure(21, weight: .light))
                .foregroundStyle(Theme.starlight)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(Theme.label(9))
                .kerning(1.1)
                .foregroundStyle(Theme.unlit)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(width: Theme.hairline, height: 30)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NO STARS LIT")
                .font(Theme.label(10))
                .kerning(1.5)
                .foregroundStyle(Theme.subdued)
            Text("Keep every habit today and the first one lights.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.unlit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
        }
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AtlasPanel(
            title: star.displayName,
            provenance: provenance,
            trailing: .init(label: "Done", isProminent: true) { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    portrait
                    readings
                    StarScaleComparison(star: star)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
        }
    }

    /// Catalogue number, Bayer designation and the date lit — the line a plate
    /// carries so you know what you're looking at and where it came from.
    private var provenance: [String] {
        var parts = ["HR \(star.hr)"]
        if let bayer = star.bayer, star.name != nil { parts.append(bayer) }
        if let litOn {
            parts.append("lit \(litOn.date().formatted(.dateTime.day().month(.abbreviated)))")
        } else if !isLit {
            parts.append("not yet lit")
        }
        return parts
    }

    /// The star with its measurements set around it.
    ///
    /// This is the one screen in the app with a single hero object, which is
    /// exactly the condition annotations-over-the-subject are for — a spec
    /// table would put the numbers somewhere you have to look them up, and here
    /// they can simply sit against the thing they describe.
    private var portrait: some View {
        ZStack {
            StarPortrait(star: star, diameter: 172)
                // Unlit stars show as they *will* look, dimmed — something to
                // walk towards rather than a blank.
                .opacity(isLit ? 1 : 0.3)
                .saturation(isLit ? 1 : 0.45)

            VStack {
                HStack {
                    annotation("mag \(star.magnitude.formatted(.number.precision(.fractionLength(2))))")
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    if let kelvin = star.temperatureKelvin {
                        annotation("\(Int((kelvin / 100).rounded()) * 100) K")
                    }
                }
                Spacer()
                HStack {
                    if let distance = star.distanceLightYears {
                        annotation("\(Int(distance.rounded())) ly")
                    } else if let type = star.spectralType?.prefix(6) {
                        annotation(String(type).trimmingCharacters(in: .whitespaces))
                    }
                    Spacer()
                }
            }
            .frame(height: 208)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
    }

    /// An annotation ruled to the object, as a chart labels a feature: a mark,
    /// a leader line, then the value.
    private func annotation(_ text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Theme.ruleStrong)
                .frame(width: 14, height: Theme.hairline)
            Text(text)
                .font(Theme.figure(11))
                .foregroundStyle(Theme.starlight.opacity(0.9))
        }
        .padding(.vertical, 3)
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarginLabel(text: "Notes")
                .padding(.bottom, 10)
            ForEach(factLines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.starlight.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
                    }
            }
        }
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
