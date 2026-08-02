import SwiftUI

/// The moment a star lights.
///
/// This is the payoff the whole app is arranged around, so it gets the one
/// genuinely theatrical animation in the product: the sky darkens, the star
/// swells out of nothing, rays sweep out behind it, and its name arrives.
/// Everything else stays quiet so that this reads as an event.
///
/// Dismissed by tapping anywhere. It never blocks — there is no button to find
/// and no way to get stuck behind it.
struct StarUnlockView: View {
    let star: Star
    let constellation: Constellation
    /// Stars lit in this constellation *including* the new one.
    let litCount: Int
    let onDismiss: () -> Void

    @State private var phase: CGFloat = 0
    @State private var raysPhase: CGFloat = 0
    @State private var textPhase: CGFloat = 0

    private var isFigureComplete: Bool { litCount >= constellation.starCount }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82 * phase)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    rays
                    StarPortrait(star: star, diameter: 180)
                        .scaleEffect(0.4 + 0.6 * phase)
                        .opacity(Double(phase))
                }
                .frame(height: 300)

                VStack(spacing: 10) {
                    Text(isFigureComplete ? "\(constellation.name) complete" : "You lit")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.subdued)
                        .textCase(.uppercase)
                        .kerning(1.4)

                    Text(star.displayName)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .foregroundStyle(Theme.starlight)
                        .multilineTextAlignment(.center)

                    Text(progressLine)
                        .font(.callout)
                        .foregroundStyle(Theme.subdued)
                }
                .opacity(Double(textPhase))
                .offset(y: 14 * (1 - textPhase))

                Text("Tap to continue")
                    .font(.footnote)
                    .foregroundStyle(Theme.subdued.opacity(0.7))
                    .opacity(Double(textPhase) * 0.9)
                    .padding(.top, 8)
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .onAppear(perform: animateIn)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("You lit \(star.displayName). \(progressLine)")
        .accessibilityAction(named: "Continue", dismiss)
    }

    private var progressLine: String {
        if isFigureComplete {
            "All \(constellation.starCount) stars lit"
        } else {
            "\(constellation.name) · \(litCount) of \(constellation.starCount)"
        }
    }

    /// Light sweeping outward from the star. Drawn rather than illustrated, in
    /// the star's own colour, and fading as it goes so the edge never has to be
    /// resolved.
    private var rays: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let colour = Theme.starColor(bv: star.colorIndex)
            let count = 14

            for index in 0..<count {
                // Irregular spacing, so it reads as light rather than a wheel.
                let jitter = Double((index * 37) % 11) / 11 * 0.4
                let angle = (Double(index) / Double(count) + jitter / Double(count)) * 2 * .pi
                let length = (110 + Double((index * 53) % 70)) * Double(raysPhase)
                let width = 1.5 + Double((index * 29) % 3)

                var path = Path()
                path.move(to: centre)
                path.addLine(to: CGPoint(
                    x: centre.x + cos(angle) * length,
                    y: centre.y + sin(angle) * length
                ))
                context.stroke(
                    path,
                    with: .color(colour.opacity(0.30 * Double(1 - raysPhase))),
                    lineWidth: width
                )
            }
        }
        .frame(width: 320, height: 320)
        .blur(radius: 2)
        .allowsHitTesting(false)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) {
            phase = 1
        }
        withAnimation(.easeOut(duration: 1.1)) {
            raysPhase = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.35)) {
            textPhase = 1
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.22)) {
            phase = 0
            textPhase = 0
        }
        // Let the fade finish before the view is torn out from under it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: onDismiss)
    }
}
