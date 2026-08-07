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
    @State private var showingManageHabits = false
    @State private var showingMenu = false
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

    /// Counted across every day, not just the shown one — the five-habit cap
    /// applies to what's being tracked, not to what was live last Tuesday.
    private var activeHabitCount: Int { habits.count { !$0.isArchived } }

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
                VStack(alignment: .leading, spacing: 24) {
                    WeekStrip(today: today, selection: $selectedDay) { day in
                        keptColorIndexes(on: day)
                    }
                    .padding(.horizontal, -20)

                    VStack(alignment: .leading, spacing: 24) {
                        progressHeader
                        if activeHabits.isEmpty {
                            emptyState
                        } else {
                            section(title: "To keep", habits: pending, isDone: false)
                            section(title: "Kept", habits: done, isDone: true)
                        }
                    }
                    .animation(.spring(response: 0.45, dampingFraction: 0.78), value: done.map(\.id))
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            // The system's large title is the single most recognisable piece of
            // stock iOS on the screen. The date belongs in the app's own
            // grammar — set as a chart heading, with the full date beneath it
            // the way a plate carries its observation date.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(isViewingToday ? "TODAY" : selectedDay.date()
                            .formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(Theme.label(11))
                            .kerning(1.8)
                            .foregroundStyle(Theme.starlight)
                        Text(selectedDay.date().formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(Theme.figure(9))
                            .kerning(0.5)
                            .foregroundStyle(Theme.unlit)
                    }
                }
            }
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
                    Button {
                        withAnimation(nil) { showingMenu = true }
                    } label: {
                        // A drawn cross rather than the system plus, so the one
                        // control in the bar matches the marks used everywhere
                        // else in the app.
                        ZStack {
                            Rectangle().fill(Theme.starlight).frame(width: 15, height: 1.5)
                            Rectangle().fill(Theme.starlight).frame(width: 1.5, height: 15)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    // Plain, or iOS 26 wraps it in the capsule it gives every
                    // toolbar button — the last piece of system chrome in the bar.
                    .buttonStyle(.plain)
                    .accessibilityLabel("Habits")
                }
            }
            .atlasSheet(isPresented: $showingAddHabit, detents: [.medium]) {
                AddHabitSheet()
            }
            .atlasSheet(isPresented: $showingManageHabits) {
                ManageHabitsView()
            }
            .atlasSheet(item: $historyHabit) { habit in
                HabitHistoryView(habit: habit)
            }
            .atlasAlert("Couldn't do that", message: $errorMessage)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: keptPulse)
        .overlay {
            if showingMenu {
                AtlasMenu(entries: [
                    .init(
                        label: "Add habit",
                        isEnabled: activeHabitCount < HabitStore.maxActiveHabits
                    ) { showingAddHabit = true },
                    .init(
                        label: "Manage habits",
                        isEnabled: !habits.isEmpty
                    ) { showingManageHabits = true },
                ]) {
                    showingMenu = false
                }
            }
        }
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

    /// The day's reading, set as a chart figure: the count large and
    /// monospaced, the denominator small beside it, a measured scale beneath.
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(done.count)")
                    .font(Theme.figure(44, weight: .light))
                    .foregroundStyle(Theme.starlight)
                    .contentTransition(.numericText())
                Text("/\(activeHabits.count)")
                    .font(Theme.figure(20, weight: .light))
                    .foregroundStyle(Theme.unlit)
                Spacer()
                Text(isViewingToday ? "KEPT TODAY" : "KEPT")
                    .font(Theme.label(10))
                    .kerning(1.4)
                    .foregroundStyle(Theme.subdued)
                    .offset(y: -4)
            }

            if !activeHabits.isEmpty {
                MeasuredScale(
                    fraction: Double(done.count) / Double(activeHabits.count),
                    tint: done.count == activeHabits.count
                        ? Theme.starlight
                        : Theme.habitColor(pending.first?.colorIndex ?? 0),
                    divisions: max(2, activeHabits.count)
                )
            }

            Text(statusLine)
                .font(.system(size: 13))
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)
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
            VStack(alignment: .leading, spacing: 0) {
                MarginLabel(text: title, count: habits.count)
                    .padding(.bottom, 4)

                ForEach(habits) { habit in
                    HabitEntry(
                        habit: habit,
                        isDone: isDone,
                        consistency: consistency(for: habit),
                        onToggle: { toggle(habit) },
                        onOpenHistory: { historyHabit = habit }
                    )
                    // Keyed by habit, so an entry travels between the two
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

/// One habit, as a logbook entry with two targets.
///
/// The entry body opens the habit's record and the mark logs the day. They're
/// different intents — one is the daily action, the other is looking back — and
/// sharing a tap would mean guessing which was meant. The mark carries a 44pt
/// target despite reading as 22.
private struct HabitEntry: View {
    let habit: Habit
    let isDone: Bool
    let consistency: Double?
    let onToggle: () -> Void
    let onOpenHistory: () -> Void

    private var tint: Color { Theme.habitColor(habit.colorIndex) }

    /// Set as a figure with its unit, the way a reading is quoted — not as a
    /// sentence, which at this size is just a long grey smear.
    private var reading: String? {
        guard let consistency else { return nil }
        return "\(Int((consistency * 100).rounded()))% · 30d"
    }

    var body: some View {
        RuledEntry(
            swatch: tint,
            title: habit.name,
            subtitle: reading,
            isSpent: isDone
        ) {
            Button(action: onToggle) {
                EntryMark(colour: tint, isMarked: isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.name), \(isDone ? "kept" : "not kept")")
            .accessibilityHint(isDone ? "Double tap to unmark" : "Double tap to mark kept")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenHistory)
        .accessibilityElement(children: .contain)
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
    @FocusState private var isNameFocused: Bool

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
        AtlasPanel(
            title: "New habit",
            leading: .init(label: "Cancel") { dismiss() },
            trailing: .init(label: "Add", isProminent: true, isEnabled: !trimmedName.isEmpty, action: save)
        ) {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    MarginLabel(text: "Name")
                    TextField("", text: $name, prompt: Text("Work out for an hour")
                        .foregroundStyle(Theme.unlit))
                        .textFieldStyle(.plain)
                        .font(.system(size: 19))
                        .foregroundStyle(Theme.starlight)
                        .tint(Theme.habitColor(colorIndex))
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.ruleStrong).frame(height: Theme.hairline)
                        }
                }

                VStack(alignment: .leading, spacing: 12) {
                    MarginLabel(text: "Key")
                    HStack(spacing: 0) {
                        ForEach(0..<Theme.habitPalette.count, id: \.self) { index in
                            Button {
                                colorIndex = index
                            } label: {
                                VStack(spacing: 8) {
                                    Rectangle()
                                        .fill(Theme.habitPalette[index])
                                        .frame(width: 22, height: 22)
                                    Rectangle()
                                        .fill(index == colorIndex ? Theme.starlight : .clear)
                                        .frame(width: 22, height: 2)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Colour \(index + 1)")
                            .accessibilityAddTraits(index == colorIndex ? [.isSelected] : [])
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
        }
        .onAppear {
            colorIndex = suggestedColorIndex
            isNameFocused = true
        }
        .atlasAlert("Couldn't add that", message: $errorMessage)
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
