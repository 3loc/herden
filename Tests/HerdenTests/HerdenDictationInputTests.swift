import Foundation
import Testing

@testable import Herden

@Suite("Herden terminal dictation")
struct HerdenDictationInputTests {
    @Test func offersTheSevenRequestedLanguagesInAStableOrder() {
        let locales = ["en_GB", "fr_FR", "pt_BR", "zh_TW", "en_US", "de_DE", "sv_SE", "pt_PT", "zh_CN"]
            .map(Locale.init(identifier:))
        #expect(HerdenDictationLanguages.available(in: locales).map(\.identifier)
            == ["zh_TW", "zh_CN", "sv_SE", "pt_PT", "en_US", "de_DE", "fr_FR"])
    }

    @Test func germanAndFrenchHaveNativeNamesAndKeepTheirSelection() {
        let locales = ["de-DE", "fr-FR"].map(Locale.init(identifier:))
        #expect(HerdenDictationLanguages.available(in: locales) == locales)
        #expect(locales.map(HerdenDictationLanguages.displayName) == ["Deutsch", "Français"])
        for locale in locales {
            #expect(HerdenDictationLanguages.selection(
                saved: locale, current: .current, available: locales) == locale)
        }
    }

    @Test func migratesRemovedEnglishVariantsToUSAndFallsBackToAnAvailableModel() {
        let available = ["zh_TW", "en_US"].map(Locale.init(identifier:))
        #expect(HerdenDictationLanguages.selection(
            saved: Locale(identifier: "en_GB"), current: Locale(identifier: "zh_TW"),
            available: available)?.identifier == "en_US")
        #expect(HerdenDictationLanguages.selection(
            saved: Locale(identifier: "de_DE"), current: Locale(identifier: "fr_FR"),
            available: available)?.identifier == "en_US")
        #expect(HerdenDictationLanguages.selection(
            saved: Locale(identifier: "en_US"), current: .current, available: []) == nil)
    }

    @Test func recognisesHyphenatedAppleLocaleIdentifiersAndDoesNotInventMissingModels() {
        let locales = ["zh-Hant-TW", "en-US", "pt-BR"].map(Locale.init(identifier:))
        #expect(HerdenDictationLanguages.available(in: locales).map(\.identifier)
            == ["zh-Hant-TW", "en-US"])
    }

    @MainActor
    @Test func remembersTheSelectedRecognitionLocaleAcrossScreens() throws {
        let suiteName = "HerdenDictationInputTests.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        suite.set("zh_TW", forKey: HerdenSpeechRecorder.selectedLocaleDefaultsKey)

        let recorder = HerdenSpeechRecorder(defaults: suite)

        #expect(recorder.selectedLocale.identifier == "zh_TW")
    }

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

    @Test func repeatedIdenticalHypothesesNeverRepeatWordsInTheTerminal() {
        var input = HerdenDictationInputState()
        let locale = Locale(identifier: "en_US")
        input.begin()

        #expect(String(decoding: input.apply("open the space", locale: locale), as: UTF8.self) == "open the space")
        #expect(input.apply("open the space", locale: locale).isEmpty)
        #expect(String(decoding: input.apply("open the space now", locale: locale), as: UTF8.self) == " now")
        #expect(input.apply("open the space now", locale: locale).isEmpty)
    }
}
