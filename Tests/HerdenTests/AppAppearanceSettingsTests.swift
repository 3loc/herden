import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Herden

@MainActor
@Suite("App appearance settings")
struct AppAppearanceSettingsTests {
    private func makeDefaults() throws -> (UserDefaults, cleanup: () -> Void) {
        let suiteName = "hm-app-appearance-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }

    @Test func defaultsToFollowingTheSystem() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppAppearanceSettings(defaults: defaults)

        #expect(settings.selection == .system)
        #expect(settings.preferredColorScheme == nil)
    }

    @Test func selectionPersistsAcrossStoreInstances() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppAppearanceSettings(defaults: defaults)

        settings.select(.dark)

        #expect(AppAppearanceSettings(defaults: defaults).selection == .dark)
    }

    /// A newer build's option name must not brick an older one: an unreadable
    /// stored value falls back to the system appearance rather than sticking
    /// the app in whatever was last rendered.
    @Test func unknownStoredOptionFallsBackToTheSystem() throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        defaults.set("solar-flare", forKey: "app-appearance")

        #expect(AppAppearanceSettings(defaults: defaults).selection == .system)
    }

    @Test(
        arguments: [
            (AppAppearanceOption.system, ColorScheme?.none),
            (.light, .light),
            (.dark, .dark),
        ])
    func eachOptionMapsToItsColorScheme(
        option: AppAppearanceOption, expected: ColorScheme?
    ) throws {
        let (defaults, cleanup) = try makeDefaults()
        defer { cleanup() }
        let settings = AppAppearanceSettings(defaults: defaults)

        settings.select(option)

        #expect(settings.preferredColorScheme == expected)
    }

    @Test func everyOptionIsOfferedInAStableOrder() {
        #expect(AppAppearanceOption.allCases == [.system, .light, .dark])
        #expect(AppAppearanceOption.allCases.map(\.title) == ["System", "Light", "Dark"])
    }

    @Test func brandSurfacesAndInkResolveDifferentlyForDayAndNight() {
        #expect(hex(Brand.background, style: .light) == 0xF8FAF4)
        #expect(hex(Brand.background, style: .dark) == 0x08080A)
        #expect(hex(Brand.ink, style: .light) == 0x14180F)
        #expect(hex(Brand.ink, style: .dark) == 0xF5F4F0)
        #expect(hex(Brand.vine, style: .light) == 0x416D00)
        #expect(hex(Brand.vine, style: .dark) == 0xA8EC2A)
    }

    private func hex(_ color: Color, style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return UInt32((red * 255).rounded()) << 16
            | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
    }
}
