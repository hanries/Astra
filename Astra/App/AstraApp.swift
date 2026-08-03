import SwiftUI
import SwiftData

@main
struct AstraApp: App {
    /// Frozen on first launch from wherever the user is standing; stable for
    /// the life of the install. See `SkyProgressionStore`.
    private let progression = SkyProgressionStore.load(catalog: .shared)

    var body: some Scene {
        WindowGroup {
            RootView(progression: progression)
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
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                TodayView(progression: progression) { star in
                    // Completing the day ends by showing the day's result:
                    // dismiss the card, cross to the sky, and land on the star.
                    arrivingStar = star
                    withAnimation(.easeInOut(duration: 0.35)) { tab = .sky }
                }
            }
            Tab("Sky", systemImage: "sparkles", value: AppTab.sky) {
                SkyMapView(progression: progression, arrivingStar: $arrivingStar)
            }
            Tab("Log", systemImage: "calendar", value: AppTab.log) {
                JournalView()
            }
        }
        .tint(Theme.starlight)
    }
}
