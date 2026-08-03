import SwiftUI
import SwiftData

/// The home tab: today's habits, and the star each kept day lights.
///
/// Habits live in two sections and physically move between them. A card that
/// slides from "To do" into "Done" gives the completion somewhere to *go* —
/// a checkbox that dims in place says the same thing and feels like nothing.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\Award.ordinal)]) private var awards: [Award]

    let progression: SkyProgression
    /// Called once the unlock card is dismissed, so the app can take the user
    /// to where the star now lives.
    var onStarLit: (Star) -> Void = { _ in }

    @State private var showingAddHabit = false
    @State private var errorMessage: String?
    @State private var keptPulse = 0
    @State private var celebration: Celebration?
    @State private var historyHabit: Habit?
    /// The day the list is showing. Defaults to today; the strip moves it.
    @State private var selectedDay: DayKey = .today()
    @Namespace private var cardTransition

    private var store: HabitStore { HabitStore(context: context) }
    private var today: DayKey { store.today() }
    private var isViewingToday: Bool { selectedDay == today }

    /// Habits that existed on the shown day. A habit added this week doesn't
    /// appear on last Tuesday, where it would only be an unfillable blank.
    private var activeHabits: [Habit] {
        habits.filter { !$0.isArchived && $0.isActive(on: selectedDay) }
    }

    private var pending: [Habit] { activeHabits.filter { !store.isKept($0, on: selectedDay) } }
    private var done: [Habit] { activeHabits.filter { store.isKept($0, on: selectedDay) } }

    /// What the celebration overlay needs. Captured at the moment the star is
    /// earned, because by the time it's dismissed the counts have moved on.
    private struct Celebration: Identifiable {
        let id: Int
        let star: Star
        let constellation: Constellation
        let litCount: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WeekStrip(today: today, selection: $selectedDay) { day in
                        keptColorIndexes(on: day)
                    }
                    .padding(.horizontal, -20)

                    VStack(alignment: .leading, spacing: 26) {
                        progressHeader
                        if activeHabits.isEmpty {
                            emptyState
                        } else {
                            section(title: "To do", habits: pending, isDone: false)
                            section(title: "Done", habits: done, isDone: true)
                        }
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: done.map(\.id))
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(navigationTitle)
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Debug", systemImage: "ladybug") {
                        Button("Seed 60 days") { act { try DebugSeed.fill(context: context) } }
                        Button("Clear all", role: .destructive) {
                            act { try DebugSeed.clear(context: context) }
                        }
                    }
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddHabit = true } label: {
                        Label("Add habit", systemImage: "plus")
                    }
                    .disabled(activeHabits.count >= HabitStore.maxActiveHabits)
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                AddHabitSheet().presentationDetents([.medium])
            }
            .sheet(item: $historyHabit) { habit in
                HabitHistoryView(habit: habit)
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
        .overlay {
            if let celebration {
                StarUnlockView(
                    star: celebration.star,
                    constellation: celebration.constellation,
                    litCount: celebration.litCount
                ) {
                    let star = celebration.star
                    self.celebration = nil
                    onStarLit(star)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Header

    private var navigationTitle: String {
        isViewingToday
            ? "Today"
            : selectedDay.date().formatted(.dateTime.weekday(.wide).month().day())
    }

    /// Colour indexes of habits kept on a day, for the strip's dots.
    private func keptColorIndexes(on day: DayKey) -> [Int] {
        habits
            .filter { !$0.isArchived && store.isKept($0, on: day) }
            .map(\.colorIndex)
            .sorted()
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(done.count)")
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.starlight)
                    .contentTransition(.numericText())
                Text("of \(activeHabits.count) kept\(isViewingToday ? " today" : "")")
                    .font(.callout)
                    .foregroundStyle(Theme.subdued)
            }

            if !activeHabits.isEmpty {
                ProgressBar(
                    fraction: Double(done.count) / Double(activeHabits.count),
                    tint: done.count == activeHabits.count
                        ? Theme.starlight
                        : Theme.habitColor(pending.first?.colorIndex ?? 0)
                )
                .frame(height: 6)
            }

            Text(statusLine)
                .font(.footnote)
                .foregroundStyle(Theme.subdued)
        }
    }

    /// Never mentions what was missed. The line either names what's next or
    /// marks the day done — there's no version of this that reads as a telling
    /// off.
    /// Names what's next, or marks the day done. There's no wording of this
    /// that reports what was missed — a partial day costs the next star, and
    /// that's plain enough from the count above without being said twice.
    private var statusLine: String {
        guard !activeHabits.isEmpty else {
            return isViewingToday
                ? "Add a habit to start lighting the sky."
                : "Nothing was being tracked on this day."
        }
        if pending.isEmpty {
            return "Everything kept. The sky is brighter for it."
        }
        guard isViewingToday else {
            return done.isEmpty
                ? "Nothing kept. You can still fill it in."
                : "\(pending.count) still to fill in."
        }
        let target = progression.star(forOrdinal: awards.count)?.star.displayName
        let goal = target.map { "light \($0)" } ?? "light a new star"
        return activeHabits.count == 1
            ? "Keep it today to \(goal)."
            : "Keep all \(activeHabits.count) today to \(goal)."
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing tracked yet")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.starlight)
            Text("One habit is enough to start. You can add up to \(HabitStore.maxActiveHabits).")
                .font(.callout)
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 30)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(title: String, habits: [Habit], isDone: Bool) -> some View {
        if !habits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.subdued)
                    Text("\(habits.count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Theme.subdued.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surface, in: Capsule())
                }

                ForEach(habits) { habit in
                    HabitCard(
                        habit: habit,
                        isDone: isDone,
                        consistency: consistency(for: habit),
                        onToggle: { toggle(habit) },
                        onOpenHistory: { historyHabit = habit }
                    )
                    // Keyed by habit, so a card animates between the two
                    // sections rather than one vanishing and another appearing.
                    .matchedGeometryEffect(id: habit.id, in: cardTransition)
                }
            }
        }
    }

    /// Share of the 30 days ending on the shown day, clamped to when the habit
    /// started — so a habit added yesterday reads 100%, not 3%.
    private func consistency(for habit: Habit) -> Double? {
        Stats.consistency(
            keptDays: store.keptDays(for: habit),
            window: 30,
            endingOn: selectedDay,
            startingNoEarlierThan: habit.createdOn
        )
    }

    // MARK: - Actions

    private func toggle(_ habit: Habit) {
        let before = (try? store.awardCount()) ?? 0
        act {
            if try store.toggle(habit, on: selectedDay) { keptPulse += 1 }
        }
        let after = (try? store.awardCount()) ?? 0
        guard after > before, let earned = try? store.allAwards().last else { return }
        guard let hit = progression.star(forOrdinal: earned.ordinal) else { return }

        // How many of that figure are lit now, for the "3 of 7" line.
        let litInFigure = progression.litStars(awardCount: after)
            .first { $0.constellation.abbreviation == hit.constellation.abbreviation }?
            .litCount ?? 1

        celebration = Celebration(
            id: earned.ordinal,
            star: hit.star,
            constellation: hit.constellation,
            litCount: litInFigure
        )
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

// MARK: - Card

/// One habit, with two targets.
///
/// The card body opens the habit's history and the checkmark logs the day.
/// They're different intents — one is the daily action, the other is looking
/// back — and sharing a tap would mean guessing which was meant. The circle is
/// sized to 44pt so the daily one stays comfortably hittable despite being the
/// smaller of the two.
private struct HabitCard: View {
    let habit: Habit
    let isDone: Bool
    let consistency: Double?
    let onToggle: () -> Void
    let onOpenHistory: () -> Void

    private var tint: Color { Theme.habitColor(habit.colorIndex) }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpenHistory) {
                HStack(spacing: 14) {
                    // The colour bar carries habit identity down the whole card
                    // rather than sitting in a dot you have to look for.
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(isDone ? 0.45 : 1))
                        .frame(width: 4)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(habit.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(isDone ? Theme.subdued : Theme.starlight)
                            .strikethrough(isDone, color: Theme.subdued.opacity(0.6))
                            .multilineTextAlignment(.leading)

                        if let consistency {
                            Text("\(consistency.formatted(.percent.precision(.fractionLength(0)))) of the last 30 days")
                                .font(.caption)
                                .foregroundStyle(Theme.subdued.opacity(isDone ? 0.6 : 0.9))
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(habit.name)
            .accessibilityHint("Double tap to see this habit's history")

            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(isDone ? tint : Theme.unlit, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    if isDone {
                        Circle().fill(tint).frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.background)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel("\(habit.name), \(isDone ? "kept" : "not kept")")
            .accessibilityHint(isDone ? "Double tap to unmark" : "Double tap to mark kept")
        }
        .padding(.vertical, 14)
        .padding(.trailing, 12)
        .padding(.leading, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.surface.opacity(isDone ? 0.45 : 1))
        )
    }
}

/// A card that gives under the finger. The only motion in the list that isn't
/// the completion itself.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
    }
}

// MARK: - Adding

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
                    Button("Add", action: save).disabled(trimmedName.isEmpty)
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

/// A star rendered as a dot: colour and size are measurements, not art
/// direction. Used wherever a full portrait would be too much.
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
