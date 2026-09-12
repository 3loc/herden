import SwiftUI

/// The controls that belong to the terminal itself rather than to typing: go
/// back, resize the text, and — where the attached application can actually be
/// walked — step between messages. Identical in Agent and Space terminals, in
/// the same place on both, so neither screen grows chrome the other lacks.
///
/// This strip is the screen's only top chrome: both terminals hide the
/// navigation bar, so a screen showing this and a navigation bar would stack
/// two bars on one another. An Agent needs no name here — its status chrome
/// names it directly above the keyboard — so the name is shown only when a
/// screen has nowhere else to put it, inline beside Back rather than as a
/// centred title.
struct TerminalTopControls<Trailing: View>: View {
    let zoom: TerminalZoomSettings
    var backLabel = "Back"
    var name: String?
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    @Environment(\.appAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    static var height: CGFloat { 44 }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.ink)
            .background(Brand.card, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.hairline, lineWidth: 1)
            }
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier("terminal-back")

            if let name {
                Text(name)
                    .font(Brand.sans(.caption, weight: .semibold))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier("terminal-name")
            }

            Spacer(minLength: 0)

            if let appearance { appearanceToggle(appearance) }
            TerminalFontSizeControls(zoom: zoom)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
    }

    /// One tap, not a three-way picker: the glyph shows what the next tap
    /// gives you. Reading the effective `colorScheme` rather than the stored
    /// selection means the first tap out of System pins the opposite of what
    /// is actually on screen, which is what someone stepping into sunlight
    /// means by it.
    private func appearanceToggle(_ appearance: AppAppearanceSettings) -> some View {
        let isDark = colorScheme == .dark
        return Button {
            appearance.select(isDark ? .light : .dark)
        } label: {
            Image(systemName: isDark ? "sun.max" : "moon")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.ink)
        .background(Brand.card, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.hairline, lineWidth: 1)
        }
        .accessibilityLabel(isDark ? "Switch to Light Mode" : "Switch to Dark Mode")
        .accessibilityIdentifier("terminal-appearance-toggle")
    }
}

extension TerminalTopControls where Trailing == EmptyView {
    init(
        zoom: TerminalZoomSettings,
        backLabel: String = "Back",
        name: String? = nil,
        onBack: @escaping () -> Void
    ) {
        self.init(zoom: zoom, backLabel: backLabel, name: name, onBack: onBack) { EmptyView() }
    }
}

/// A trailing action in the terminal top strip, drawn like the other controls
/// there so an Agent's jump buttons and a Space's terminal actions read as one
/// row rather than as a toolbar bolted beside a strip.
struct TerminalTopAction: View {
    let systemImage: String
    let label: String
    var role: ButtonRole?
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Brand.fault : Brand.ink)
        .background(Brand.card, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.hairline, lineWidth: 1)
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}
