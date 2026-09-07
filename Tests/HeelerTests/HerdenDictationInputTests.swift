import Foundation
import Testing

@testable import Heeler

@Suite("Herden terminal dictation")
struct HerdenDictationInputTests {
    @Test func streamsLowercaseCorrectionsWithoutSubmitting() {
        var input = HerdenDictationInputState()
        let locale = Locale(identifier: "en_US")

        input.begin()
        #expect(String(decoding: input.apply("Codex", locale: locale), as: UTF8.self) == "codex")
        #expect(String(decoding: input.apply("Codex Model", locale: locale), as: UTF8.self) == " model")
        #expect(String(decoding: input.apply("Codex Mode", locale: locale), as: UTF8.self) == "\u{7f}")
        input.end()
        #expect(input.apply("ignored", locale: locale).isEmpty)
    }

    @Test func stripsEveryLineBreakBeforeBytesReachTheTTY() {
        var input = HerdenDictationInputState()
        input.begin()

        let bytes = input.apply("first\nsecond\r\nthird\u{2028}fourth", locale: Locale(identifier: "en_US"))

        #expect(!bytes.contains(0x0A))
        #expect(!bytes.contains(0x0D))
        #expect(String(decoding: bytes, as: UTF8.self) == "first second third fourth")
    }
}
