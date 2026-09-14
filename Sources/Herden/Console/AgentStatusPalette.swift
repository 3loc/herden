import UIKit

extension AgentStatus {
    /// The one status palette in the app, in two roles: `tintUIColor` is the
    /// wash (low-opacity capsule fills), `inkUIColor` the foreground (badge
    /// text, the switcher's dot). Both read from the same palette, so a
    /// colour never means two things.
    var tintUIColor: UIColor {
        switch self {
        case .blocked: AgentStatusPalette.attention
        case .done: AgentStatusPalette.success
        case .working: AgentStatusPalette.working
        // Idle, Unknown, and anything this build cannot read: not asking for
        // the user, so it stays out of the way.
        default: AgentStatusPalette.muted
        }
    }

    /// The legible end of each status colour, for text and small solid
    /// indicators. Same hue as the wash; see `AgentStatusPalette` for why
    /// Latte cannot use the wash directly.
    var inkUIColor: UIColor {
        switch self {
        case .blocked: AgentStatusPalette.attentionInk
        case .done: AgentStatusPalette.successInk
        case .working: AgentStatusPalette.workingInk
        default: AgentStatusPalette.mutedInk
        }
    }
}

/// Agent states expressed in the shared Paper + Cobalt product language.
/// Working is the active cobalt, Blocked is the rust attention colour, Done is
/// success green, and everything unreadable or idle remains neutral.
enum AgentStatusPalette {
    static let attention = adaptive(dark: 0xDA702C, light: 0xBC5215)
    static let success = adaptive(dark: 0x879A39, light: 0x5E6F00)
    static let working = adaptive(dark: 0x4385BE, light: 0x205EA6)
    static let muted = adaptive(dark: 0xB7B5AC, light: 0x575653)

    /// Foreground counterparts are adjusted within the same hue family so
    /// caption text clears 4.5:1 over each 15% wash on the raised surface.
    static let attentionInk = adaptive(dark: 0xEC8B49, light: 0xA5470F)
    static let successInk = adaptive(dark: 0xA0AF54, light: 0x5E6F00)
    static let workingInk = adaptive(dark: 0x6CA6D9, light: 0x205EA6)
    static let mutedInk = adaptive(dark: 0xB7B5AC, light: 0x575653)

    private static func adaptive(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

extension UIColor {
    fileprivate convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
