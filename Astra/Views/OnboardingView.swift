import SwiftUI
import SwiftData

/// First light.
///
/// The term for the first image a newly built telescope takes, and the shape of
/// this flow: the sky comes out, settles over where the user is standing, takes
/// one promise from them, and lights one star.
///
/// Nothing here is a slide. The starfield is a single continuous thing that
/// persists across all four phases — it appears, drifts, dims and finally
/// yields to one star. Advancing is a tap anywhere, so the flow never asks the
/// user to find a button.
struct OnboardingView: View {
    /// Whether the flow has been through once.
    ///
    /// Named here rather than written as a literal at each use, so the debug
    /// action that clears it can't drift from the check that reads it.
    static let seenKey = "hasSeenFirstLight"

    let progression: SkyProgression
    let onFinish: () -> Void

    /// Built once, in `init`, and handed down as a plain value.
    ///
    /// This started as `@State` on the field, filled in a `.task`. It always
    /// drew nothing: `TimelineView` holds on to the `Canvas` renderer closure
    /// it was first given, so the closure kept seeing the empty array the view
    /// was created with and never the one the task produced. The data depends
    /// only on the anchor and the catalogue, both fixed — so there was never a
    /// reason for it to be state.
    private let duskStars: [DuskStar]

    @Environment(\.modelContext) private var context

    init(progression: SkyProgression, onFinish: @escaping () -> Void) {
        self.progression = progression
        self.onFinish = onFinish
        self.duskStars = DuskField.build(
            anchor: progression.anchor,
            catalog: .shared
        )
    }

    @State private var phase: Phase = .dusk
    @State private var startedAt = Date.now
    @State private var habitName = ""
    @State private var colorIndex = 0
    @State private var errorMessage: String?
    @FocusState private var isNaming: Bool

    enum Phase: Int, CaseIterable {
        case dusk, sun, oneStar, figures, naming
    }

    /// The figure used to demonstrate a constellation completing.
    ///
    /// The earliest in their own progression with enough stars to read as a
    /// shape, since a two-star figure drawing one line teaches nothing. Still a
    /// figure they will genuinely fill, not a stock example.
    private var demonstrationFigure: Constellation? {
        progression.constellations.first { $0.starCount >= 4 }
            ?? progression.constellations.first
    }

    /// The star shown lighting, and the one that then flies into place.
    ///
    /// Taken from the demonstration figure rather than from the head of the
    /// progression, because the next page moves this exact star into that
    /// exact figure. A star that didn't belong to the figure would make the
    /// journey a lie.
    private var heroStar: Star? {
        demonstrationFigure?.stars.first
    }

    var body: some View {
        ZStack {
            // The same ground as the launch screen and as the app proper, not
            // pure black. It is a difference of ten values, and it is the
            // difference between the system's still dissolving into this and
            // the whole screen stepping a shade darker as it does.
            Theme.background.ignoresSafeArea()

            DuskField(
                stars: duskStars,
                startedAt: startedAt,
                settled: phase != .dusk,
                dimmed: phase != .dusk && phase != .sun,
                showsSun: phase == .sun
            )
            .ignoresSafeArea()

            // Whatever the system was showing a moment ago, still showing.
            // Drawn here rather than inside `content` so it is measured against
            // the whole screen, as the storyboard's constraints are.
            if phase == .dusk {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(startedAt)
                    LaunchMark(
                        sunOpacity: 1 - ramp(t, from: DuskField.sunFadesAt,
                                             over: DuskField.sunFadesOver)
                    )
                }
                .transition(.opacity)
            }

            // Words never sit straight on the field. A star landing behind a
            // line of type is the failure mode of every interface built over
            // an image, and this one has 1,584 chances to hit.
            if phase != .dusk {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72), .black.opacity(0.94)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            content
                .padding(.horizontal, 30)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: advanceByTap)
        .atlasAlert("Couldn't start", message: $errorMessage)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .dusk:    duskContent
        case .sun:     sunContent
        case .oneStar: oneStarContent
        case .figures: figuresContent
        case .naming:  namingContent
        }
    }

    // MARK: - Dusk

    /// Only the hint. The title is already on screen when this phase begins —
    /// the system put it there — and `LaunchMark` keeps it there. It used to
    /// arrive by letterspacing open as it fades, which was a good move for the
    /// type to make, but the launch screen now says the word first and no
    /// opening is worth saying it twice.
    private var duskContent: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startedAt)

            VStack {
                Spacer()
                TapHint(opacity: ramp(t, from: DuskField.hintAt, over: 0.9))
            }
        }
    }

    // MARK: - Anchor

    // MARK: - Sun

    /// Words gathered close under the Sun, high on the screen, with the rest of
    /// the sky left dark below them. The empty half is the point: that's the
    /// part still to fill.
    private var sunContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer().frame(height: geometry.size.height * 0.46)
                PhaseCopy(
                    "This is our Sun, and where your universe begins.",
                    alignment: .center
                )
                .shielded()
                Spacer()
                TapHint(opacity: 1)
            }
        }
        .transition(.opacity)
    }

    // MARK: - One star

    /// The star takes the middle and one line sits at the bottom. Nothing
    /// competes with the thing catching light.
    ///
    /// Held at `heroHeight` from the top so the next page can start this same
    /// star in the same place and the two read as one continuous shot.
    private var oneStarContent: some View {
        VStack(spacing: 0) {
            if let heroStar {
                Ignition(star: heroStar)
                    .frame(height: Self.heroHeight)
                Text(heroStar.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.starlight)
            }
            Spacer()
            PhaseCopy(
                "Complete your tasks to unlock a new star every day.",
                alignment: .center
            )
            TapHint(opacity: 1)
        }
        .transition(.opacity)
    }

    /// Vertical space the hero occupies on both the star page and the figure
    /// page, so it doesn't jump between them.
    static let heroHeight: CGFloat = 380

    // MARK: - Figures

    /// The star from the previous page travels into its own place in the
    /// figure, and the rest of the constellation assembles around it.
    private var figuresContent: some View {
        VStack(spacing: 0) {
            if let demonstrationFigure, let heroStar {
                FigureDraw(constellation: demonstrationFigure, hero: heroStar)
                    .frame(height: Self.heroHeight)
                Text(demonstrationFigure.name.uppercased())
                    .font(Theme.label(10))
                    .kerning(1.5)
                    .foregroundStyle(Theme.subdued)
            }
            Spacer()
            PhaseCopy(
                "Stars join into constellations.",
                alignment: .center
            )
            TapHint(opacity: 1)
        }
        .transition(.opacity)
    }

    // MARK: - Naming

    private var namingContent: some View {
        VStack(alignment: .leading, spacing: 30) {
            Spacer()

            Text("Name one habit you want to keep track of.")
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Theme.starlight)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: $habitName, prompt: Text("Work out for an hour")
                    .foregroundStyle(Theme.unlit))
                    .textFieldStyle(.plain)
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.starlight)
                    .tint(Theme.habitColor(colorIndex))
                    .focused($isNaming)
                    .submitLabel(.done)
                    .onSubmit(commitHabit)
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.ruleStrong).frame(height: Theme.hairline)
                    }

                HStack(spacing: 0) {
                    ForEach(0..<Theme.habitPalette.count, id: \.self) { index in
                        Button { colorIndex = index } label: {
                            VStack(spacing: 8) {
                                Rectangle()
                                    .fill(Theme.habitPalette[index])
                                    .frame(width: 20, height: 20)
                                Rectangle()
                                    .fill(index == colorIndex ? Theme.starlight : .clear)
                                    .frame(width: 20, height: 2)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(index + 1)")
                    }
                }
                .padding(.top, 6)
            }

            Spacer()

            if !trimmedName.isEmpty {
                TapHint(opacity: 1, text: "Tap to begin")
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: trimmedName.isEmpty)
        .transition(.opacity)
    }

    private var trimmedName: String {
        habitName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - First light

    // MARK: - Flow

    private func advanceByTap() {
        switch phase {
        case .dusk:
            // Ignore taps until the field has actually come out; tapping
            // through the opening would skip the only thing it's there to show.
            guard Date.now.timeIntervalSince(startedAt) > DuskField.settlesAt else { return }
            move(to: .sun)
        case .sun:
            move(to: .oneStar)
        case .oneStar:
            move(to: .figures)
        case .figures:
            move(to: .naming)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { isNaming = true }
        case .naming:
            commitHabit()
        }
    }

    private func move(to next: Phase) {
        withAnimation(.easeInOut(duration: 0.55)) { phase = next }
    }

    private func commitHabit() {
        guard !trimmedName.isEmpty else { return }
        isNaming = false
        do {
            try HabitStore(context: context).addHabit(name: trimmedName, colorIndex: colorIndex)
            onFinish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 0 to 1 over `over` seconds, starting at `from`.
    private func ramp(_ t: TimeInterval, from: TimeInterval, over: TimeInterval) -> Double {
        max(0, min(1, (t - from) / over))
    }
}

// MARK: - Field

/// The sky coming out, then behaving.
///
/// Stars appear in order of brightness, which is what actually happens at
/// nightfall: a handful of bright ones first, a long pause while your eyes
/// adjust, then the rest of the sky arrives at once. The curve below is shaped
/// to that — slow to start, a flood at the end — and it's the reason the
/// opening reads as dusk rather than as a loading bar.
struct DuskField: View {
    let stars: [DuskStar]
    let startedAt: Date
    let settled: Bool
    let dimmed: Bool
    let showsSun: Bool

    /// Held still before anything happens, so the mark the launch screen left
    /// on screen gets a moment of its own before the sky starts arriving.
    static let holdFor: TimeInterval = 0.7
    /// How long the whole sky takes to come out.
    static let duskOver: TimeInterval = 3.8
    /// When the sun starts to go, and how long it takes. It leaves while the
    /// sky is still filling, so the two overlap rather than queue, and the
    /// phase ends on stars rather than on the thing it opened with. The Sun
    /// comes back as itself, labelled and to scale, in the next phase.
    static let sunFadesAt: TimeInterval = 1.2
    static let sunFadesOver: TimeInterval = 2.0
    /// When the sky is far enough out to invite a tap.
    static let hintAt: TimeInterval = 3.6
    /// Taps before this are ignored — going straight through the opening skips
    /// the only thing it is there to show.
    static let settlesAt: TimeInterval = 2.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startedAt)
            Canvas { context, size in
                draw(in: &context, size: size, elapsed: t)
            }
        }
        .opacity(dimmed ? 0.28 : 1)
        .blur(radius: dimmed ? 1.4 : 0)
        // Held slightly wide during dusk, then eased back — the sky settling
        // onto where the user is standing.
        .scaleEffect(settled ? 1 : 1.14)
        .animation(.easeInOut(duration: 1.6), value: settled)
        .animation(.easeInOut(duration: 0.6), value: dimmed)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        // Enough scale that the field fills the screen edge to edge.
        let scale = max(size.width, size.height) / 150

        for star in stars {
            let age = elapsed - star.appearsAt
            guard age > 0 else { continue }
            // Each star fades up over its own beat rather than snapping on.
            let presence = min(1, age / 0.9)

            let point = CGPoint(
                x: centre.x - star.x * scale,
                y: centre.y - star.y * scale
            )
            guard point.x > -20, point.x < size.width + 20,
                  point.y > -20, point.y < size.height + 20 else { continue }

            let r = star.radius
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                with: .color(star.colour.opacity(presence * star.alpha))
            )
        }

        if showsSun {
            // Held above centre so it never shares space with the copy below.
            drawSun(in: &context, at: CGPoint(x: centre.x, y: size.height * 0.34))
        }
    }

    private func drawSun(in context: inout GraphicsContext, at centre: CGPoint) {
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 11))
            layer.fill(
                Path(ellipseIn: CGRect(x: centre.x - 17, y: centre.y - 17, width: 34, height: 34)),
                with: .color(Color(red: 1, green: 0.84, blue: 0.42).opacity(0.55))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)),
            with: .color(Color(red: 1, green: 0.95, blue: 0.80))
        )
        let label = Text("the Sun")
            .font(Theme.label(10))
            .foregroundStyle(Theme.subdued)
        context.draw(context.resolve(label), at: CGPoint(x: centre.x, y: centre.y + 22), anchor: .center)
    }

    /// Projects the whole catalogue once and assigns each star its moment.
    static func build(anchor: EquatorialCoordinate, catalog: StarCatalog) -> [DuskStar] {
        let ordered = catalog.stars.sorted { $0.magnitude < $1.magnitude }
        let total = Double(ordered.count)

        return ordered.enumerated().map { rank, star in
            let projected = SkyMath.project(star.coordinate, from: anchor)
            // pow < 1 spreads the first few stars over a long stretch and
            // packs the faint majority into the last moment — the shape of
            // real nightfall rather than a linear wipe.
            let progress = pow(Double(rank) / total, 0.42)
            return DuskStar(
                x: projected.x,
                y: projected.y,
                radius: Theme.starRadius(magnitude: star.magnitude) * 0.85,
                colour: Theme.starColor(bv: star.colorIndex),
                alpha: star.magnitude < 3.5 ? 0.95 : 0.55,
                appearsAt: holdFor + progress * duskOver
            )
        }
    }
}

struct DuskStar {
    let x: Double
    let y: Double
    let radius: Double
    let colour: Color
    let alpha: Double
    let appearsAt: TimeInterval
}

// MARK: - Pieces

/// The star catching. Scale and brightness come up together while a ring of
/// light leaves it, which is the same device the map uses when a star arrives —
/// so the last screen of onboarding teaches the gesture the app will repeat.
private struct Ignition: View {
    let star: Star

    @State private var lit: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.starColor(bv: star.colorIndex).opacity(0.6 * Double(1 - lit)), lineWidth: 2)
                .frame(width: 60 + 190 * lit, height: 60 + 190 * lit)

            StarPortrait(star: star, diameter: 150)
                .scaleEffect(0.55 + 0.45 * lit)
                .opacity(Double(lit))
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.66)) { lit = 1 }
        }
    }
}

/// The only instruction in the flow.
private struct TapHint: View {
    let opacity: Double
    var text: String = "Tap to continue"

    @State private var breathing = false

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(10))
            .kerning(1.6)
            .foregroundStyle(Theme.subdued)
            .opacity(opacity * (breathing ? 0.45 : 1))
            // Clear of the copy above it — sitting tight under a paragraph made
            // the hint read as a third line of that paragraph.
            .padding(.top, 30)
            .padding(.bottom, 34)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

/// A phase's words: one line carrying the idea, and the small print beneath.
///
/// No margin label above it. Every phase having a little uppercase category
/// heading was the flow's own worst habit — it dressed four plain statements up
/// as sections of a document, which is the register the copy is trying to
/// avoid in the first place.
/// A phase's one line.
///
/// There used to be a second, smaller line under each of these. It was cut:
/// with the animation carrying the explanation, the small print was reading as
/// caption furniture rather than as anything anyone needed.
private struct PhaseCopy: View {
    let headline: String
    var alignment: HorizontalAlignment = .leading

    init(_ headline: String, alignment: HorizontalAlignment = .leading) {
        self.headline = headline
        self.alignment = alignment
    }

    var body: some View {
        Text(headline)
            .font(.system(size: 23, weight: .regular))
            .foregroundStyle(Theme.starlight)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                alignment: alignment == .center ? .center : .leading
            )
    }
}

private extension View {
    /// A soft local darkening behind a block of words.
    ///
    /// Needed only where copy sits over the field at full brightness. The
    /// page-wide bottom gradient can't help text placed high on the screen, and
    /// a panel behind it would put a rectangle in the middle of the sky.
    func shielded() -> some View {
        background {
            RadialGradient(
                colors: [.black.opacity(0.9), .black.opacity(0.72), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 250
            )
            .blur(radius: 20)
            .padding(-60)
            .allowsHitTesting(false)
        }
    }
}

/// A constellation assembling: its stars already lit, then its lines drawn on.
///
/// The lines are drawn with a trim, edge by edge, in the order the figure is
/// written — so it reads as something being joined up rather than a shape
/// fading in. This is the app's actual figure data, not a diagram.
private struct FigureDraw: View {
    let constellation: Constellation
    /// The star carried over from the previous page. It begins where that page
    /// left it, then travels to the place it actually occupies in the figure.
    let hero: Star

    /// Hero travelling from centre-large to its own position at true size.
    @State private var arrived: CGFloat = 0
    /// The rest of the figure's stars fading up once the hero has landed.
    @State private var others: CGFloat = 0
    /// Lines joining them, drawn in the order the figure is written.
    @State private var drawn: CGFloat = 0

    private var catalog: StarCatalog { .shared }

    /// Figure edges resolved to the two stars they join.
    private var edges: [(Star, Star)] {
        (catalog.figures[constellation.abbreviation] ?? []).compactMap { edge in
            guard let a = catalog.star(hr: edge.0), let b = catalog.star(hr: edge.1) else { return nil }
            return (a, b)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = FigureLayout(size: geometry.size, stars: constellation.stars)
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let landing = layout.point(hero)
            let heroRadius = Theme.starRadius(magnitude: hero.magnitude)

            ZStack {
                // Lines under the stars, so a join never covers the thing it joins.
                ForEach(Array(edges.enumerated()), id: \.offset) { index, edge in
                    let share = 1.0 / Double(max(edges.count, 1))
                    let start = Double(index) * share
                    let local = max(0, min(1, (Double(drawn) - start) / share))

                    Path { path in
                        path.move(to: layout.point(edge.0))
                        path.addLine(to: layout.point(edge.1))
                    }
                    .trim(from: 0, to: local)
                    .stroke(Theme.starlight.opacity(0.45), lineWidth: 1)
                }

                ForEach(constellation.stars.filter { $0.hr != hero.hr }) { star in
                    dot(star, at: layout.point(star))
                        .opacity(Double(others))
                }

                // The hero starts as the same portrait the previous page ended
                // on, so the crossfade between pages has nothing to catch on,
                // then hands over to a plain dot as it lands. Without the
                // handover it stays textured at rest and reads as a different
                // kind of object from the stars beside it.
                ZStack {
                    StarPortrait(star: hero, diameter: heroDiameter(finalRadius: heroRadius),
                                 showsCorona: arrived < 0.5, isAnimated: false)
                        .opacity(1 - settledIn)
                    dot(hero, at: .zero)
                        .frame(width: heroRadius * 2, height: heroRadius * 2)
                        .opacity(settledIn)
                }
                .position(
                    x: centre.x + (landing.x - centre.x) * arrived,
                    y: centre.y + (landing.y - centre.y) * arrived
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).delay(0.45)) { arrived = 1 }
            withAnimation(.easeOut(duration: 0.7).delay(1.5)) { others = 1 }
            withAnimation(.easeInOut(duration: 1.6).delay(1.9)) { drawn = 1 }
        }
    }

    /// Shrinks from the size the star page showed to the size its own
    /// magnitude earns it.
    private func heroDiameter(finalRadius: Double) -> CGFloat {
        let start: CGFloat = 150
        let end = max(finalRadius * 2, 5)
        return start + (end - start) * arrived
    }

    /// Handover from portrait to dot, over the last stretch of the journey.
    private var settledIn: Double {
        max(0, min(1, (Double(arrived) - 0.72) / 0.28))
    }

    private func dot(_ star: Star, at point: CGPoint) -> some View {
        let radius = Theme.starRadius(magnitude: star.magnitude)
        return Circle()
            .fill(Theme.starColor(bv: star.colorIndex))
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: Theme.starColor(bv: star.colorIndex).opacity(0.7), radius: radius * 1.4)
            .position(point)
    }
}

/// Fits a constellation's own stars to a box, keeping their real shape.
///
/// Everything is computed once in `init`. The first version recomputed the
/// projection inside `point(_:)`, which ran the whole catalogue lookup per star
/// per frame, and centred on the star centroid rather than the figure's
/// bounding box — so any lopsided figure, which is most of them, sat off to one
/// side of its own frame.
private struct FigureLayout {
    private let placed: [Int: CGPoint]

    init(size: CGSize, stars: [Star]) {
        let origin = Constellation(abbreviation: "", name: "", stars: stars).center
        let projected = stars.map { ($0.hr, SkyMath.project($0.coordinate, from: origin)) }

        guard let first = projected.first else {
            placed = [:]
            return
        }
        var minX = first.1.x, maxX = first.1.x
        var minY = first.1.y, maxY = first.1.y
        for (_, point) in projected {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }

        // Fit the figure's own extent, then centre that extent in the box.
        let inset: CGFloat = 30
        let scale = min(
            (size.width - inset * 2) / max(maxX - minX, 0.001),
            (size.height - inset * 2) / max(maxY - minY, 0.001)
        )
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2

        placed = Dictionary(uniqueKeysWithValues: projected.map { hr, point in
            (hr, CGPoint(
                x: size.width / 2 - (point.x - midX) * scale,
                y: size.height / 2 - (point.y - midY) * scale
            ))
        })
    }

    func point(_ star: Star) -> CGPoint {
        placed[star.hr] ?? .zero
    }
}
