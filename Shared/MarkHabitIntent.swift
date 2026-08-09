import AppIntents
import Foundation
import SwiftData

/// Marks or unmarks one habit for today.
///
/// The widget's marks call this, which is why it lives in shared code. It costs
/// nothing extra to also make it the action Siri and the Action Button use
/// later; an App Intent is the same object either way.
struct MarkHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a habit"
    static var description = IntentDescription("Records a habit as kept for today.")
    /// Runs without bringing the app forward. The point of the widget is that
    /// logging never costs a launch.
    static var openAppWhenRun = false

    @Parameter(title: "Habit")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { return .result() }
        // No store means no habits to mark, and opening the container would
        // create one from the widget's side. See `AstraStore.storeExists`.
        guard AstraStore.storeExists else { return .result() }

        let context = ModelContext(AstraStore.container)
        let store = HabitStore(context: context)
        let today = store.today()

        guard let habit = try store.allHabits().first(where: { $0.id == id }) else {
            return .result()
        }
        try store.toggle(habit, on: today)
        return .result()
    }
}
