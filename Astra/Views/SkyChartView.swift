import SwiftUI

/// The whole sky on one chart, drawn from the catalogue.
///
/// Every bundled star is here at its real position, sized by magnitude and
/// coloured by its measured B−V index. Lit stars burn; the rest wait as faint
/// grey points, so what the user has earned reads against everything they
/// haven't.
///
/// The chart is centred on the anchor their progression was frozen from, in an
/// azimuthal equidistant projection — so radius from the centre is angular
/// distance from where they started, which is exactly the order things unlock
/// in. The lit region grows as a disc.
struct SkyChartView: View {
    let progression: SkyProgression
    let catalog: StarCatalog
    let litCount: Int
    /// A star to point at on arrival — the one just earned. Drawn as an
    /// expanding ring so the eye is taken to it without moving the chart, which
    /// would cost the user the view they already had.
    var arrivingStar: Star?
    var onSelectStar: ((Star) -> Void)?

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    /// Set once a touch travels far enough to be a drag rather than a tap.
    @State private var isDragging = false

    /// True when the view has been moved off its starting framing, which is the
    /// only time the recentre control is worth showing.
    private var isOffCentre: Bool {
        committedPan != .zero || committedZoom != 1
    }

    /// Half-width of the chart in degrees at zoom 1 — the whole visible sky
    /// plus a little rim.
    private static let baseSpanDegrees: Double = 110
    private static let zoomRange: ClosedRange<CGFloat> = 0.7...12

    /// Stars already lit, by catalogue number, and the frontier radius.
    private var litState: LitState {
        var hrs = Set<Int>()
        var reach = 0.0
        let centre = progression.anchor
        for entry in progression.litStars(awardCount: litCount) {
            for star in entry.constellation.stars.prefix(entry.litCount) {
                hrs.insert(star.hr)
            }
            reach = max(reach, SkyMath.angularSeparation(centre, entry.constellation.center))
        }
        return LitState(hrs: hrs, reach: reach)
    }

    var body: some View {
        GeometryReader { geometry in
            let state = litState
            let layout = ChartLayout(
                size: geometry.size,
                centre: progression.anchor,
                spanDegrees: Self.baseSpanDegrees / Double(committedZoom * zoom),
                pan: CGSize(
                    width: committedPan.width + pan.width,
                    height: committedPan.height + pan.height
                )
            )

            ZStack(alignment: .bottomTrailing) {
                Canvas(rendersAsynchronously: true) { context, size in
                    draw(in: &context, size: size, layout: layout, state: state)
                }
                .background(Theme.background)
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        panAndTapGesture(layout: layout),
                        magnifyGesture
                    )
                )

                if let arrivingStar,
                   let point = layout.point(for: arrivingStar.coordinate) {
                    ArrivalPulse(colour: Theme.starColor(bv: arrivingStar.colorIndex))
                        .position(point)
                        .allowsHitTesting(false)
                        // Keyed by star, so a second arrival restarts the
                        // animation rather than inheriting a finished one.
                        .id(arrivingStar.hr)
                }

                if isOffCentre {
                    Button {
                        withAnimation(.spring(duration: 0.4)) {
                            committedPan = .zero
                            committedZoom = 1
                            pan = .zero
                            zoom = 1
                        }
                    } label: {
                        Label("Recentre", systemImage: "scope")
                            .font(.footnote)
                            .labelStyle(.iconOnly)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .tint(Theme.starlight)
                    .padding(20)
                    .transition(.opacity)
                }
            }
        }
    }

    private struct LitState {
        let hrs: Set<Int>
        /// How far out, in degrees, the user has reached.
        let reach: Double
    }

    // MARK: - Drawing

    private func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        layout: ChartLayout,
        state: LitState
    ) {
        drawFrontier(in: &context, layout: layout, reach: state.reach)
        drawFigures(in: &context, layout: layout, state: state)

        // Unlit stars first, as a flat wash — no glow, so 1,500 of them stay
        // cheap and stay quiet.
        for star in catalog.stars where !state.hrs.contains(star.hr) {
            guard let point = layout.point(for: star.coordinate) else { continue }
            let radius = Theme.starRadius(magnitude: star.magnitude) * 0.55
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2
                )),
                with: .color(Theme.unlit.opacity(0.55))
            )
        }

        // All the glow in one blurred layer rather than one per star, which is
        // the difference between a smooth chart and a slideshow.
        let lit = catalog.stars.filter { state.hrs.contains($0.hr) }
        if !lit.isEmpty {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                for star in lit {
                    guard let point = layout.point(for: star.coordinate) else { continue }
                    let radius = Theme.starRadius(magnitude: star.magnitude) * 1.7
                    layer.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - radius, y: point.y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .color(Theme.starColor(bv: star.colorIndex).opacity(0.55))
                    )
                }
            }
            for star in lit {
                guard let point = layout.point(for: star.coordinate) else { continue }
                let radius = Theme.starRadius(magnitude: star.magnitude)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius, y: point.y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(Theme.starColor(bv: star.colorIndex))
                )
            }
        }

        drawOrigin(in: &context, layout: layout)
        drawLabels(in: &context, layout: layout, state: state)
    }

    /// A soft ring at the edge of what's been reached — the visible boundary of
    /// the user's sky, and the thing that grows.
    private func drawFrontier(in context: inout GraphicsContext, layout: ChartLayout, reach: Double) {
        guard reach > 0 else { return }
        let radius = reach * layout.pointsPerDegree
        let centre = layout.centrePoint
        let rect = CGRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(Theme.starlight.opacity(0.10)),
            lineWidth: 1
        )
    }

    /// The Sun at the centre — the one fixed point on the chart.
    ///
    /// Without it the map is a field of anonymous points with no sense of where
    /// the viewer stands. This is home: the projection's centre is the sky
    /// directly over the user at the moment they started, so the Sun marks
    /// where they're looking out from.
    private func drawOrigin(in context: inout GraphicsContext, layout: ChartLayout) {
        let centre = layout.centrePoint
        guard centre.x > -60, centre.x < layout.size.width + 60,
              centre.y > -60, centre.y < layout.size.height + 60 else { return }

        let sunRadius = 5.0
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            layer.fill(
                Path(ellipseIn: CGRect(
                    x: centre.x - sunRadius * 3, y: centre.y - sunRadius * 3,
                    width: sunRadius * 6, height: sunRadius * 6
                )),
                with: .color(Color(red: 1, green: 0.84, blue: 0.42).opacity(0.5))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(
                x: centre.x - sunRadius, y: centre.y - sunRadius,
                width: sunRadius * 2, height: sunRadius * 2
            )),
            with: .color(Color(red: 1, green: 0.95, blue: 0.80))
        )
    }

    /// Figure lines, drawn only where both ends are lit. A half-finished
    /// constellation shows the lines it has earned and no more, so the shape
    /// assembles as you go.
    private func drawFigures(in context: inout GraphicsContext, layout: ChartLayout, state: LitState) {
        for (_, edges) in catalog.figures {
            for edge in edges {
                guard state.hrs.contains(edge.0), state.hrs.contains(edge.1),
                      let a = catalog.star(hr: edge.0), let b = catalog.star(hr: edge.1),
                      let from = layout.point(for: a.coordinate),
                      let to = layout.point(for: b.coordinate) else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(Theme.starlight.opacity(0.28)), lineWidth: 0.8)
            }
        }
    }

    /// Names the figures the user has started, beneath each one.
    ///
    /// Without these the map is a field of anonymous dots — you can see you've
    /// done work, but not what the work *is*. Every started figure is offered a
    /// caption; any that would overlap one already placed is skipped rather
    /// than drawn on top, so a zoomed-out sky labels what it has room for and a
    /// zoomed-in one labels everything.
    ///
    /// Completed figures get a brighter caption than ones in progress, so the
    /// finished sky reads at a glance.
    private func drawLabels(in context: inout GraphicsContext, layout: ChartLayout, state: LitState) {
        var placed: [CGRect] = []

        // The Sun's caption goes down first and claims its space, so a
        // constellation label can't be drawn across the one fixed reference
        // point on the chart.
        let sunAnchor = CGPoint(x: layout.centrePoint.x, y: layout.centrePoint.y + 19)
        let sunCaption = Text("the Sun")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.starlight.opacity(0.7))
        _ = place(sunCaption, at: sunAnchor, in: &context, layout: layout, placed: &placed)

        for entry in progression.litStars(awardCount: litCount) {
            let lit = entry.constellation.stars.prefix(entry.litCount)
            // Hang the caption below the figure's lowest lit star rather than
            // its centre, so it sits under the shape instead of inside it.
            let points = lit.compactMap { layout.point(for: $0.coordinate) }
            guard let lowest = points.max(by: { $0.y < $1.y }) else { continue }
            let midX = points.map(\.x).reduce(0, +) / Double(points.count)
            let anchor = CGPoint(x: midX, y: lowest.y + 16)

            let isComplete = entry.litCount == entry.constellation.starCount
            let caption = Text(entry.constellation.name)
                .font(.system(size: 10, weight: isComplete ? .medium : .regular))
                .foregroundStyle(
                    isComplete
                        ? Theme.starlight.opacity(0.75)
                        : Theme.subdued.opacity(0.65)
                )
            _ = place(caption, at: anchor, in: &context, layout: layout, placed: &placed)
        }
    }

    /// Draws a caption if it fits entirely on screen and clears everything
    /// already placed. Returns the rect it took, or nil if it was skipped.
    ///
    /// Fully on screen, not merely overlapping: a half-drawn "…dus" hanging off
    /// the edge reads as a rendering fault rather than as a label.
    private func place(
        _ caption: Text,
        at anchor: CGPoint,
        in context: inout GraphicsContext,
        layout: ChartLayout,
        placed: inout [CGRect]
    ) -> CGRect? {
        let resolved = context.resolve(caption)
        let measured = resolved.measure(in: layout.size)
        let frame = CGRect(
            x: anchor.x - measured.width / 2 - 4,
            y: anchor.y - measured.height / 2 - 2,
            width: measured.width + 8,
            height: measured.height + 4
        )
        guard frame.minX >= 0, frame.maxX <= layout.size.width,
              frame.minY >= 0, frame.maxY <= layout.size.height else { return nil }
        guard !placed.contains(where: { $0.intersects(frame) }) else { return nil }

        placed.append(frame)
        context.draw(resolved, at: anchor, anchor: .center)
        return frame
    }

    // MARK: - Interaction

    /// Pan and tap from one gesture.
    ///
    /// A separate `onTapGesture` alongside a `DragGesture` doesn't work here:
    /// the drag claims the touch and the tap never arrives. Instead this uses a
    /// zero-distance drag and decides at the end — under the slop threshold it
    /// was a tap, past it a pan.
    private func panAndTapGesture(layout: ChartLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging,
                   hypot(value.translation.width, value.translation.height) > Self.dragSlop {
                    isDragging = true
                }
                if isDragging { pan = value.translation }
            }
            .onEnded { value in
                if isDragging {
                    committedPan.width += value.translation.width
                    committedPan.height += value.translation.height
                } else if let star = nearestStar(to: value.startLocation, layout: layout) {
                    onSelectStar?(star)
                }
                pan = .zero
                isDragging = false
            }
    }

    /// Points of travel before a touch counts as a pan. Roughly a fingertip's
    /// wobble — below this, someone meant to tap a star.
    private static let dragSlop: CGFloat = 10

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Clamp live as well as on commit, so pinching past the limit
                // doesn't rubber-band back and lose the user's place.
                zoom = (committedZoom * value.magnification)
                    .clamped(to: Self.zoomRange) / committedZoom
            }
            .onEnded { value in
                committedZoom = (committedZoom * value.magnification)
                    .clamped(to: Self.zoomRange)
                zoom = 1
            }
    }

    private func nearestStar(to location: CGPoint, layout: ChartLayout) -> Star? {
        var best: (Star, CGFloat)?
        for star in catalog.stars {
            guard let point = layout.point(for: star.coordinate) else { continue }
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance < 24, best == nil || distance < best!.1 {
                best = (star, distance)
            }
        }
        return best?.0
    }
}

/// Rings expanding out of a newly lit star.
///
/// Runs once and stops. A pulse that keeps going becomes decoration you learn
/// to ignore; this one exists to say "here" and then get out of the way.
private struct ArrivalPulse: View {
    let colour: Color

    @State private var phase: CGFloat = 0

    /// Long enough to be noticed by someone who has just changed screens and
    /// hasn't found the star yet — a pulse timed to the animation alone is over
    /// before the eye arrives.
    static let duration: Double = 2.2

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let delay = Double(index) * 0.34
                Circle()
                    .stroke(colour.opacity(0.75 * Double(1 - phase)), lineWidth: 2)
                    .frame(width: 18 + 104 * phase, height: 18 + 104 * phase)
                    .animation(
                        .easeOut(duration: Self.duration).delay(delay),
                        value: phase
                    )
            }
            Circle()
                .fill(colour.opacity(0.55 * Double(1 - phase)))
                .frame(width: 18, height: 18)
                .blur(radius: 7)
                .animation(.easeOut(duration: Self.duration), value: phase)
        }
        .onAppear { phase = 1 }
    }
}

/// Maps sky coordinates to view coordinates for one frame.
struct ChartLayout {
    let size: CGSize
    let centre: EquatorialCoordinate
    let spanDegrees: Double
    let pan: CGSize

    var pointsPerDegree: Double {
        Double(min(size.width, size.height)) / 2 / spanDegrees
    }

    var centrePoint: CGPoint {
        CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
    }

    /// Nil when the star falls outside the drawn area, so callers skip it
    /// rather than piling geometry off-screen.
    func point(for coordinate: EquatorialCoordinate) -> CGPoint? {
        let projected = SkyMath.project(coordinate, from: centre)
        guard projected.angularDistance < 178 else { return nil }

        let scale = pointsPerDegree
        // x is flipped so east renders left, as it does overhead.
        let point = CGPoint(
            x: centrePoint.x - projected.x * scale,
            y: centrePoint.y - projected.y * scale
        )
        let margin = 40.0
        guard point.x > -margin, point.x < size.width + margin,
              point.y > -margin, point.y < size.height + margin else { return nil }
        return point
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
