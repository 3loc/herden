import CoreGraphics
import Testing
@testable import Herden

@Suite("Console horizontal navigation")
struct ConsoleHorizontalNavigationTests {
    @Test func rightSwipeReturnsFromAgentToPicker() {
        #expect(ConsoleHorizontalNavigation.returnsToPicker(
            translation: CGSize(width: 90, height: 12)))
        #expect(!ConsoleHorizontalNavigation.returnsToPicker(
            translation: CGSize(width: 60, height: 0)))
        #expect(!ConsoleHorizontalNavigation.returnsToPicker(
            translation: CGSize(width: 90, height: 80)))
    }

    @Test func leftSwipeReopensTheLastAgent() {
        #expect(ConsoleHorizontalNavigation.opensLastAgent(
            translation: CGSize(width: -90, height: -12)))
        #expect(!ConsoleHorizontalNavigation.opensLastAgent(
            translation: CGSize(width: -60, height: 0)))
        #expect(!ConsoleHorizontalNavigation.opensLastAgent(
            translation: CGSize(width: -90, height: -80)))
    }
}
