import CoreText
import SwiftUI
import UIKit

/// Herden's Paper + Cobalt visual system. Warm neutral planes do the structural
/// work; cobalt identifies Herden and its primary controls, while rust, green,
/// and red are reserved for attention, success, and failure respectively.
enum Brand {
    static let background = adaptive(light: 0xFFFCF0, dark: 0x100F0F)
    static let elevated = adaptive(light: 0xF2F0E5, dark: 0x1C1B1A)
    static let card = adaptive(light: 0xFFFEF8, dark: 0x282726)
    static let pressed = adaptive(light: 0xE6E4D9, dark: 0x343331)
    static let ink = adaptive(light: 0x100F0F, dark: 0xF2F0E5)
    static let muted = adaptive(light: 0x575653, dark: 0xB7B5AC)
    static let subtle = adaptive(light: 0x6F6E69, dark: 0x878580)
    static let primary = adaptive(light: 0x205EA6, dark: 0x4385BE)
    static let attention = adaptive(light: 0xBC5215, dark: 0xDA702C)
    static let success = adaptive(light: 0x5E6F00, dark: 0x879A39)
    static let fault = adaptive(light: 0xAF3029, dark: 0xD65A50)
    static let hairline = adaptive(light: 0xCECDC3, dark: 0x403E3C)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(herdenHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: style.herdenBaseSize, relativeTo: style).weight(weight)
    }

    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: style.herdenBaseSize, relativeTo: style).weight(weight)
    }

    static func registerFonts(in bundle: Bundle = .main) {
        let urls = ["InstrumentSerif-Regular", "Inter-Regular"].compactMap {
            bundle.url(forResource: $0, withExtension: "ttf")
        }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
    }
}

private extension UIColor {
    convenience init(herdenHex: UInt32) {
        self.init(
            red: CGFloat((herdenHex >> 16) & 0xff) / 255,
            green: CGFloat((herdenHex >> 8) & 0xff) / 255,
            blue: CGFloat(herdenHex & 0xff) / 255,
            alpha: 1)
    }
}

private extension Font.TextStyle {
    var herdenBaseSize: CGFloat {
        switch self {
        case .largeTitle: 38
        case .title: 30
        case .title2: 24
        case .title3: 21
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

/// Live Tether: two endpoints joined by one persistent right-angle connection.
struct HerdenLogoMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("HerdenFold")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The active endpoint of Live Tether identifies one Agent.
struct HerdenAgentMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("HerdenAgentFold")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The origin endpoint of Live Tether identifies one Space.
struct HerdenSpaceMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image("HerdenSpaceFold")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
