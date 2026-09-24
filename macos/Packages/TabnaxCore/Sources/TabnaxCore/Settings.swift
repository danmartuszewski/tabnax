import Foundation
import CoreGraphics

public enum HandPreset: String, Codable, Sendable, CaseIterable {
    case right, left, both, all, custom
    public var alphabet: String { switch self { case .right, .custom: "jkluionmhp"; case .left: "asdfwercgq"; case .both: "asdfjklweruiop"; case .all: "abcdefghijklmnopqrstuvwxyz" } }
}
// `.mnemonic` remains decodable for saved settings; `.stable` also prefers name initials.
public enum AssignmentPolicy: String, Codable, Sendable, CaseIterable { case stable, mnemonic, pairs }
public enum KeyInterpretation: String, Codable, Sendable, CaseIterable { case physical, characters }
public enum ActivationBehavior: String, Codable, Sendable, CaseIterable { case latch, hold }
public enum ModifierSide: String, Codable, Sendable, CaseIterable { case either, left, right }
public enum MouseControl: String, Codable, Sendable, CaseIterable { case off, click, clickAndWheel }
public enum AppearanceSource: String, Codable, Sendable, CaseIterable { case system, light, dark }
public enum ThemePreset: String, Codable, Sendable, CaseIterable {
    case graphite, tabnax, sage, iris, glass, liquidGlass

    public var title: String {
        switch self {
        case .graphite: "Graphite"
        case .tabnax: "Tabnax"
        case .sage: "Sage"
        case .iris: "Iris"
        case .glass: "Frosted Glass"
        case .liquidGlass: "macOS Glass"
        }
    }
    public var detail: String {
        switch self {
        case .graphite: "Quiet, neutral surfaces."
        case .tabnax: "Warm charcoal and signature lime keys."
        case .sage: "Soft botanical greens."
        case .iris: "Lavender surfaces and violet accents."
        case .glass: "Cool, frosted surfaces that let your desktop through."
        case .liquidGlass: "Native Liquid Glass on macOS 26; frosted glass on earlier macOS."
        }
    }
    public var surfaceStyle: ThemeSurfaceStyle {
        switch self {
        case .glass: .frosted
        case .liquidGlass: .liquidGlass
        default: .solid
        }
    }
}
public enum LabelScale: String, Codable, Sendable, CaseIterable {
    case standard, large, extraLarge
    public var factor: Double { switch self { case .standard: 1; case .large: 1.35; case .extraLarge: 2 } }
}
public enum DisplayChoice: String, Codable, Sendable, CaseIterable { case focused, pointer, main }
public enum Anchor: String, Codable, Sendable, CaseIterable {
    case topLeft, topCenter, topRight, middleLeft, center, middleRight, bottomLeft, bottomCenter, bottomRight
    public var title: String { switch self {
    case .topLeft: "Top left"; case .topCenter: "Top center"; case .topRight: "Top right"
    case .middleLeft: "Middle left"; case .center: "Center"; case .middleRight: "Middle right"
    case .bottomLeft: "Bottom left"; case .bottomCenter: "Bottom center"; case .bottomRight: "Bottom right"
    } }
    public var coordinates: (Double, Double) {
        switch self {
        case .topLeft: (0,1); case .topCenter: (0.5,1); case .topRight: (1,1)
        case .middleLeft: (0,0.5); case .center: (0.5,0.5); case .middleRight: (1,0.5)
        case .bottomLeft: (0,0); case .bottomCenter: (0.5,0); case .bottomRight: (1,0)
        }
    }
}
public struct Placement: Codable, Equatable, Sendable {
    public var display: DisplayChoice = .focused
    public var anchor: Anchor = .middleRight
    public var inset: Double = 24
    public init() {}
    public static func defaults(for mode: DisplayMode) -> Self {
        var p = Self()
        p.anchor = switch mode { case .shore, .relay: .middleRight; case .beacons: .bottomCenter; case .canopy: .topCenter; case .lattice, .fold: .center }
        return p
    }
    public func frame(size: CGSize, visible: CGRect) -> CGRect {
        let margin = min(max(0, inset), min(visible.width, visible.height)/4)
        let safe = visible.insetBy(dx: margin, dy: margin)
        let w = min(max(0,size.width),safe.width), h = min(max(0,size.height),safe.height)
        return CGRect(x: safe.minX + (safe.width-w)*anchor.coordinates.0, y: safe.minY + (safe.height-h)*anchor.coordinates.1, width: w, height: h)
    }
}
public struct SelectionPreferences: Codable, Equatable, Sendable {
    public var hand: HandPreset = .right
    public var baseHand: HandPreset = .right
    public var alphabet = HandPreset.right.alphabet
    public var policy: AssignmentPolicy = .stable
    public var interpretation: KeyInterpretation = .physical
    public var baseLayoutID = "com.apple.keylayout.US"
    public var appShortcuts = AppShortcutPreferences()
    public init() {}
    private enum CodingKeys: String, CodingKey { case hand, baseHand, alphabet, policy, interpretation, baseLayoutID, appShortcuts }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A single missing or corrupt field here must not fail the whole document decode
        // (that would flip the app permanently read-only for the session); fall back to
        // this type's own defaults per field, same as appShortcuts already did.
        let fallback = Self()
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key))?.flatMap { $0 } ?? fallback
        }
        hand = field(.hand, fallback.hand)
        baseHand = field(.baseHand, fallback.baseHand)
        alphabet = field(.alphabet, fallback.alphabet)
        policy = field(.policy, fallback.policy)
        interpretation = field(.interpretation, fallback.interpretation)
        baseLayoutID = field(.baseLayoutID, fallback.baseLayoutID)
        appShortcuts = field(.appShortcuts, AppShortcutPreferences())
    }
    public mutating func choose(_ hand: HandPreset) { self.hand = hand; if hand != .custom { baseHand = hand; alphabet = hand.alphabet } }
    public mutating func restoreOrder() { alphabet = baseHand.alphabet; hand = baseHand }
    public static func normalize(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace } }
}
public struct ActivationPreferences: Codable, Equatable, Sendable {
    public var keyCode: UInt16 = 49
    // Core values use the same documented CGEvent flag bits; no AppKit dependency.
    public var modifiers: UInt64 = (1 << 18) | (1 << 19)
    public var behavior: ActivationBehavior = .latch
    public var side: ModifierSide = .either
    /// Hold-behavior only: a quick tap and release swaps straight to the previous window
    /// without ever showing the switcher panel. Nil in documents saved before this existed,
    /// which fall back to off (the panel keeps showing, as it always did).
    public var quietReturn: Bool?
    public init() {}
    public mutating func restoreChord() { keyCode = 49; modifiers = Self().modifiers }
    public mutating func useCommandTab() { keyCode = 48; modifiers = 1 << 20 }
    public var isCommandTab: Bool { keyCode == 48 && modifiers == 1 << 20 }
    public var quietReturnEnabled: Bool { quietReturn ?? false }
    public func overlaps(_ other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
            && (side == .either || other.side == .either || side == other.side)
    }
    public static let validationMessage = "Use Command–Tab, or a non-navigation key with Control, Option or Command. Shift alone is allowed only with function keys. Command–Space combinations are reserved."
    private static let functionKeys: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
    public var valid: Bool {
        // Command–Tab is an intentional replacement for the macOS app switcher.
        // Keep ordinary typing and the other navigation/system chords reserved.
        if isCommandTab { return true }
        let allowed: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        let reserved: Set<UInt16> = [48, 53, 36, 76, 51, 123, 124, 125, 126]
        return keyCode < 128 && modifiers & ~allowed == 0 && modifiers.nonzeroBitCount >= 1 && !reserved.contains(keyCode)
            && (modifiers != 1 << 17 || Self.functionKeys.contains(keyCode))
            && !(keyCode == 49 && modifiers & (1 << 20) != 0) // Spotlight/input-source shortcuts
    }
}
public struct SearchActivationPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public var shortcut = suggestedShortcut
    public static var suggestedShortcut: ActivationPreferences {
        var value = ActivationPreferences(); value.modifiers = (1 << 18) | (1 << 17); return value
    }
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, shortcut }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Malformed/missing new fields cannot opt a migrated document in.
        if let saved = try? values.decode(ActivationPreferences.self, forKey: .shortcut), saved.valid {
            shortcut = saved
            enabled = (try? values.decode(Bool.self, forKey: .enabled)) ?? false
        }
    }
}
public enum BrowserID: String, Codable, Sendable, CaseIterable {
    case arc, zen, safari, chrome, firefox, edge, brave
    public var title: String { self == .arc ? "Arc" : rawValue.capitalized }
    public var bundleID: String { switch self {
    case .arc: "company.thebrowser.Browser"; case .zen: "app.zen-browser.zen"; case .safari: "com.apple.Safari"
    case .chrome: "com.google.Chrome"; case .firefox: "org.mozilla.firefox"; case .edge: "com.microsoft.edgemac"; case .brave: "com.brave.Browser"
    } }
}
public enum BrowserRange: String, Codable, Sendable, CaseIterable { case all, activeBrowser, activeWindow }
public struct BrowserPreferences: Codable, Equatable, Sendable {
    public var enabled = true
    public var automatic = true
    public var selected = Set(BrowserID.allCases)
    public var range: BrowserRange = .all
    public init() {}
    public func includes(_ id: BrowserID) -> Bool { enabled && (automatic || selected.contains(id)) }
}
public enum DesktopSpotlightMode: String, Codable, Equatable, Sendable { case selectedWindow, switcherOnly }
public struct DesktopSpotlightPreferences: Codable, Equatable, Sendable {
    public static let defaultAnimationDuration = 0.13655945920658685
    public var mode: DesktopSpotlightMode = .selectedWindow
    public var switcherDimmingOpacity = 0.75
    public var previewsWindows: Bool { enabled && mode == .selectedWindow }
    public var resolvedSwitcherOpacity: Double { switcherDimmingOpacity.isFinite ? min(1, max(0, switcherDimmingOpacity)) : 0.75 }
    public var activeOpacity: Double { mode == .switcherOnly ? resolvedSwitcherOpacity : resolvedOpacity }
    public var enabled = true
    public var dimmingOpacity = 0.75
    public var animationEnabled = true
    public var animationDuration = Self.defaultAnimationDuration
    public init() {}
    public var resolvedOpacity: Double { dimmingOpacity.isFinite ? min(1, max(0, dimmingOpacity)) : 0.75 }
    public var resolvedAnimationDuration: Double { animationDuration.isFinite ? min(0.5, max(0.08, animationDuration)) : Self.defaultAnimationDuration }
    public func transitionDuration(reduceMotion: Bool) -> Double { animationEnabled && !reduceMotion ? resolvedAnimationDuration : 0 }
    private enum CodingKeys: String, CodingKey { case enabled, dimmingOpacity, animationEnabled, animationDuration, mode, switcherDimmingOpacity }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decodeIfPresent(DesktopSpotlightMode.self, forKey: .mode) ?? .selectedWindow
        switcherDimmingOpacity = try values.decodeIfPresent(Double.self, forKey: .switcherDimmingOpacity) ?? 0.75
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        dimmingOpacity = try values.decodeIfPresent(Double.self, forKey: .dimmingOpacity) ?? 0.75
        animationEnabled = try values.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? true
        animationDuration = try values.decodeIfPresent(Double.self, forKey: .animationDuration) ?? Self.defaultAnimationDuration
    }
}
public struct AppearancePreferences: Codable, Equatable, Sendable {
    public var source: AppearanceSource = .system
    public var preset: ThemePreset = .graphite
    public var scale: LabelScale = .standard
    public var strongOutlines = false
    public var desktopSpotlight = DesktopSpotlightPreferences()
    public var overrides: [String: [String: [String: String]]] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case source, preset, scale, strongOutlines, desktopSpotlight, overrides }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(AppearanceSource.self, forKey: .source)
        preset = try values.decode(ThemePreset.self, forKey: .preset)
        scale = try values.decode(LabelScale.self, forKey: .scale)
        strongOutlines = try values.decode(Bool.self, forKey: .strongOutlines)
        overrides = try values.decode([String: [String: [String: String]]].self, forKey: .overrides)
        desktopSpotlight = try values.decodeIfPresent(DesktopSpotlightPreferences.self, forKey: .desktopSpotlight) ?? .init()
    }
    public mutating func resetColor(_ token: String, dark: Bool) {
        let key = preset.rawValue, tone = dark ? "dark" : "light"
        overrides[key]?[tone]?[token] = nil
        if overrides[key]?[tone]?.isEmpty == true { overrides[key]?[tone] = nil }
        if overrides[key]?.isEmpty == true { overrides[key] = nil }
    }
    public mutating func setColor(_ value: String, token: String, dark: Bool) {
        overrides[preset.rawValue, default: [:]][dark ? "dark" : "light", default: [:]][token] = value
    }
}
public struct SettingsDocument: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var mode: DisplayMode = .shore
    public var selection = SelectionPreferences()
    public var activation = ActivationPreferences()
    public var searchActivation = SearchActivationPreferences()
    public var mouse: MouseControl = .click
    public var moveCursorToSelectedWindow = false
    public var windowActionsEnabled = true
    public var rememberSearchChoices = false
    public var traversalOrder: TraversalOrder = .stable
    public var exclusions = ExclusionPreferences()
    public var includeMinimized = true
    public var includeHidden = true
    public var appearance = AppearancePreferences()
    public var positions: [String: Placement] = [:]
    /// One display choice for every mode. Nil only in documents saved before it existed,
    /// which fall back to the per-mode value they stored.
    public var display: DisplayChoice?
    /// Opt-in simultaneous copies; the existing display choice selects the initial input owner.
    public var allDisplays = false
    public var browsers = BrowserPreferences()
    public var launchAtLogin = false
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, mode, selection, activation, mouse, includeMinimized, includeHidden, appearance, positions, browsers, launchAtLogin, display, moveCursorToSelectedWindow, windowActionsEnabled, rememberSearchChoices, exclusions, traversalOrder, searchActivation, allDisplays
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        mode = try values.decode(DisplayMode.self, forKey: .mode)
        selection = try values.decode(SelectionPreferences.self, forKey: .selection)
        activation = try values.decode(ActivationPreferences.self, forKey: .activation)
        searchActivation = (try? values.decodeIfPresent(SearchActivationPreferences.self, forKey: .searchActivation)) ?? .init()
        // Older releases accepted Shift-only printable chords. Recover only that legacy
        // case on load, preserving behavior/side and every unrelated preference. New saves
        // still reject it via validated(), without making the whole document read-only.
        if activation.modifiers == 1 << 17, !activation.valid {
            activation.restoreChord()
            if activation.overlaps(searchActivation.shortcut) { searchActivation.enabled = false }
        }
        mouse = try values.decode(MouseControl.self, forKey: .mouse)
        includeMinimized = try values.decode(Bool.self, forKey: .includeMinimized)
        includeHidden = try values.decode(Bool.self, forKey: .includeHidden)
        appearance = try values.decode(AppearancePreferences.self, forKey: .appearance)
        positions = try values.decode([String: Placement].self, forKey: .positions)
        browsers = try values.decode(BrowserPreferences.self, forKey: .browsers)
        launchAtLogin = try values.decode(Bool.self, forKey: .launchAtLogin)
        display = try values.decodeIfPresent(DisplayChoice.self, forKey: .display)
        allDisplays = (try? values.decodeIfPresent(Bool.self, forKey: .allDisplays)) ?? false
        moveCursorToSelectedWindow = try values.decodeIfPresent(Bool.self, forKey: .moveCursorToSelectedWindow) ?? false
        windowActionsEnabled = try values.decodeIfPresent(Bool.self, forKey: .windowActionsEnabled) ?? true
        rememberSearchChoices = (try? values.decodeIfPresent(Bool.self, forKey: .rememberSearchChoices)) ?? false
        traversalOrder = (try? values.decodeIfPresent(TraversalOrder.self, forKey: .traversalOrder)) ?? .stable
        exclusions = (try? values.decodeIfPresent(ExclusionPreferences.self, forKey: .exclusions)) ?? .init()
    }
    public func placement(for mode: DisplayMode) -> Placement {
        var placement = positions[mode.rawValue] ?? .defaults(for: mode)
        if let display { placement.display = display }
        return placement
    }
    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw SettingsError.unsupportedVersion }
        guard (try? AddressBook(alphabet: selection.alphabet)) != nil, selection.baseHand != .custom else { throw SettingsError.invalid("Use 6–26 different letters A–Z.") }
        guard activation.valid, searchActivation.shortcut.valid else { throw SettingsError.invalid(ActivationPreferences.validationMessage) }
        guard !searchActivation.enabled || !activation.overlaps(searchActivation.shortcut) else {
            throw SettingsError.invalid("The search shortcut overlaps the main shortcut. Choose another chord or non-overlapping left/right modifier sides.")
        }
        try exclusions.validate()
        try selection.appShortcuts.validate(alphabet: selection.alphabet, policy: selection.policy)
        // Positions and appearance overrides are cosmetic and per-entry: a single corrupt
        // entry (e.g. from a future app version, or hand-edited defaults) drops just that
        // entry instead of invalidating the whole document and locking settings read-only.
        var result = self
        result.appearance.desktopSpotlight.switcherDimmingOpacity = appearance.desktopSpotlight.resolvedSwitcherOpacity
        result.appearance.desktopSpotlight.dimmingOpacity = appearance.desktopSpotlight.resolvedOpacity
        result.appearance.desktopSpotlight.animationDuration = appearance.desktopSpotlight.resolvedAnimationDuration
        for (key, placement) in positions where !(DisplayMode(rawValue: key) != nil && placement.inset.isFinite && (12...64).contains(placement.inset) && placement.inset.truncatingRemainder(dividingBy: 4) == 0) {
            result.positions[key] = nil
        }
        for (preset, tones) in appearance.overrides {
            guard ThemePreset(rawValue: preset) != nil else { result.appearance.overrides[preset] = nil; continue }
            for (tone, colors) in tones {
                guard ["light", "dark"].contains(tone) else { result.appearance.overrides[preset]?[tone] = nil; continue }
                for (token, hex) in colors where !(["keyBg", "selection"].contains(token) && RGB(hex: hex) != nil) {
                    result.appearance.overrides[preset]?[tone]?[token] = nil
                }
                if result.appearance.overrides[preset]?[tone]?.isEmpty == true { result.appearance.overrides[preset]?[tone] = nil }
            }
            if result.appearance.overrides[preset]?.isEmpty == true { result.appearance.overrides[preset] = nil }
        }
        return result
    }
}
public enum SettingsError: Error, Equatable, LocalizedError {
    case unsupportedVersion, invalid(String)
    public var errorDescription: String? { switch self { case .unsupportedVersion: "This settings version is newer than this app. Your saved settings have been preserved."; case .invalid(let message): message } }
}
