import SwiftUI

/// The launch screen, continued.
///
/// The system paints a still of the sun and the wordmark before any of this
/// code runs, and then dissolves it into whatever the app draws first. Dusk
/// draws this, which is that same still from the same two assets in the same
/// two places, so the dissolve has nothing to cross and the word arrives once
/// rather than twice.
///
/// The arrangement is duplicated in LaunchScreen.storyboard because a launch
/// screen cannot run code. `Tools/make_launch_mark.swift` prints the offsets
/// both sides use; changing the design means moving all three together.
struct LaunchMark: View {
    /// Faded by the caller once the sky has something else to show.
    var sunOpacity: Double = 1

    /// Where the lockup's centre sits, as a fraction of the screen's height.
    /// A group centred on the true middle reads low.
    static let centre: CGFloat = 0.45
    static let sunOffset: CGFloat = -35.81
    static let wordOffset: CGFloat = 81

    var body: some View {
        GeometryReader { geometry in
            let x = geometry.size.width / 2
            let y = geometry.size.height * Self.centre

            Image("LaunchSun")
                .position(x: x, y: y + Self.sunOffset)
                .opacity(sunOpacity)

            Image("LaunchWord")
                .position(x: x, y: y + Self.wordOffset)
        }
        // Measured against the whole screen, as the storyboard's constraints
        // are. Inset by the safe area the two would disagree by the height of
        // the status bar.
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
