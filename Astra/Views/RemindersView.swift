import SwiftUI

/// Reminder settings: on or off, and when.
///
/// Two controls and a line showing exactly what will arrive. Showing the actual
/// text is worth the space — a reminder is the app speaking without being
/// opened, and nobody should have to switch it on to find out what it says.
struct RemindersView: View {
    @Environment(\.dismiss) private var dismiss

    /// The star the next reminder would name, so the preview is the real thing.
    let nextStarName: String?
    let isTodayComplete: Bool

    @State private var isEnabled = false
    @State private var minutes = ReminderService.defaultMinutes
    @State private var isDenied = false

    private var reminders: ReminderService { .shared }

    private var timeLabel: String {
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        AtlasPanel(
            title: "Reminders",
            trailing: .init(label: "Done", isProminent: true) { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    toggleRow
                    if isEnabled && !isDenied {
                        timeSection
                        previewSection
                    }
                    if isDenied { deniedNote }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
        }
        .task {
            isEnabled = reminders.isEnabled
            minutes = reminders.minutesAfterMidnight
            let status = await reminders.authorizationStatus()
            isDenied = status == .denied
            if isDenied { isEnabled = false }
        }
    }

    // MARK: - Rows

    private var toggleRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarginLabel(text: "Daily reminder")
                .padding(.bottom, 6)
            HStack {
                Text("One a day")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.starlight)
                Spacer()
                AtlasSwitch(isOn: $isEnabled)
            }
            .padding(.vertical, 13)
            Rectangle().fill(Theme.rule).frame(height: Theme.hairline)
        }
        .onChange(of: isEnabled) { _, wanted in
            Task { await apply(enabled: wanted) }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MarginLabel(text: "At")

            // The system wheel, because a hand-built time picker would be worse
            // at the one job it has, and picking a time is not where this app's
            // character needs to show.
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            from: DateComponents(hour: minutes / 60, minute: minutes % 60)
                        ) ?? .now
                    },
                    set: { picked in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                        minutes = (parts.hour ?? 20) * 60 + (parts.minute ?? 0)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            // No colour tricks. The app runs in dark mode, so the wheel already
            // draws light text; inverting it turned the digits black on black
            // and left the picker all but invisible.
            .frame(maxWidth: .infinity)
            .onChange(of: minutes) { _, newValue in
                reminders.minutesAfterMidnight = newValue
                Task { await reschedule() }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarginLabel(text: "What arrives")
            VStack(alignment: .leading, spacing: 5) {
                Text("Astra")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.starlight)
                Text(ReminderService.message(nextStarName: nextStarName))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.subdued)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay {
                Rectangle().strokeBorder(Theme.rule, lineWidth: Theme.hairline)
            }

            Text("Nothing arrives at \(timeLabel) on a day you've already finished.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.unlit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deniedNote: some View {
        Text("Notifications are switched off for Astra in Settings. Turn them on there and this will work.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.subdued)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func apply(enabled: Bool) async {
        guard enabled else {
            reminders.isEnabled = false
            reminders.cancelAll()
            return
        }
        let status = await reminders.authorizationStatus()
        if status == .notDetermined {
            let granted = await reminders.requestAuthorization()
            if !granted {
                isEnabled = false
                isDenied = await reminders.authorizationStatus() == .denied
                return
            }
        } else if status == .denied {
            isEnabled = false
            isDenied = true
            return
        }
        reminders.isEnabled = true
        await reschedule()
    }

    private func reschedule() async {
        await reminders.refresh(nextStarName: nextStarName, isTodayComplete: isTodayComplete)
    }
}

/// A switch drawn in the app's grammar.
///
/// The system toggle is a green pill that appears in every iOS settings screen
/// ever shipped, and it drags the whole page back to stock the moment it lands.
struct AtlasSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? Theme.starlight.opacity(0.9) : Theme.surface)
                    .overlay {
                        Rectangle().strokeBorder(
                            isOn ? Theme.starlight : Theme.ruleStrong,
                            lineWidth: Theme.hairline
                        )
                    }
                    .frame(width: 46, height: 26)
                Rectangle()
                    .fill(isOn ? Theme.background : Theme.subdued)
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 4)
            }
            .frame(width: 46, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
