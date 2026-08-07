import SwiftUI
import SwiftData

/// Changing one habit: its name, its colour, and whether it's still tracked.
///
/// Reachable from the habit's own history and from the manage list, because
/// both are places you'd already be looking at the thing you want to change.
struct EditHabitSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let habit: Habit
    /// Called after the habit is removed, so a parent showing its history can
    /// close too rather than sit on something that no longer exists.
    var onRemoved: () -> Void = {}

    @State private var name = ""
    @State private var colorIndex = 0
    @State private var confirmingRemoval = false
    @State private var errorMessage: String?

    private var store: HabitStore { HabitStore(context: context) }
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// A habit with nothing recorded can go entirely; one with history can only
    /// stop, so the days it already accounts for stay true.
    private var canDelete: Bool { store.canDelete(habit) }

    var body: some View {
        AtlasPanel(
            title: "Edit habit",
            leading: .init(label: "Cancel") { dismiss() },
            trailing: .init(label: "Save", isProminent: true, isEnabled: !trimmedName.isEmpty, action: save)
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    field
                    palette
                    removal
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            name = habit.name
            colorIndex = habit.colorIndex
        }
        .atlasAlert("Couldn't save that", message: $errorMessage)
        .overlay {
            if confirmingRemoval {
                AtlasDialog(
                    title: canDelete ? "Delete \(habit.name)?" : "Stop tracking \(habit.name)?",
                    message: canDelete
                        ? "Nothing is recorded against it, so it goes completely. This can't be undone."
                        : "Its days stay counted and the stars they lit stay in the sky. You can start it again later.",
                    confirmLabel: canDelete ? "Delete" : "Stop",
                    isDestructive: true,
                    onConfirm: remove
                ) {
                    confirmingRemoval = false
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirmingRemoval)
    }

    /// A field ruled underneath rather than boxed — the line you write on in a
    /// logbook, not a control borrowed from a settings screen.
    private var field: some View {
        VStack(alignment: .leading, spacing: 10) {
            MarginLabel(text: "Name")
            TextField("", text: $name, prompt: Text("Work out for an hour")
                .foregroundStyle(Theme.unlit))
                .textFieldStyle(.plain)
                .font(.system(size: 19))
                .foregroundStyle(Theme.starlight)
                .tint(Theme.habitColor(colorIndex))
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.ruleStrong).frame(height: Theme.hairline)
                }
        }
    }

    /// Squares in a keyed row, as a chart legend sets its symbols — the
    /// selected one marked by a rule beneath rather than a ring around.
    private var palette: some View {
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
    }

    private var removal: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarginLabel(text: canDelete ? "Delete" : "Stop tracking")

            Text(canDelete
                 ? "Nothing has been recorded against this habit yet, so it can go completely."
                 : "Its days stay counted and the stars they lit stay in the sky. It just stops appearing.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                confirmingRemoval = true
            } label: {
                Text(canDelete ? "Delete habit" : "Stop tracking")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.94, green: 0.42, blue: 0.40))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay {
                        Rectangle()
                            .strokeBorder(Color(red: 0.94, green: 0.42, blue: 0.40).opacity(0.35),
                                          lineWidth: Theme.hairline)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        do {
            try store.rename(habit, to: trimmedName)
            try store.setColor(habit, to: colorIndex)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove() {
        do {
            if canDelete {
                try store.delete(habit)
            } else {
                try store.archive(habit)
            }
            dismiss()
            onRemoved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
