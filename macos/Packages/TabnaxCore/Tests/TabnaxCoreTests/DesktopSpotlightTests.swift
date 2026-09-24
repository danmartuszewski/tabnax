import Foundation
import Testing
@testable import TabnaxCore

@Test func switcherOnlyModeRetainsIndependentOpacityAndPreservesOldPreferences() throws {
    let old = Data(#"{"enabled":true,"dimmingOpacity":0.35,"animationEnabled":false,"animationDuration":0.4}"#.utf8)
    let decoded = try JSONDecoder().decode(DesktopSpotlightPreferences.self, from: old)
    #expect(decoded.mode == .selectedWindow)
    #expect(decoded.dimmingOpacity == 0.35)
    #expect(decoded.animationDuration == 0.4)
    #expect(!decoded.animationEnabled)
    #expect(decoded.switcherDimmingOpacity == 0.75)
    var settings = SettingsDocument()
    settings.appearance.desktopSpotlight.mode = .switcherOnly
    settings.appearance.desktopSpotlight.switcherDimmingOpacity = 0.9
    settings.appearance.desktopSpotlight.dimmingOpacity = 0.4
    #expect(!settings.appearance.desktopSpotlight.previewsWindows)
    #expect(settings.appearance.desktopSpotlight.activeOpacity == 0.9)
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(settings)).validated() == settings)
    settings.appearance.desktopSpotlight.mode = .selectedWindow
    #expect(settings.appearance.desktopSpotlight.previewsWindows)
    #expect(settings.appearance.desktopSpotlight.activeOpacity == 0.4)
    for (raw, expected) in [(-1.0, 0.0), (2.0, 1.0), (Double.nan, 0.75)] {
        settings.appearance.desktopSpotlight.switcherDimmingOpacity = raw
        #expect(try settings.validated().appearance.desktopSpotlight.resolvedSwitcherOpacity == expected)
    }
}

@Test func windowAnimationDefaultsMigrationPersistenceAndReducedMotion() throws {
    let old = Data(#"{"enabled":true,"dimmingOpacity":0.6}"#.utf8)
    let migrated = try JSONDecoder().decode(DesktopSpotlightPreferences.self, from: old)
    #expect(migrated.animationEnabled)
    #expect(migrated.animationDuration == DesktopSpotlightPreferences.defaultAnimationDuration)
    #expect(migrated.dimmingOpacity == 0.6)
    for enabled in [true, false] {
        for duration in [0.08, 0.2, 0.5] {
            var settings = SettingsDocument()
            settings.appearance.desktopSpotlight.animationEnabled = enabled
            settings.appearance.desktopSpotlight.animationDuration = duration
            #expect(try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(settings)).validated() == settings)
            #expect(settings.appearance.desktopSpotlight.transitionDuration(reduceMotion: true) == 0)
            #expect(settings.appearance.desktopSpotlight.transitionDuration(reduceMotion: false) == (enabled ? duration : 0))
        }
    }
    for (raw, expected) in [(-1.0, 0.08), (10.0, 0.5), (Double.nan, DesktopSpotlightPreferences.defaultAnimationDuration), (Double.infinity, DesktopSpotlightPreferences.defaultAnimationDuration)] {
        var settings = SettingsDocument(); settings.appearance.desktopSpotlight.animationDuration = raw
        #expect(try settings.validated().appearance.desktopSpotlight.animationDuration == expected)
    }
}

@Test func desktopSpotlightMigratesOldSettingsWithoutResettingAppearance() throws {
    var original = SettingsDocument()
    original.appearance.preset = .iris
    original.appearance.source = .dark
    original.appearance.setColor("#bbccdd", token: "selection", dark: true)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    var appearance = try #require(json["appearance"] as? [String: Any])
    appearance.removeValue(forKey: "desktopSpotlight"); json["appearance"] = appearance
    let decoded = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: json)).validated()
    #expect(decoded == original)
    #expect(decoded.appearance.desktopSpotlight.enabled)
    #expect(decoded.appearance.desktopSpotlight.dimmingOpacity == 0.75)
}

@Test func desktopSpotlightPersistsAndSanitizesOpacity() throws {
    for enabled in [false, true] {
        for opacity in [0.0, 0.35, 1.0] {
            var settings = SettingsDocument()
            settings.appearance.desktopSpotlight.enabled = enabled
            settings.appearance.desktopSpotlight.dimmingOpacity = opacity
            let data = try JSONEncoder().encode(settings)
            #expect(try JSONDecoder().decode(SettingsDocument.self, from: data).validated() == settings)
            settings.appearance.resetColor("selection", dark: false)
            #expect(settings.appearance.desktopSpotlight.enabled == enabled)
            #expect(settings.appearance.desktopSpotlight.dimmingOpacity == opacity)
        }
    }
    for (input, expected) in [(-0.5, 0.0), (1.5, 1.0), (Double.nan, 0.75), (Double.infinity, 0.75)] {
        var settings = SettingsDocument(); settings.appearance.desktopSpotlight.dimmingOpacity = input
        #expect(try settings.validated().appearance.desktopSpotlight.dimmingOpacity == expected)
    }
}
