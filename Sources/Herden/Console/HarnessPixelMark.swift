import SwiftUI

/// Small, original pixel-letter marks for Space and Agent rows. These are
/// identifiers, not reproductions of third-party logos. The word label beside
/// each mark remains the authoritative Agent or shell identification.
struct HarnessPixelMark: View {
    enum Subject {
        case agent(String)
        case terminal(TerminalShellKind?)
        case agents(Int)
    }

    let subject: Subject
    var size: CGFloat = 42

    private var style: (letters: String, fill: UInt32, name: String) {
        switch subject {
        case .agent(let kind):
            guard let supported = SupportedAgentKind(rawValue: kind) else {
                return ("?", 0x205EA6, kind)
            }
            return (supported.pixelLetters, supported.brandAccent, supported.displayName)
        case .terminal(let shell?):
            return (shell.pixelLetter, 0x273544, "\(shell.displayName) terminal")
        case .terminal(nil):
            return (">", 0x273544, "Terminal")
        case .agents(let count):
            return ("A", 0x205EA6, "\(count) Agents")
        }
    }

    var body: some View {
        let mark = style
        let background = Color(pixelHex: mark.fill)
        let foreground = Self.usesDarkInk(on: mark.fill) ? Color(pixelHex: 0x100F0F) : .white
        Canvas { context, dimensions in
            let letters = Array(mark.letters)
            let cell = floor(min(dimensions.width, dimensions.height)
                / (letters.count == 1 ? 7 : 9))
            let glyphWidth = letters.count == 1 ? 3 : 7
            let originX = floor((dimensions.width - CGFloat(glyphWidth) * cell) / 2)
            let originY = floor((dimensions.height - 5 * cell) / 2)
            for (letterIndex, letter) in letters.enumerated() {
                let rows = Self.glyphs[letter] ?? Self.glyphs["?"] ?? []
                for (rowIndex, row) in rows.enumerated() {
                    for (columnIndex, pixel) in row.enumerated() where pixel == "#" {
                        let x = originX + CGFloat(letterIndex * 4 + columnIndex) * cell
                        let y = originY + CGFloat(rowIndex) * cell
                        context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                     with: .color(foreground))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.hairline, lineWidth: 1))
        .accessibilityLabel(mark.name)
    }

    private static func usesDarkInk(on rgb: UInt32) -> Bool {
        let r = Double((rgb >> 16) & 0xff) / 255
        let g = Double((rgb >> 8) & 0xff) / 255
        let b = Double(rgb & 0xff) / 255
        let luminance = [r, g, b].map { value in
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * luminance[0] + 0.7152 * luminance[1] + 0.0722 * luminance[2] > 0.18
    }

    /// Three by five cells; drawn at integral coordinates for crisp edges.
    private static let glyphs: [Character: [String]] = [
        "A": [".#.", "#.#", "###", "#.#", "#.#"],
        "B": ["##.", "#.#", "##.", "#.#", "##."],
        "C": [".##", "#..", "#..", "#..", ".##"],
        "D": ["##.", "#.#", "#.#", "#.#", "##."],
        "E": ["###", "#..", "##.", "#..", "###"],
        "F": ["###", "#..", "##.", "#..", "#.."],
        "G": [".##", "#..", "#.#", "#.#", ".##"],
        "H": ["#.#", "#.#", "###", "#.#", "#.#"],
        "I": ["###", ".#.", ".#.", ".#.", "###"],
        "K": ["#.#", "##.", "#..", "##.", "#.#"],
        "L": ["#..", "#..", "#..", "#..", "###"],
        "M": ["#.#", "###", "###", "#.#", "#.#"],
        "O": ["###", "#.#", "#.#", "#.#", "###"],
        "P": ["##.", "#.#", "##.", "#..", "#.."],
        "Q": ["###", "#.#", "#.#", "###", "..#"],
        "R": ["##.", "#.#", "##.", "##.", "#.#"],
        "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
        "Z": ["###", "..#", ".#.", "#..", "###"],
        "x": ["...", "#.#", ".#.", "#.#", "..."],
        ">": ["#..", ".#.", "..#", ".#.", "#.."],
        "?": ["###", "..#", ".#.", "...", ".#."],
    ]
}

private extension Color {
    init(pixelHex rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255)
    }
}

extension TerminalShellKind {
    var pixelLetter: String {
        switch self {
        case .zsh: "Z"
        case .bash: "B"
        case .fish: "F"
        }
    }
}

extension SupportedAgentKind {
    var pixelLetters: String {
        switch self {
        case .codex: "Cx"
        default: String(displayName.prefix(1)).uppercased()
        }
    }

    /// Recognizable accent hues from each harness's own public presentation.
    /// Monochrome projects use a neutral ink tile. These colours identify the
    /// kind; no vendor logo shapes or lockups are copied into Herden.
    var brandAccent: UInt32 {
        switch self {
        case .pi: 0x111111
        case .claude: 0xD97757
        case .codex: 0x202020
        case .gemini: 0x4285F4
        case .cursor: 0x202020
        case .devin: 0x2866BB
        case .antigravity: 0x4285F4
        case .cline: 0xE16A64
        case .omp: 0x4E62C8
        case .mastracode: 0xE45454
        case .opencode: 0x202020
        case .copilot: 0x8534F3
        case .kimi: 0x2864B4
        case .kiro: 0x7244BE
        case .droid: 0xE56A3B
        case .amp: 0x9555D7
        case .grok: 0x202020
        case .hermes: 0xB26539
        case .kilo: 0x5055D4
        case .qodercli: 0x5A48CB
        case .qwen: 0x7B4FC2
        case .letta: 0xE6B340
        case .maki: 0xC54676
        case .muse: 0x7360C7
        }
    }
}
