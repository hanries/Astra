import SwiftUI

/// The parts a star atlas is assembled from.
///
/// Every element here has a counterpart in a real printed chart — a column
/// heading cut into the margin, a magnitude key, an epoch stamp, a ruled entry,
/// a measured scale. They're gathered in one file so the app speaks with one
/// voice, and so the grammar stays checkable against the documents it came
/// from rather than drifting into decoration.

// MARK: - Margin annotations

/// A column heading, letterspaced and uppercase, as engraved in a chart margin.
///
/// Takes a trailing figure when the heading counts something — real chart
/// legends nearly always do, and it saves a separate badge.
struct MarginLabel: View {
    let text: String
    var count: Int?

    var body: some View {
        HStack(spacing: 7) {
            Text(text.uppercased())
                .font(Theme.label())
                .kerning(1.3)
                .foregroundStyle(Theme.subdued)
            if let count {
                Text("\(count)")
                    .font(Theme.figure(10))
                    .foregroundStyle(Theme.unlit)
            }
            Rectangle()
                .fill(Theme.rule)
                .frame(height: Theme.hairline)
        }
    }
}

/// The provenance line a chart carries: catalogue, epoch, plate. Small, dry,
/// and true — it's the detail that tells you the thing was made from something.
struct ProvenanceStamp: View {
    let parts: [String]

    var body: some View {
        Text(parts.joined(separator: "  ·  "))
            .font(Theme.figure(9))
            .kerning(0.6)
            .foregroundStyle(Theme.unlit)
    }
}

// MARK: - Ruled entries

/// One line of a logbook: a keyed swatch, content, a figure, a mark.
///
/// Ruled rather than boxed. Rounded cards with a coloured rail down one edge is
/// among the most recognisable shapes in generated software; a ruled entry is
/// what an observation log actually looks like, and it stacks without the page
/// turning into a row of identical pills.
struct RuledEntry<Trailing: View>: View {
    let swatch: Color?
    let title: String
    var subtitle: String?
    var isSpent: Bool = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // A fixed key column, so swatches line up down the page the way
                // symbols do in a chart legend.
                Group {
                    if let swatch {
                        Rectangle()
                            .fill(swatch.opacity(isSpent ? 0.4 : 1))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isSpent ? Theme.subdued : Theme.starlight)
                        .strikethrough(isSpent, color: Theme.unlit)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.figure(11))
                            .foregroundStyle(Theme.unlit)
                    }
                }

                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 13)

            Rectangle()
                .fill(Theme.rule)
                .frame(height: Theme.hairline)
        }
    }
}

/// The mark against a logbook entry.
///
/// A drawn ring that fills rather than an SF Symbol checkmark, because the
/// symbol set is the same one every other app reaches for and this is the one
/// control the user touches every day.
struct EntryMark: View {
    let colour: Color
    let isMarked: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isMarked ? colour : Theme.ruleStrong, lineWidth: 1)
                .frame(width: 22, height: 22)
            if isMarked {
                Circle()
                    .fill(colour)
                    .frame(width: 22, height: 22)
                // A struck mark, drawn rather than set in a symbol font.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 5.2))
                    path.addLine(to: CGPoint(x: 3.6, y: 8.6))
                    path.addLine(to: CGPoint(x: 10, y: 0))
                }
                .stroke(Theme.background, style: .init(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 9)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isMarked)
    }
}

// MARK: - Scales

/// A measured scale, ticked like a chart axis.
///
/// The ticks aren't decoration: minor at every unit, major at the quarters, so
/// a glance reads position without a percentage having to be printed.
struct MeasuredScale: View {
    let fraction: Double
    let tint: Color
    var divisions: Int = 4

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            VStack(alignment: .leading, spacing: 0) {
                // The track, always visible, so an empty reading still shows
                // the full extent of what's being measured against.
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.rule)
                        .frame(height: 3)
                    Rectangle()
                        .fill(tint)
                        .frame(width: max(0, min(1, fraction)) * width, height: 3)
                }

                // Ticks hang below the track, majors at the ends and at each
                // whole division, so a glance reads position without a
                // percentage having to be printed anywhere.
                ZStack(alignment: .topLeading) {
                    ForEach(0...divisions, id: \.self) { index in
                        let isEnd = index == 0 || index == divisions
                        Rectangle()
                            .fill(isEnd ? Theme.ruleStrong : Theme.rule)
                            .frame(width: 1, height: isEnd ? 6 : 4)
                            // Inset the final tick by its own width so it isn't
                            // clipped off the trailing edge.
                            .offset(x: min(width - 1, width * Double(index) / Double(divisions)))
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(height: 9)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
    }
}

// MARK: - Panels

/// A panel that rises out of the page.
///
/// Replaces the system sheet's rounded card and grabber. Squared to a small
/// radius with a ruled header, because this app's surfaces are pages from an
/// atlas rather than cards in a stack.
struct AtlasPanel<Content: View>: View {
    let title: String
    var provenance: [String] = []
    var leading: PanelAction?
    var trailing: PanelAction?
    @ViewBuilder var content: Content

    struct PanelAction {
        let label: String
        var isProminent = false
        var isEnabled = true
        let action: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                actionButton(leading, alignment: .leading)
                Spacer(minLength: 12)
                VStack(spacing: 3) {
                    Text(title.uppercased())
                        .font(Theme.label(11))
                        .kerning(1.6)
                        .foregroundStyle(Theme.starlight)
                    if !provenance.isEmpty {
                        ProvenanceStamp(parts: provenance)
                    }
                }
                Spacer(minLength: 12)
                actionButton(trailing, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Theme.ruleStrong)
                .frame(height: Theme.hairline)

            content
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private func actionButton(_ action: PanelAction?, alignment: Alignment) -> some View {
        Group {
            if let action {
                Button(action: action.action) {
                    Text(action.label)
                        .font(.system(size: 15, weight: action.isProminent ? .medium : .regular))
                        .foregroundStyle(action.isEnabled ? Theme.starlight : Theme.unlit)
                }
                .disabled(!action.isEnabled)
            }
        }
        .frame(minWidth: 56, alignment: alignment)
    }
}

/// A short, squared confirmation drawn in the app's own grammar.
///
/// Replaces `alert` and `confirmationDialog`, whose rounded translucent cards
/// are unmistakably system furniture and pull the user out of the atlas.
struct AtlasDialog: View {
    let title: String
    let message: String
    var confirmLabel: String = "OK"
    var isDestructive = false
    var onConfirm: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.starlight)
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.subdued)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)

                Rectangle().fill(Theme.rule).frame(height: Theme.hairline)

                HStack(spacing: 0) {
                    if onConfirm != nil {
                        dialogButton("Cancel", tint: Theme.subdued, action: onDismiss)
                        Rectangle().fill(Theme.rule).frame(width: Theme.hairline)
                    }
                    dialogButton(
                        confirmLabel,
                        tint: isDestructive ? Color(red: 0.94, green: 0.42, blue: 0.40) : Theme.starlight
                    ) {
                        (onConfirm ?? onDismiss)()
                    }
                }
                .frame(height: 48)
            }
            .frame(maxWidth: 300)
            .background(Theme.surface)
            .overlay {
                Rectangle().strokeBorder(Theme.ruleStrong, lineWidth: Theme.hairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(32)
        }
    }

    private func dialogButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
    }
}
