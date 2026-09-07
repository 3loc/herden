import CoreText
import SwiftUI

/// Herden's fixed dark visual system. It does not inherit iOS semantic fills.
enum Brand {
    static let background = Color(herdenHex: 0x08080A)
    static let elevated = Color(herdenHex: 0x0E0E12)
    static let card = Color(herdenHex: 0x121218)
    static let ink = Color(herdenHex: 0xF5F4F0)
    static let muted = Color(herdenHex: 0xA8A6A0)
    static let subtle = Color(herdenHex: 0x6B6A65)
    static let vine = Color(herdenHex: 0xA8EC2A)
    static let vineLight = Color(herdenHex: 0xCFF87A)
    static let vineDark = Color(herdenHex: 0x8FD413)
    static let amber = Color(herdenHex: 0xF0CE7A)
    static let fault = Color(herdenHex: 0xEF4E4E)
    static let hairline = Color.white.opacity(0.08)

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

private extension Color {
    init(herdenHex: UInt32) {
        self.init(
            red: Double((herdenHex >> 16) & 0xff) / 255,
            green: Double((herdenHex >> 8) & 0xff) / 255,
            blue: Double(herdenHex & 0xff) / 255)
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

/// A Space is the field itself. Keeping this separate from `HerdenMark`
/// prevents the sheep/Agent metaphor from leaking onto Workspace rows.
struct HerdenSpaceMark: View {
    var size: CGFloat = 40

    var body: some View {
        Image("HerdenField")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
