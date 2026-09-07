import CoreText
import SwiftUI

/// The original Founder Terminal / Fansvine visual system. Herden deliberately
/// keeps this fixed dark palette instead of inheriting iOS semantic fills.
enum Brand {
    static let background = Color(founderHex: 0x08080A)
    static let elevated = Color(founderHex: 0x0E0E12)
    static let card = Color(founderHex: 0x121218)
    static let ink = Color(founderHex: 0xF5F4F0)
    static let muted = Color(founderHex: 0xA8A6A0)
    static let subtle = Color(founderHex: 0x6B6A65)
    static let vine = Color(founderHex: 0xA8EC2A)
    static let vineLight = Color(founderHex: 0xCFF87A)
    static let vineDark = Color(founderHex: 0x8FD413)
    static let amber = Color(founderHex: 0xF0CE7A)
    static let fault = Color(founderHex: 0xEF4E4E)
    static let hairline = Color.white.opacity(0.08)

    static func display(_ style: Font.TextStyle) -> Font {
        .custom("InstrumentSerif-Regular", size: style.founderBaseSize, relativeTo: style)
    }

    static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: style.founderBaseSize, relativeTo: style).weight(weight)
    }

    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: style.founderBaseSize, relativeTo: style).weight(weight)
    }

    static func registerFonts(in bundle: Bundle = .main) {
        let urls = ["InstrumentSerif-Regular", "Inter-Regular"].compactMap {
            bundle.url(forResource: $0, withExtension: "ttf")
        }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
    }
}

private extension Color {
    init(founderHex: UInt32) {
        self.init(
            red: Double((founderHex >> 16) & 0xff) / 255,
            green: Double((founderHex >> 8) & 0xff) / 255,
            blue: Double(founderHex & 0xff) / 255)
    }
}

private extension Font.TextStyle {
    var founderBaseSize: CGFloat {
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

/// Herden's transparent pixel-art shepherd mark. Nearest-neighbour sampling
/// preserves the deliberately hard pixel edges at every rendered size.
struct HerdenMark: View {
    var size: CGFloat = 32

    var body: some View {
        Image("HerdenMuddyBoot")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
