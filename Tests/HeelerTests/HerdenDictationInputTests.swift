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

    @Test func preservesCommittedTextWhenLongRecognitionWindowRollsForward() {
        var input = HerdenDictationInputState()
        let locale = Locale(identifier: "en_US")
        input.begin()

        let first = "This is a deliberately long opening thought with enough words to leave the correction window behind and reach the recent phrase"
        #expect(String(decoding: input.apply(first, locale: locale), as: UTF8.self) == first.lowercased())

        let rollover = input.apply("the recent phrase with a new ending", locale: locale)

        #expect(String(decoding: rollover, as: UTF8.self) == " with a new ending")
        #expect(!rollover.contains(0x7F))
    }

    @Test func appendsNonOverlappingRecognitionWindowInsteadOfDeletingOldDictation() {
        var input = HerdenDictationInputState()
        let locale = Locale(identifier: "en_US")
        input.begin()

        let first = "This first dictated section is comfortably longer than the correction window and must remain in the terminal"
        _ = input.apply(first, locale: locale)

        let rollover = input.apply("a completely new recognition window", locale: locale)

        #expect(String(decoding: rollover, as: UTF8.self) == " a completely new recognition window")
        #expect(!rollover.contains(0x7F))
    }

    @Test func doesNotMistakeASharedLetterForARecognitionWindowOverlap() {
        var input = HerdenDictationInputState()
        let locale = Locale(identifier: "en_US")
        input.begin()

        let first = "This dictated section is deliberately long enough to commit safely and ends with terminal"
        _ = input.apply(first, locale: locale)

        let rollover = input.apply("take the next step", locale: locale)

        #expect(String(decoding: rollover, as: UTF8.self) == " take the next step")
        #expect(!rollover.contains(0x7F))
    }

    @Test func supportsMoreThanOneRecognitionWindowRollover() {
        var input = HerdenDictationInputState()
        let locale = Locale(identifier: "en_US")
        input.begin()

        let first = "A long opening section fills the recognition window while preserving this first overlap phrase"
        _ = input.apply(first, locale: locale)
        _ = input.apply(
            "this first overlap phrase continues through another long section that ends on the second overlap phrase",
            locale: locale)

        let rollover = input.apply(
            "the second overlap phrase and the final words",
            locale: locale)

        #expect(String(decoding: rollover, as: UTF8.self) == " and the final words")
        #expect(!rollover.contains(0x7F))
    }

    @Test func ignoresEmptyInterimRecognitionWithoutErasingTerminalText() {
        var input = HerdenDictationInputState()
        input.begin()
        _ = input.apply("keep this text", locale: Locale(identifier: "en_US"))

        #expect(input.apply("", locale: Locale(identifier: "en_US")).isEmpty)
    }
}
