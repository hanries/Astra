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
                VStack(spacing: 20) {
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
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Log")
            .sheet(item: $selectedDay) { day in
                DaySheet(day: day)
                    .presentationDetents([.medium])
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                displayedMonth = monthShifted(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.subdued)
            }
            Spacer()
            Text(displayedMonth.date().formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .foregroundStyle(Theme.starlight)
            Spacer()
            Button {
                displayedMonth = monthShifted(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(canGoForward ? Theme.subdued : Theme.unlit)
            }
            .disabled(!canGoForward)
        }
        .buttonStyle(.plain)
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
    @ViewBuilder
    private var consistencyFooter: some View {
        let active = habits.filter { !$0.isArchived }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 30 days")
                    .font(.headline)
                    .foregroundStyle(Theme.subdued)
                ForEach(active) { habit in
                    let kept = store.keptDays(for: habit)
                    let share = Stats.consistency(
                        keptDays: kept,
                        window: 30,
                        endingOn: today,
                        startingNoEarlierThan: habit.createdOn
                    ) ?? 0
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Theme.habitColor(habit.colorIndex))
                            .frame(width: 8, height: 8)
                        Text(habit.name)
                            .font(.callout)
                            .foregroundStyle(Theme.starlight)
                        Spacer()
                        Text(share, format: .percent.precision(.fractionLength(0)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Theme.subdued)
                    }
                }
            }
            .padding(16)
            .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
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
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(Theme.subdued)
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
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.callout)
                    .foregroundStyle(isFuture ? Theme.unlit : Theme.starlight)
                HStack(spacing: 2) {
                    ForEach(keptColors.prefix(5), id: \.self) { colorIndex in
                        Circle()
                            .fill(Theme.habitColor(colorIndex))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isToday {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.subdued, lineWidth: 1)
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(habits.filter { !$0.isArchived }) { habit in
                    let active = habit.isActive(on: day)
                    let kept = store.isKept(habit, on: day)
                    Button {
                        toggle(habit)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Theme.habitColor(habit.colorIndex))
                                .frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(habit.name)
                                    .font(.body)
                                    .foregroundStyle(active ? Theme.starlight : Theme.unlit)
                                if !active {
                                    Text("Didn't exist yet")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.unlit)
                                }
                            }
                            Spacer()
                            Image(systemName: kept ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(kept ? Theme.habitColor(habit.colorIndex) : Theme.unlit)
                        }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!active)
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
            .navigationTitle(day.date().formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
        }
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
