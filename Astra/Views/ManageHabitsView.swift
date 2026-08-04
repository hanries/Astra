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
        NavigationStack {
            List {
                Section {
                    ForEach(active) { habit in
                        row(habit)
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Tracking")
                } footer: {
                    Text("Drag to reorder. \(active.count) of \(HabitStore.maxActiveHabits) slots used.")
                }

                if !archived.isEmpty {
                    Section {
                        ForEach(archived) { habit in
                            archivedRow(habit)
                        }
                    } header: {
                        Text("Stopped")
                    } footer: {
                        Text("Their days still count and the stars they lit are still in the sky.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage habits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { habit in
                EditHabitSheet(habit: habit)
            }
            .alert("Something went wrong", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func row(_ habit: Habit) -> some View {
        Button {
            editing = habit
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Theme.habitColor(habit.colorIndex))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .foregroundStyle(Theme.starlight)
                    Text("^[\(habit.completions.count) day](inflect: true) recorded")
                        .font(.caption)
                        .foregroundStyle(Theme.subdued)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.unlit)
            }
        }
        .listRowBackground(Theme.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                act { try store.archive(habit) }
            } label: {
                Label("Stop", systemImage: "pause.circle")
            }
        }
    }

    private func archivedRow(_ habit: Habit) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.habitColor(habit.colorIndex).opacity(0.4))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .foregroundStyle(Theme.subdued)
                if let stopped = habit.archivedOn {
                    Text("Stopped \(stopped.date().formatted(.dateTime.month().day()))")
                        .font(.caption)
                        .foregroundStyle(Theme.unlit)
                }
            }
            Spacer()
            Button("Start again") {
                act { try store.unarchive(habit) }
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.borderless)
            .tint(Theme.starlight)
            .disabled(active.count >= HabitStore.maxActiveHabits)
        }
        .listRowBackground(Theme.surface.opacity(0.5))
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
