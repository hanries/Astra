import SwiftUI
import SwiftData

@main
struct AstraApp: App {
    var body: some Scene {
        WindowGroup {
            DebugHarnessView()
        }
        .modelContainer(for: [Habit.self, Completion.self, Award.self])
    }
}
