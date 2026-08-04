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
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                field
                palette
                Spacer()
                removal
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .background(Theme.background)
            .navigationTitle("Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                name = habit.name
                colorIndex = habit.colorIndex
            }
        }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.subdued)
            TextField("Habit name", text: $name)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(Theme.starlight)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.done)
                .onSubmit(save)
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colour")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.subdued)
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
        }
    }

    @ViewBuilder
    private var removal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                Label(
                    canDelete ? "Delete habit" : "Stop tracking",
                    systemImage: canDelete ? "trash" : "pause.circle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            .tint(.red)

            Text(canDelete
                 ? "Nothing has been recorded against this habit yet, so it can go completely."
                 : "Its days stay counted and the stars they lit stay in the sky. It just stops appearing.")
                .font(.caption)
                .foregroundStyle(Theme.subdued)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            canDelete ? "Delete \(habit.name)?" : "Stop tracking \(habit.name)?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(canDelete ? "Delete" : "Stop tracking", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(canDelete
                 ? "This can't be undone."
                 : "You can start it again later from Manage habits.")
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
