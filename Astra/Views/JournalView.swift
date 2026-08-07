import SwiftUI
import SwiftData

/// The log tab: a month of kept days, and the way back into any of them.
///
/// Backfilling is a first-class path, not an easter egg — forgetting to log
/// before bed must never cost the day. Tap any day the habits existed on and
/// edit it; the award ledger reconciles on its own.
struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]
    @Query private var completions: [Completion]

    @State private var displayedMonth: DayKey = .today()
    @State private var selectedDay: DayKey?

    private var store: HabitStore { HabitStore(context: context) }
    private var today: DayKey { store.today() }

    /// Days in the shown month with at least one keep, mapped to the colour
    /// indexes kept that day — the calendar dots.
    private var keptByDay: [DayKey: [Int]] {
        var result: [DayKey: [Int]] = [:]
        for completion in completions {
            guard completion.day.year == displayedMonth.year,
                  completion.day.month == displayedMonth.month,
                  let habit = completion.habit else { continue }
            result[completion.day, default: []].append(habit.colorIndex)
        }
        return result.mapValues { $0.sorted() }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    monthHeader
                    MonthGrid(
                        month: displayedMonth,
                        today: today,
                        keptByDay: keptByDay
                    ) { day in
                        selectedDay = day
                    }
                    consistencyFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .background(Theme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("LOG")
                            .font(Theme.label(11))
                            .kerning(1.8)
                            .foregroundStyle(Theme.starlight)
                        Text(displayedMonth.date().formatted(.dateTime.month(.abbreviated).year()))
                            .font(Theme.figure(9))
                            .kerning(0.5)
                            .foregroundStyle(Theme.unlit)
                    }
                }
            }
            .atlasSheet(item: $selectedDay, detents: [.medium]) { day in
                DaySheet(day: day)
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 14) {
            Text(displayedMonth.date().formatted(.dateTime.month(.wide)).uppercased())
                .font(Theme.label(11))
                .kerning(1.5)
                .foregroundStyle(Theme.starlight)
            Rectangle()
                .fill(Theme.rule)
                .frame(height: Theme.hairline)
            HStack(spacing: 14) {
                monthStep("−", enabled: true) { displayedMonth = monthShifted(by: -1) }
                monthStep("+", enabled: canGoForward) { displayedMonth = monthShifted(by: 1) }
            }
        }
    }

    private func monthStep(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(Theme.figure(15))
                .foregroundStyle(enabled ? Theme.subdued : Theme.rule)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var canGoForward: Bool {
        displayedMonth.year < today.year
            || (displayedMonth.year == today.year && displayedMonth.month < today.month)
    }

    private func monthShifted(by months: Int) -> DayKey {
        let anchor = DayKey(rawValue: displayedMonth.year * 10_000 + displayedMonth.month * 100 + 15)
        let moved = Calendar.current.date(byAdding: .month, value: months, to: anchor.date()) ?? anchor.date()
        return DayKey(moved)
    }

    /// The number that replaces a streak: how much of the last 30 days was
    /// kept, per habit. It dips and recovers — it never resets.
    /// Each habit's reading over the trailing month, set as a table with a
    /// scale beside the figure so the column can be read down at a glance
    /// rather than compared number by number.
    @ViewBuilder
    private var consistencyFooter: some View {
        let active = habits.filter { !$0.isArchived }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                MarginLabel(text: "Last 30 days")
                    .padding(.bottom, 10)

                ForEach(active) { habit in
                    let share = Stats.consistency(
                        keptDays: store.keptDays(for: habit),
                        window: 30,
                        endingOn: today,
                        startingNoEarlierThan: habit.createdOn
                    ) ?? 0

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Theme.habitColor(habit.colorIndex))
                                .frame(width: 7, height: 7)
                            Text(habit.name)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.starlight)
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            MeasuredScale(
                                fraction: share,
                                tint: Theme.habitColor(habit.colorIndex),
                                divisions: 4
                            )
                            .frame(width: 74)
                            Text("\(Int((share * 100).rounded()))%")
                                .font(Theme.figure(13))
                                .foregroundStyle(Theme.subdued)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .padding(.vertical, 11)

                        Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
                    }
                }
            }
        }
    }
}

extension DayKey: Identifiable {
    var id: Int { rawValue }
}

// MARK: - Month grid

private struct MonthGrid: View {
    let month: DayKey
    let today: DayKey
    let keptByDay: [DayKey: [Int]]
    let onSelect: (DayKey) -> Void

    private static let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(Theme.label(9))
                        .kerning(0.8)
                        .foregroundStyle(Theme.unlit)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        DayCell(
                            day: day,
                            isToday: day == today,
                            isFuture: day > today,
                            keptColors: keptByDay[day] ?? []
                        ) {
                            if day <= today { onSelect(day) }
                        }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month laid into weeks, nil-padded to the first weekday.
    private var cells: [DayKey?] {
        let calendar = Calendar.current
        let firstDay = DayKey(rawValue: month.year * 10_000 + month.month * 100 + 1)
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay.date())?.count ?? 30

        let weekday = calendar.component(.weekday, from: firstDay.date())
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [DayKey?] = Array(repeating: nil, count: leadingBlanks)
        for dayNumber in 1...dayCount {
            cells.append(DayKey(rawValue: month.year * 10_000 + month.month * 100 + dayNumber))
        }
        return cells
    }
}

private struct DayCell: View {
    let day: DayKey
    let isToday: Bool
    let isFuture: Bool
    let keptColors: [Int]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(day.day)")
                    .font(Theme.figure(13))
                    .foregroundStyle(isFuture ? Theme.rule : Theme.starlight)
                // Square marks in a keyed row, matching the chart legend and
                // the swatches beside each habit's name.
                HStack(spacing: 2) {
                    ForEach(keptColors.prefix(5), id: \.self) { colorIndex in
                        Rectangle()
                            .fill(Theme.habitColor(colorIndex))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(alignment: .bottom) {
                // Today is marked by a rule beneath rather than a box around —
                // the same device the week strip and tab bar use.
                if isToday {
                    Rectangle()
                        .fill(Theme.starlight)
                        .frame(height: 1.5)
                        .padding(.horizontal, 9)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }
}

// MARK: - Day editing

/// One day's habits, editable. Habits that didn't exist on this day are shown
/// but disabled with the reason, which beats their silent absence.
private struct DaySheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Habit.sortOrder)]) private var habits: [Habit]

    let day: DayKey

    @State private var errorMessage: String?

    private var store: HabitStore { HabitStore(context: context) }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AtlasPanel(
            title: day.date().formatted(.dateTime.weekday(.wide)),
            provenance: [day.date().formatted(.dateTime.day().month(.abbreviated).year())],
            trailing: .init(label: "Done", isProminent: true) { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(habits.filter { !$0.isArchived }) { habit in
                        let active = habit.isActive(on: day)
                        RuledEntry(
                            swatch: Theme.habitColor(habit.colorIndex),
                            title: habit.name,
                            subtitle: active ? nil : "not tracked yet",
                            isSpent: !active
                        ) {
                            Button {
                                toggle(habit)
                            } label: {
                                EntryMark(
                                    colour: Theme.habitColor(habit.colorIndex),
                                    isMarked: store.isKept(habit, on: day)
                                )
                                .opacity(active ? 1 : 0.35)
                            }
                            .buttonStyle(.plain)
                            .disabled(!active)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
        }
        .atlasAlert("Couldn't save that", message: $errorMessage)
    }

    private func toggle(_ habit: Habit) {
        do {
            try store.toggle(habit, on: day)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
