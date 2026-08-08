import SwiftUI
import SwiftData

@main
struct AstraApp: App {
    /// Frozen on first launch from wherever the user is standing; stable for
    /// the life of the install. See `SkyProgressionStore`.
    private let progression = SkyProgressionStore.load(catalog: .shared)

    @AppStorage(OnboardingView.seenKey) private var hasSeenFirstLight = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenFirstLight {
                    RootView(progression: progression)
                } else {
                    OnboardingView(progression: progression) {
                        withAnimation(.easeInOut(duration: 0.6)) { hasSeenFirstLight = true }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Habit.self, Completion.self, Award.self])
    }
}

enum AppTab: Hashable {
    case today, sky, log
}

/// Three tabs, all labelled. The lesson from the apps this one admires is that
/// the sensory budget goes into the log action itself — never into making the
/// navigation a puzzle.
struct RootView: View {
    let progression: SkyProgression

    @State private var tab: AppTab = .today
    /// The star just earned, carried across so the sky can point at it on
    /// arrival. Cleared once the map has had its moment.
    @State private var arrivingStar: Star?

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.today) {
                TodayView(progression: progression) { star in
                    // Completing the day ends by showing the day's result:
                    // dismiss the card, cross to the sky, land on the star.
                    arrivingStar = star
                    withAnimation(.easeInOut(duration: 0.35)) { tab = .sky }
                }
                .hidingSystemTabBar()
            }
            Tab(value: AppTab.sky) {
                SkyMapView(progression: progression, arrivingStar: $arrivingStar)
                    .hidingSystemTabBar()
            }
            Tab(value: AppTab.log) {
                JournalView()
                    .hidingSystemTabBar()
            }
        }
        // Inset rather than overlaid, so scroll views end above the bar
        // instead of running under it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AxisTabBar(selection: $tab)
        }
        .tint(Theme.starlight)
    }
}

private extension View {
    /// Hides the system tab bar.
    ///
    /// The modifier has to sit on the tab's *content*, not on the `TabView` —
    /// applied to the container it leaves the bar's material visible behind
    /// whatever replaces it, which shows up as a faint capsule ghosting under
    /// the custom bar.
    func hidingSystemTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

/// Navigation as a divided scale.
///
/// Three divisions on a rule, the current one marked by a major tick — the
/// same device the week strip uses for days, so moving between tabs and moving
/// between days read as the same kind of act. No icons: at this size a symbol
/// is either ambiguous or redundant next to its own label, and every app on the
/// phone draws from the same symbol set.
struct AxisTabBar: View {
    @Binding var selection: AppTab

    private let divisions: [(tab: AppTab, name: String)] = [
        (.today, "Today"),
        (.sky, "Sky"),
        (.log, "Log"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.rule)
                .frame(height: Theme.hairline)

            HStack(spacing: 0) {
                ForEach(divisions, id: \.tab) { division in
                    let isCurrent = division.tab == selection
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            selection = division.tab
                        }
                    } label: {
                        VStack(spacing: 7) {
                            Rectangle()
                                .fill(isCurrent ? Theme.starlight : Theme.rule)
                                .frame(width: isCurrent ? 16 : Theme.hairline,
                                       height: isCurrent ? 2 : 5)
                                .frame(height: 5, alignment: .top)
                            Text(division.name.uppercased())
                                .font(Theme.label(10))
                                .kerning(1.5)
                                .foregroundStyle(isCurrent ? Theme.starlight : Theme.subdued)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 9)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(division.name)
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                }
            }
        }
        .background(Theme.background)
    }
}
