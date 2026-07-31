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

/// Three tabs, all labelled. The lesson from the apps this one admires is that
/// the sensory budget goes into the log action itself — never into making the
/// navigation a puzzle.
struct RootView: View {
    let progression: SkyProgression

    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                TodayView(progression: progression)
            }
            Tab("Sky", systemImage: "sparkles") {
                SkyMapView(progression: progression)
            }
            Tab("Log", systemImage: "calendar") {
                JournalView()
            }
        }
        .tint(Theme.starlight)
    }
}
