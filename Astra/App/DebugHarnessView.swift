import SwiftUI
import SwiftData

/// Scaffolding, not design.
///
/// A plain list that exercises `HabitStore` so the core can be run and poked at
/// on device before the artifact exists. Delete this whole file when the real
/// UI lands — nothing else should come to depend on it.
struct DebugHarnessView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    @State private var newName = ""
    @State private var offset = 0
    @State private var awardCount = 0
    @State private var error: String?

    private var store: HabitStore { HabitStore(context: context) }
    private var day: DayKey { store.today().advanced(by: -offset) }

    var body: some View {
        NavigationStack {
            List {
                Section("Day") {
                    Stepper(
                        String("\(day)\(offset == 0 ? " (today)" : "")"),
                        value: $offset, in: 0...400
                    )
                    LabeledContent("Awards", value: "\(awardCount)")
                }

                Section("Habits") {
                    ForEach(habits.filter { !$0.isArchived }) { habit in
                        Button {
                            act { try store.toggle(habit, on: day) }
                        } label: {
                            HStack {
                                Image(systemName: store.isKept(habit, on: day)
                                      ? "checkmark.circle.fill" : "circle")
                                Text(habit.name)
                                Spacer()
                                Text("\(habit.completions.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!habit.isActive(on: day))
                    }
                    .onDelete { indexSet in
                        let active = habits.filter { !$0.isArchived }
                        act { for i in indexSet { try store.archive(active[i]) } }
                    }
                }

                Section("Add") {
                    HStack {
                        TextField("Habit name", text: $newName)
                        Button("Add") {
                            act {
                                try store.addHabit(name: newName, colorIndex: habits.count)
                                newName = ""
                            }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Astra — core")
            .task { refresh() }
        }
    }

    private func act(_ work: () throws -> Void) {
        do {
            try work()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        awardCount = (try? store.awardCount()) ?? 0
    }
}
