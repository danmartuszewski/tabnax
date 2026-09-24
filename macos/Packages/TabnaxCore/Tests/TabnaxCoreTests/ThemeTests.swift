import Foundation
import Testing
@testable import TabnaxCore

@Test func allSixThemesRoundTripThroughValidatedSettings() throws {
    let expected: [ThemePreset] = [.graphite, .tabnax, .sage, .iris, .glass, .liquidGlass]
    #expect(ThemePreset.allCases == expected)
    for preset in expected {
        var settings = SettingsDocument()
        settings.mode = .canopy
        settings.mouse = .clickAndWheel
        settings.appearance.preset = preset
        settings.appearance.source = .dark
        settings.appearance.scale = .large
        settings.appearance.strongOutlines = true
        settings.appearance.setColor("#347890", token: "keyBg", dark: true)
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(SettingsDocument.self, from: data).validated()
        #expect(restored == settings)
        #expect(ThemeTokens.resolve(restored.appearance, dark: true).key == RGB(hex: "#347890"))
    }
}

@Test func legacyThemeRawValuesStillDecodeWithTheirOverrides() throws {
    // These strings are persisted identifiers, independent of the names shown in Settings.
    let legacy: [(String, ThemePreset)] = [
        ("graphite", .graphite), ("tabnax", .tabnax), ("sage", .sage), ("iris", .iris)
    ]
    for (rawValue, expected) in legacy {
        let fixture: [String: Any] = [
            "source": "system", "preset": rawValue, "scale": "extraLarge", "strongOutlines": false,
            "overrides": [rawValue: ["light": ["keyBg": "#123456"], "dark": ["selection": "#abcdef"]]]
        ]
        let appearance = try JSONDecoder().decode(AppearancePreferences.self, from: JSONSerialization.data(withJSONObject: fixture))
        #expect(appearance.preset == expected)
        #expect(appearance.preset.rawValue == rawValue)
        #expect(appearance.source == .system && appearance.scale == .extraLarge)
        #expect(appearance.overrides[rawValue]?["dark"]?["selection"] == "#abcdef")
        #expect(ThemeTokens.resolve(appearance, dark: false).key == RGB(hex: "#123456"))
        #expect(ThemeTokens.resolve(appearance, dark: false).surfaceStyle == .solid)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(appearance)) as? [String: Any]
        #expect(encoded?["preset"] as? String == rawValue)
    }
}

@Test func themeAndToneOverridesSurviveSwitchingPersistenceAndScopedResets() throws {
    var settings = SettingsDocument()
    let colors = ["#102030", "#203040", "#304050", "#405060", "#506070", "#607080"]
    for (index, preset) in ThemePreset.allCases.enumerated() {
        settings.appearance.preset = preset
        settings.appearance.setColor(colors[index], token: "keyBg", dark: false)
        settings.appearance.setColor(colors[colors.count-1-index], token: "keyBg", dark: true)
        settings.appearance.setColor("#345678", token: "selection", dark: false)
        settings.appearance.setColor("#abcdef", token: "selection", dark: true)
    }
    settings = try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(settings)).validated()
    let allOverrides = settings.appearance.overrides
    for (index, preset) in ThemePreset.allCases.enumerated() {
        settings.appearance.preset = preset
        #expect(ThemeTokens.resolve(settings.appearance, dark: false).key == RGB(hex: colors[index]))
        #expect(ThemeTokens.resolve(settings.appearance, dark: true).key == RGB(hex: colors[colors.count-1-index]))
        #expect(settings.appearance.overrides == allOverrides)
    }

    settings.appearance.preset = .glass
    settings.appearance.resetColor("keyBg", dark: true)
    var expected = allOverrides
    expected["glass"]?["dark"]?["keyBg"] = nil
    #expect(settings.appearance.overrides == expected)
    var uncustomized = AppearancePreferences(); uncustomized.preset = .glass
    #expect(ThemeTokens.resolve(settings.appearance, dark: true).key == ThemeTokens.resolve(uncustomized, dark: true).key)
    #expect(ThemeTokens.resolve(settings.appearance, dark: false).key == RGB(hex: colors[4]))

    settings.appearance.resetColor("selection", dark: true)
    expected["glass"]?["dark"] = nil
    #expect(settings.appearance.overrides == expected)
    settings.appearance.resetColor("keyBg", dark: false)
    settings.appearance.resetColor("selection", dark: false)
    expected["glass"] = nil
    #expect(settings.appearance.overrides == expected)
    #expect(settings.appearance.preset == .glass)
    #expect(settings.appearance.overrides["liquidGlass"] == allOverrides["liquidGlass"])
}

@Test func everyThemeKeepsReadableTextKeysAndSelectionInBothTones() {
    for preset in ThemePreset.allCases {
        for dark in [false, true] {
            var appearance = AppearancePreferences(); appearance.preset = preset
            let standard = ThemeTokens.resolve(appearance, dark: dark)
            // Equal-to-surface overrides exercise automatic selection correction.
            for custom in [nil, "#000000", "#ffffff", "#888888", standard.surface.hex] as [String?] {
                if let custom {
                    appearance.setColor(custom, token: "keyBg", dark: dark)
                    appearance.setColor(custom, token: "selection", dark: dark)
                }
                let tokens = ThemeTokens.resolve(appearance, dark: dark)
                #expect(tokens.text.contrast(tokens.surface) >= 4.5)
                #expect(tokens.secondary.contrast(tokens.surface) >= 4.5)
                #expect(tokens.keyText.contrast(tokens.key) >= 4.5)
                #expect(tokens.selection.contrast(tokens.surface) >= 3)
                if custom == standard.surface.hex { #expect(tokens.adjustedSelection) }
            }
        }
    }
}

@Test func glassMaterialFallsBackForOlderSystemsAndAccessibilityPreferences() {
    let cases: [(reduceTransparency: Bool, increaseContrast: Bool, supported: Bool, expected: [ThemeSurfaceStyle])] = [
        (false, false, true, [.solid, .frosted, .liquidGlass]),
        (false, false, false, [.solid, .frosted, .frosted]),
        (true, false, true, [.solid, .solid, .solid]),
        (true, false, false, [.solid, .solid, .solid]),
        (false, true, true, [.solid, .solid, .solid]),
        (false, true, false, [.solid, .solid, .solid]),
        (true, true, true, [.solid, .solid, .solid]),
        (true, true, false, [.solid, .solid, .solid])
    ]
    for testCase in cases {
        for (index, style) in [ThemeSurfaceStyle.solid, .frosted, .liquidGlass].enumerated() {
            #expect(style.resolved(reduceTransparency: testCase.reduceTransparency,
                                   increaseContrast: testCase.increaseContrast,
                                   supportsLiquidGlass: testCase.supported) == testCase.expected[index])
        }
    }
    #expect(ThemePreset.glass.surfaceStyle == .frosted)
    #expect(ThemePreset.liquidGlass.surfaceStyle == .liquidGlass)
}
