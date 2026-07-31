import SwiftUI
import SwiftData

/// The home tab: today's habits, and the star each kept day lights.
///
/// One rule shapes everything here: the tap that logs a habit is the whole
/// app, so it gets the size, the spring, and the haptic. Everything else stays
/// quiet.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\Award.ordinal)]) private var awards: [Award]

    let progression: SkyProgression

    @State private var showingAddHabit = false
    @State private var errorMessage: String?
    @State private var keptPulse = 0

    private var store: HabitStore { HabitStore(context: context) }
    private var today: DayKey { store.today() }
    private var activeHabits: [Habit] { habits.filter { !$0.isArchived } }
    private var keptToday: Int { activeHabits.count { store.isKept($0, on: today) } }

    /// The star today's keeping lit — the newest award, if it was earned today.
    private var todaysStar: (constellation: Constellation, star: Star)? {
        guard let latest = awards.last, latest.day == today else { return nil }
        return progression.star(forOrdinal: latest.ordinal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    starBanner
                    habitList
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddHabit = true
                    } label: {
                        Label("Add habit", systemImage: "plus")
                    }
                    .disabled(activeHabits.count >= HabitStore.maxActiveHabits)
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                AddHabitSheet()
                    .presentationDetents([.medium])
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
        .sensoryFeedback(.impact(weight: .medium), trigger: keptPulse)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if activeHabits.isEmpty {
                Text("Add a habit to start lighting the sky.")
                    .font(.callout)
                    .foregroundStyle(Theme.subdued)
            } else {
                Text("\(keptToday) of \(activeHabits.count) kept today")
                    .font(.callout)
                    .foregroundStyle(Theme.subdued)
                    .contentTransition(.numericText())
            }
        }
    }

    /// The payoff line. Before the first keep of the day it names what's at
    /// stake; after, it names what was lit. Phrased as reward, never as loss.
    @ViewBuilder
    private var starBanner: some View {
        if let lit = todaysStar {
            HStack(spacing: 12) {
                StarDot(
                    color: Theme.starColor(bv: lit.star.colorIndex),
                    radius: Theme.starRadius(magnitude: lit.star.magnitude),
                    isLit: true
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("You lit \(lit.star.displayName)")
                        .font(.headline)
                        .foregroundStyle(Theme.starlight)
                    Text("\(lit.constellation.name) · magnitude \(lit.star.magnitude, format: .number.precision(.fractionLength(1)))")
                        .font(.caption)
                        .foregroundStyle(Theme.subdued)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else if let next = progression.star(forOrdinal: awards.count), !activeHabits.isEmpty {
            HStack(spacing: 12) {
                StarDot(
                    color: Theme.starColor(bv: next.star.colorIndex),
                    radius: Theme.starRadius(magnitude: next.star.magnitude),
                    isLit: false
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight's star: \(next.star.displayName)")
                        .font(.headline)
                        .foregroundStyle(Theme.subdued)
                    Text("Keep any habit today to light it")
                        .font(.caption)
                        .foregroundStyle(Theme.subdued)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var habitList: some View {
        VStack(spacing: 12) {
            ForEach(activeHabits) { habit in
                HabitRow(
                    habit: habit,
                    isKept: store.isKept(habit, on: today)
                ) {
                    toggle(habit)
                }
            }
        }
    }

    private func toggle(_ habit: Habit) {
        do {
            let nowKept = try store.toggle(habit, on: today)
            if nowKept { keptPulse += 1 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One habit, one big target. The whole row toggles — nobody should have to
/// hit a 24-point circle to log the thing this app exists for.
private struct HabitRow: View {
    let habit: Habit
    let isKept: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Theme.habitColor(habit.colorIndex))
                    .frame(width: 10, height: 10)
                Text(habit.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isKept ? Theme.subdued : Theme.starlight)
                    .strikethrough(isKept, color: Theme.subdued)
                Spacer()
                Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isKept ? Theme.habitColor(habit.colorIndex) : Theme.unlit)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.35), value: isKept)
    }
}

/// A star rendered the only way this app renders anything: a glowing dot whose
/// colour and size are measurements, not art direction.
struct StarDot: View {
    let color: Color
    let radius: Double
    let isLit: Bool

    var body: some View {
        ZStack {
            if isLit {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: radius * 4, height: radius * 4)
                    .blur(radius: radius)
            }
            Circle()
                .fill(isLit ? color : .clear)
                .stroke(isLit ? color : Theme.unlit, lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
        }
        .frame(width: 30, height: 30)
    }
}

/// Creating a habit: a name, a colour, nothing else to configure.
struct AddHabitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var habits: [Habit]

    @State private var name = ""
    @State private var colorIndex = 0
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First palette colour no active habit is using, so new habits differ by
    /// default without forbidding repeats.
    private var suggestedColorIndex: Int {
        let used = Set(habits.filter { !$0.isArchived }.map(\.colorIndex))
        return (0..<Theme.habitPalette.count).first { !used.contains($0) } ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Habit name", text: $name, prompt: Text("Work out for an hour"))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(Theme.starlight)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .submitLabel(.done)
                    .onSubmit(save)

                HStack(spacing: 16) {
                    ForEach(0..<Theme.habitPalette.count, id: \.self) { index in
                        Button {
                            colorIndex = index
                        } label: {
                            Circle()
                                .fill(Theme.habitPalette[index])
                                .frame(width: 34, height: 34)
                                .overlay {
                                    if index == colorIndex {
                                        Circle().stroke(Theme.starlight, lineWidth: 2).padding(-5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(index + 1)")
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { colorIndex = suggestedColorIndex }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        do {
            try HabitStore(context: context).addHabit(name: trimmedName, colorIndex: colorIndex)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
