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
                HStack(spacing: 8) {
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
                .padding(.horizontal, 20)
            }
            .onAppear {
                // Land on today rather than at the far past end of the strip.
                proxy.scrollTo(today.rawValue, anchor: .trailing)
            }
            .onChange(of: today.rawValue) { _, newValue in
                // Midnight crossed while the app was open.
                proxy.scrollTo(newValue, anchor: .trailing)
            }
        }
    }
}

private struct DayChip: View {
    let day: DayKey
    let isSelected: Bool
    let isToday: Bool
    let keptColors: [Int]
    let action: () -> Void

    private var weekday: String {
        day.date().formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(weekday)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Theme.background.opacity(0.65) : Theme.subdued)

                Text("\(day.day)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? Theme.background : Theme.starlight)

                // Kept-habit dots, or a placeholder so chips don't change
                // height between days with and without history.
                HStack(spacing: 3) {
                    if keptColors.isEmpty {
                        Circle()
                            .fill(.clear)
                            .frame(width: 4, height: 4)
                    } else {
                        ForEach(Array(keptColors.prefix(5).enumerated()), id: \.offset) { _, index in
                            Circle()
                                .fill(Theme.habitColor(index))
                                .frame(width: 4, height: 4)
                                .opacity(isSelected ? 0.9 : 1)
                        }
                    }
                }
                .frame(height: 4)
            }
            .frame(width: 46)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Theme.starlight : Theme.surface)
                    .overlay {
                        // Today keeps a ring when you've navigated away from it,
                        // so there's always a way back to now.
                        if isToday && !isSelected {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.subdued.opacity(0.6), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.date().formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(
            keptColors.isEmpty ? "nothing kept" : "\(keptColors.count) kept"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
