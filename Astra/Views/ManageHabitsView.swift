import SwiftUI
import SwiftData

/// Every habit in one place: reorder them, edit them, stop them, start them
/// again.
///
/// A `List` rather than the card stack used on Today, because reordering and
/// swipe actions are things people already know how to do to a list, and this
/// screen is for maintenance rather than for the daily loop.
struct ManageHabitsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    @State private var editing: Habit?
    @State private var errorMessage: String?

    private var store: HabitStore { HabitStore(context: context) }
    private var active: [Habit] { habits.filter { !$0.isArchived } }
    private var archived: [Habit] { habits.filter(\.isArchived) }

    var body: some View {
        AtlasPanel(
            title: "Habits",
            provenance: ["\(active.count) of \(HabitStore.maxActiveHabits) tracked"],
            trailing: .init(label: "Done", isProminent: true) { dismiss() }
        ) {
            // A List, not a VStack, purely because reordering needs it — but
            // stripped of every default surface so it reads as ruled entries
            // rather than as an inset-grouped settings screen.
            List {
                Section {
                    ForEach(active) { habit in
                        row(habit)
                    }
                    .onMove(perform: move)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    MarginLabel(text: "Tracking")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                }

                if !archived.isEmpty {
                    Section {
                        ForEach(archived) { habit in
                            archivedRow(habit)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } header: {
                        MarginLabel(text: "Stopped")
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                            .padding(.bottom, 4)
                    } footer: {
                        Text("Their days still count and the stars they lit are still in the sky.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.unlit)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .environment(\.editMode, .constant(.active))
        }
        .atlasSheet(item: $editing) { habit in
            EditHabitSheet(habit: habit)
        }
        .atlasAlert("Couldn't do that", message: $errorMessage)
    }

    private func row(_ habit: Habit) -> some View {
        RuledEntry(
            swatch: Theme.habitColor(habit.colorIndex),
            title: habit.name,
            subtitle: "^[\(habit.completions.count) day](inflect: true) recorded"
        ) {
            EmptyView()
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = habit }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                act { try store.archive(habit) }
            } label: {
                Text("Stop")
            }
        }
    }

    private func archivedRow(_ habit: Habit) -> some View {
        RuledEntry(
            swatch: Theme.habitColor(habit.colorIndex),
            title: habit.name,
            subtitle: habit.archivedOn.map {
                "stopped \($0.date().formatted(.dateTime.day().month(.abbreviated)))"
            },
            isSpent: true
        ) {
            Button {
                act { try store.unarchive(habit) }
            } label: {
                Text("START AGAIN")
                    .font(Theme.label(9))
                    .kerning(1.1)
                    .foregroundStyle(active.count >= HabitStore.maxActiveHabits
                                     ? Theme.rule : Theme.starlight)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .overlay {
                        Rectangle()
                            .strokeBorder(active.count >= HabitStore.maxActiveHabits
                                          ? Theme.rule : Theme.ruleStrong,
                                          lineWidth: Theme.hairline)
                    }
            }
            .buttonStyle(.plain)
            .disabled(active.count >= HabitStore.maxActiveHabits)
        }
    }

    /// `onMove` hands back indices into the active list, so the reorder is
    /// applied to that slice and written back as `sortOrder`.
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = active
        ordered.move(fromOffsets: source, toOffset: destination)
        act { try store.reorder(ordered) }
    }

    private func act(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
