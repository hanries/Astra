import SwiftUI

/// The horizontal day selector at the top of the home screen.
///
/// Turns the home screen from "today" into "a day", which is what makes
/// correcting a missed evening a first-class action rather than something you
/// have to go and find in another tab.
///
/// Each day carries dots for the habits kept on it, so a fortnight of history
/// is legible without tapping anything — and the gaps are visible without a
/// number attached to them.
struct WeekStrip: View {
    let today: DayKey
    /// How far back the strip scrolls. Two weeks is enough to fix a forgotten
    /// evening without turning the home screen into an archive.
    var daysBack: Int = 27
    @Binding var selection: DayKey
    /// Habit colour indexes kept on a given day.
    let keptColors: (DayKey) -> [Int]

    private var days: [DayKey] {
        today.advanced(by: -daysBack).through(today)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.rawValue) { day in
                        DayChip(
                            day: day,
                            isSelected: day == selection,
                            isToday: day == today,
                            keptColors: keptColors(day)
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selection = day
                            }
                        }
                        .id(day.rawValue)
                    }
                }
                // Leading margin only; the trailing gap comes from the spacer
                // below so today's division can sit clear of the screen edge
                // when the scale scrolls to its end.
                .padding(.leading, 20)
                .padding(.trailing, 12)
                // The axis the ticks stand on, running the full length of the
                // scale rather than stopping at the last division.
                .background(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(height: Theme.hairline)
                }
            }
            .onAppear {
                // Land on today rather than at the far past end of the strip.
                // Centre-trailing rather than hard trailing, or the final
                // division sits half off the screen.
                proxy.scrollTo(today.rawValue, anchor: UnitPoint(x: 0.9, y: 0.5))
            }
            .onChange(of: today.rawValue) { _, newValue in
                // Midnight crossed while the app was open.
                proxy.scrollTo(newValue, anchor: UnitPoint(x: 0.9, y: 0.5))
            }
        }
    }
}

/// One division of the scale.
///
/// A ticked axis rather than a row of rounded chips: the day sits above its own
/// tick, kept habits register as marks beneath it, and the selected division is
/// picked out by a rule rather than by a filled pill. A chart marks a position;
/// it doesn't put it in a button.
private struct DayChip: View {
    let day: DayKey
    let isSelected: Bool
    let isToday: Bool
    let keptColors: [Int]
    let action: () -> Void

    private var weekday: String {
        day.date().formatted(.dateTime.weekday(.narrow))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(weekday.uppercased())
                    .font(Theme.label(9))
                    .kerning(0.8)
                    .foregroundStyle(isSelected ? Theme.starlight : Theme.unlit)

                Text("\(day.day)")
                    .font(Theme.figure(16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.starlight : Theme.subdued)

                // Marks for what was kept, held at a fixed height so divisions
                // stay evenly spaced whether or not a day has history.
                HStack(spacing: 2.5) {
                    ForEach(Array(keptColors.prefix(5).enumerated()), id: \.offset) { _, index in
                        Rectangle()
                            .fill(Theme.habitColor(index))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)

                // The tick. Selected day gets a full-height major tick; today
                // keeps a shorter one so there's always a way back to now.
                Rectangle()
                    .fill(isSelected ? Theme.starlight : (isToday ? Theme.subdued : Theme.rule))
                    .frame(width: isSelected ? 1.5 : Theme.hairline, height: isSelected ? 9 : (isToday ? 6 : 3))
                    .frame(height: 9, alignment: .top)
            }
            .frame(width: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date().formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(
            keptColors.isEmpty ? "nothing kept" : "\(keptColors.count) kept"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
