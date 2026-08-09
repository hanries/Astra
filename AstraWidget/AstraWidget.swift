import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

@main
struct AstraWidgetBundle: WidgetBundle {
    var body: some Widget {
        AstraWidget()
    }
}

struct AstraWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AstraWidget", provider: DayProvider()) { entry in
            AstraWidgetView(entry: entry)
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Mark today's habits, and see the star waiting.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    let date: Date
    let habits: [HabitSnapshot]
    let unlock: AstraStore.Unlock?

    var keptCount: Int { habits.count { $0.isKept } }

    static let empty = DayEntry(date: .now, habits: [], unlock: nil)

    static let placeholder = DayEntry(
        date: .now,
        habits: [
            HabitSnapshot(id: UUID(), name: "Work out for an hour", colorIndex: 0, isKept: true),
            HabitSnapshot(id: UUID(), name: "Read before bed", colorIndex: 1, isKept: false),
        ],
        unlock: AstraStore.Unlock(star: "Beta CMi", figure: "Canis Minor", lit: 1, total: 2)
    )
}

/// A habit flattened for display.
///
/// The timeline holds plain values rather than SwiftData objects: entries are
/// archived and handed back to the widget process later, and a live model
/// object doesn't survive that trip.
struct HabitSnapshot: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let isKept: Bool
}

/// `@MainActor` on the whole provider rather than on `read` alone.
///
/// `ModelContext` and the store are main-actor bound, and the protocol's
/// callbacks are not, so isolating only the reader leaves both entry points
/// unable to call it.
@MainActor
struct DayProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> DayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        // One entry, refreshed at midnight. The day's marks are the only thing
        // that changes, and those reload the widget directly when tapped, so
        // there's nothing to interpolate between now and tomorrow.
        let midnight = Calendar.current.nextDate(
            after: .now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3600)

        completion(Timeline(entries: [read()], policy: .after(midnight)))
    }

    private func read() -> DayEntry {
        // Before the app's first launch there is nothing to show, and opening
        // the container here would create an empty store in the group ahead of
        // the app's migration.
        guard AstraStore.storeExists else { return .empty }

        let context = ModelContext(AstraStore.container)
        let store = HabitStore(context: context)
        let today = store.today()

        let habits = ((try? store.allHabits()) ?? [])
            .filter { $0.isActive(on: today) }
            .map {
                HabitSnapshot(
                    id: $0.id,
                    name: $0.name,
                    colorIndex: $0.colorIndex,
                    isKept: store.isKept($0, on: today)
                )
            }

        // Counted here rather than taken from the app's last write, so a star
        // this widget lit itself moves the name along.
        let lit = (try? context.fetchCount(FetchDescriptor<Award>())) ?? 0

        return DayEntry(
            date: .now,
            habits: habits,
            unlock: AstraStore.unlock(forAwardCount: lit)
        )
    }
}

// MARK: - Views

struct AstraWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallWidget(entry: entry)
        default:           MediumWidget(entry: entry)
        }
    }
}

/// Glanceable only. At 158pt across there isn't room for a 44pt mark beside a
/// legible name, and a mis-tap here would cost a real entry.
struct SmallWidget: View {
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel("Today")
                Spacer()
                WidgetLabel(entry.date.formatted(.dateTime.day().month(.abbreviated)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(entry.keptCount)")
                    .font(.system(size: 34, weight: .light, design: .monospaced))
                    .foregroundStyle(Theme.starlight)
                Text("/\(entry.habits.count)")
                    .font(.system(size: 15, weight: .light, design: .monospaced))
                    .foregroundStyle(Theme.unlit)
            }
            .padding(.top, 8)

            WidgetScale(
                fraction: fraction,
                tint: entry.keptCount == entry.habits.count && !entry.habits.isEmpty
                    ? Theme.starlight
                    : Theme.habitColor(entry.habits.first { !$0.isKept }?.colorIndex ?? 0),
                divisions: max(2, entry.habits.count)
            )
            .padding(.top, 7)

            Spacer(minLength: 6)

            if let unlock = entry.unlock {
                HStack(spacing: 6) {
                    StarGlint()
                    VStack(alignment: .leading, spacing: 1) {
                        WidgetLabel("Waiting")
                        Text(unlock.star)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.starlight)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var fraction: Double {
        guard !entry.habits.isEmpty else { return 0 }
        return Double(entry.keptCount) / Double(entry.habits.count)
    }
}

/// The working size: one tap per habit, logged without opening the app.
struct MediumWidget: View {
    let entry: DayEntry

    /// Three fit at a size that stays tappable. Squeezing five in would shrink
    /// every mark, including on the days there's only one thing left to do.
    private static let visibleLimit = 3

    private var shown: [HabitSnapshot] { Array(entry.habits.prefix(Self.visibleLimit)) }
    private var overflow: Int { max(0, entry.habits.count - Self.visibleLimit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel("Today · \(entry.date.formatted(.dateTime.day().month(.abbreviated)))")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(entry.keptCount)")
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.starlight)
                    Text("/\(entry.habits.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.unlit)
                }
            }
            .padding(.bottom, 7)

            Hairline()

            if entry.habits.isEmpty {
                Spacer()
                Text("No habits yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.unlit)
                Spacer()
            } else {
                ForEach(shown) { habit in
                    WidgetEntry(habit: habit)
                    Hairline()
                }
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.unlit)
                        .padding(.top, 6)
                }
                Spacer(minLength: 4)
            }

            if let unlock = entry.unlock {
                HStack {
                    HStack(spacing: 5) {
                        StarGlint()
                        WidgetLabel("\(unlock.star) waiting")
                    }
                    Spacer()
                    WidgetLabel("\(unlock.figure) \(unlock.lit)/\(unlock.total)")
                }
            }
        }
    }
}

/// One ruled entry with a live mark.
private struct WidgetEntry: View {
    let habit: HabitSnapshot

    private var tint: Color { Theme.habitColor(habit.colorIndex) }

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(tint.opacity(habit.isKept ? 0.45 : 1))
                .frame(width: 6, height: 6)

            Text(habit.name)
                .font(.system(size: 12))
                .foregroundStyle(habit.isKept ? Theme.subdued : Theme.starlight)
                .strikethrough(habit.isKept, color: Theme.unlit)
                .lineLimit(1)

            Spacer(minLength: 6)

            Button(intent: MarkHabitIntent(habitID: habit.id)) {
                ZStack {
                    Circle()
                        .strokeBorder(habit.isKept ? tint : Theme.ruleStrong, lineWidth: 1)
                        .frame(width: 19, height: 19)
                    if habit.isKept {
                        Circle().fill(tint).frame(width: 19, height: 19)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 4.4))
                            path.addLine(to: CGPoint(x: 3, y: 7.3))
                            path.addLine(to: CGPoint(x: 8.5, y: 0))
                        }
                        .stroke(Theme.background,
                                style: .init(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 8.5, height: 7.5)
                    }
                }
                // Hit area well beyond the drawn ring: a widget gets one tap
                // and no second chance to explain itself.
                .frame(width: 38, height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.name), \(habit.isKept ? "kept" : "not kept")")
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Grammar

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: 0.5)
    }
}

private struct WidgetLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .medium))
            .kerning(1.1)
            .foregroundStyle(Theme.subdued)
            .lineLimit(1)
    }
}

private struct StarGlint: View {
    var body: some View {
        Circle()
            .fill(Color(red: 0.62, green: 0.72, blue: 0.91))
            .frame(width: 6, height: 6)
            .shadow(color: Color(red: 0.62, green: 0.72, blue: 0.91).opacity(0.8), radius: 3)
    }
}

/// The measured scale, cut down for widget sizes.
private struct WidgetScale: View {
    let fraction: Double
    let tint: Color
    let divisions: Int

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 1) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.rule).frame(height: 3)
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(0, min(1, fraction)) * geometry.size.width, height: 3)
                }
                ZStack(alignment: .topLeading) {
                    ForEach(0...divisions, id: \.self) { index in
                        let isEnd = index == 0 || index == divisions
                        Rectangle()
                            .fill(isEnd ? Theme.ruleStrong : Theme.rule)
                            .frame(width: 1, height: isEnd ? 5 : 3)
                            .offset(x: min(geometry.size.width - 1,
                                           geometry.size.width * Double(index) / Double(divisions)))
                    }
                }
                .frame(height: 5)
            }
        }
        .frame(height: 9)
    }
}
