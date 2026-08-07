import SwiftUI
import SwiftData

/// One habit's whole record: what it has cost so far, and every day of it.
///
/// Reachable by tapping a habit card, which is why the card's checkmark is its
/// own target — the daily action and the retrospective are different intents
/// and shouldn't share a tap.
struct HabitHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let habit: Habit

    @State private var month: DayKey = .today()
    @State private var errorMessage: String?
    @State private var isEditing = false

    private var store: HabitStore { HabitStore(context: context) }
    private var today: DayKey { store.today() }
    private var keptDays: Set<DayKey> { store.keptDays(for: habit) }
    private var tint: Color { Theme.habitColor(habit.colorIndex) }

    var body: some View {
        AtlasPanel(
            title: habit.name,
            provenance: ["since \(habit.createdOn.date().formatted(.dateTime.month(.abbreviated).year()))"],
            leading: .init(label: "Edit") { isEditing = true },
            trailing: .init(label: "Done", isProminent: true) { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    statRow
                    monthSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 32)
            }
        }
        .atlasSheet(isPresented: $isEditing) {
            // Removing the habit from here leaves this screen showing
            // something that no longer exists, so it closes too.
            EditHabitSheet(habit: habit) { dismiss() }
        }
        .atlasAlert("Couldn't save that", message: $errorMessage)
    }

    // MARK: - Stats

    /// Three readings in a row, ruled off rather than boxed, with the figures
    /// on a shared baseline so they read as one line of a table.
    private var statRow: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                stat(value: "\(Stats.totalKept(keptDays: keptDays))", label: "days kept")
                divider
                stat(value: consistencyText, label: "last 30")
                divider
                stat(value: "\(Stats.longestRun(keptDays: keptDays))", label: "longest run")
            }
            .padding(.vertical, 16)
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
        }
    }

    private var consistencyText: String {
        let value = Stats.consistency(
            keptDays: keptDays,
            window: 30,
            endingOn: today,
            startingNoEarlierThan: habit.createdOn
        ) ?? 0
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(Theme.figure(24, weight: .light))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(Theme.label(9))
                .kerning(1.1)
                .foregroundStyle(Theme.unlit)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(width: Theme.hairline, height: 34)
    }

    // MARK: - Month

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text(month.date().formatted(.dateTime.month(.wide).year()).uppercased())
                    .font(Theme.label(11))
                    .kerning(1.5)
                    .foregroundStyle(Theme.starlight)
                Rectangle()
                    .fill(Theme.rule)
                    .frame(height: Theme.hairline)
                // Paging set as marks on the rule rather than as chevrons,
                // which are the same glyph every app uses.
                HStack(spacing: 14) {
                    monthStep("−", enabled: true) { shiftMonth(by: -1) }
                    monthStep("+", enabled: canGoForward) { shiftMonth(by: 1) }
                }
            }

            HabitMonthGrid(
                month: month,
                today: today,
                keptDays: keptDays,
                tint: tint,
                isActive: { habit.isActive(on: $0) }
            ) { day in
                toggle(day)
            }

            HStack(spacing: 14) {
                key(filled: true, text: "kept")
                key(filled: false, text: "not kept")
                Spacer()
                Text("TAP TO CORRECT")
                    .font(Theme.label(9))
                    .kerning(1.1)
                    .foregroundStyle(Theme.unlit)
            }
            .padding(.top, 2)
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

    /// The legend a chart carries, so the marks below don't have to be guessed.
    private func key(filled: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(filled ? tint : .clear)
                .stroke(filled ? .clear : Theme.unlit, lineWidth: Theme.hairline)
                .frame(width: 8, height: 8)
            Text(text.uppercased())
                .font(Theme.label(9))
                .kerning(1.1)
                .foregroundStyle(Theme.unlit)
        }
    }

    private var canGoForward: Bool {
        month.year < today.year || (month.year == today.year && month.month < today.month)
    }

    private func shiftMonth(by months: Int) {
        let anchor = DayKey(rawValue: month.year * 10_000 + month.month * 100 + 15)
        let moved = Calendar.current.date(byAdding: .month, value: months, to: anchor.date())
        month = DayKey(moved ?? anchor.date())
    }

    private func toggle(_ day: DayKey) {
        do {
            try store.toggle(habit, on: day)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A month of one habit, as filled and hollow rings.
///
/// A ring rather than a block because a hollow ring reads as "a day that
/// existed and wasn't kept" while an empty square reads as nothing at all —
/// and the point of looking back is to see the shape of the whole thing,
/// misses included.
private struct HabitMonthGrid: View {
    let month: DayKey
    let today: DayKey
    let keptDays: Set<DayKey>
    let tint: Color
    let isActive: (DayKey) -> Bool
    let onSelect: (DayKey) -> Void

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

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
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: DayKey) -> some View {
        let kept = keptDays.contains(day)
        let selectable = isActive(day) && day <= today
        let isToday = day == today

        return Button {
            if selectable { onSelect(day) }
        } label: {
            ZStack {
                Circle()
                    .fill(kept ? tint : .clear)
                Circle()
                    .stroke(
                        kept ? .clear : (selectable ? Theme.unlit : Theme.unlit.opacity(0.35)),
                        lineWidth: 1
                    )
                if isToday && !kept {
                    Circle().stroke(tint.opacity(0.8), lineWidth: 1.5)
                }
                Text("\(day.day)")
                    .font(Theme.figure(12))
                    .foregroundStyle(
                        kept ? Theme.background
                            : (selectable ? Theme.starlight.opacity(0.75) : Theme.unlit)
                    )
            }
            .frame(height: 38)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityLabel(day.date().formatted(.dateTime.month().day()))
        .accessibilityValue(kept ? "kept" : "not kept")
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
