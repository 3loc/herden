import CoreText
import SwiftUI
import UIKit

/// Herden's day/night visual system. The daylight half keeps the field-green
/// identity while using near-white planes and dark ink for outdoor contrast;
/// the night half preserves the original black-and-vine palette.
enum Brand {
    static let background = adaptive(light: 0xF8FAF4, dark: 0x08080A)
    static let elevated = adaptive(light: 0xEEF2E8, dark: 0x0E0E12)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x121218)
    static let ink = adaptive(light: 0x14180F, dark: 0xF5F4F0)
    static let muted = adaptive(light: 0x47503D, dark: 0xA8A6A0)
    static let subtle = adaptive(light: 0x626B58, dark: 0x6B6A65)
    static let vine = adaptive(light: 0x416D00, dark: 0xA8EC2A)
    static let vineLight = adaptive(light: 0x6E9C1B, dark: 0xCFF87A)
    static let vineDark = adaptive(light: 0x315600, dark: 0x8FD413)
    static let amber = adaptive(light: 0x795100, dark: 0xF0CE7A)
    static let uploadOrange = adaptive(light: 0xA84500, dark: 0xFF9F43)
    static let fault = adaptive(light: 0xB4232C, dark: 0xEF4E4E)
    static let hairline = adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.10)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(herdenHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func display(_ style: Font.TextStyle) -> Font {
        .custom("InstrumentSerif-Regular", size: style.herdenBaseSize, relativeTo: style)
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

/// Herden's paired Fold: two fields turning around one shared passage.
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

/// The active half of the Fold identifies one Agent.
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

/// The enclosing half of the Fold identifies one Space.
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
