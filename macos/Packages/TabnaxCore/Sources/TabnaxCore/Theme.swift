import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    public init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let n = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        r = Double((n >> 16) & 255)/255; g = Double((n >> 8) & 255)/255; b = Double(n & 255)/255
    }
    public var hex: String { String(format: "#%02x%02x%02x", Int((r*255).rounded()), Int((g*255).rounded()), Int((b*255).rounded())) }
    public var luminance: Double { [r,g,b].map { $0 <= 0.04045 ? $0/12.92 : pow(($0+0.055)/1.055,2.4) }.enumerated().reduce(0) { $0 + $1.element * [0.2126,0.7152,0.0722][$1.offset] } }
    public func contrast(_ other: Self) -> Double { (max(luminance,other.luminance)+0.05)/(min(luminance,other.luminance)+0.05) }
    public func mixed(with other: Self, amount: Double) -> Self { .init(r:r+(other.r-r)*amount,g:g+(other.g-g)*amount,b:b+(other.b-b)*amount) }
    public var readableText: Self { let black = RGB(hex:"#111111")!, white = RGB(hex:"#ffffff")!; return contrast(black) >= contrast(white) ? black : white }
}
public enum ThemeSurfaceStyle: Equatable, Sendable {
    case solid, frosted, liquidGlass

    public func resolved(reduceTransparency: Bool, increaseContrast: Bool, supportsLiquidGlass: Bool) -> Self {
        if reduceTransparency || increaseContrast { return .solid }
        return self == .liquidGlass && !supportsLiquidGlass ? .frosted : self
    }
}

public struct ThemeTokens: Equatable, Sendable {
    public let surface: RGB, text: RGB, secondary: RGB, key: RGB, keyText: RGB, selection: RGB
    public let adjustedSelection: Bool
    public let surfaceStyle: ThemeSurfaceStyle
    public static func resolve(_ preferences: AppearancePreferences, dark: Bool) -> Self {
        let green = preferences.preset == .tabnax
        let surfaceHex: String = switch preferences.preset {
        case .tabnax: dark ? "#202720" : "#f5f7ef"
        case .sage: dark ? "#232c29" : "#f1f6f0"
        case .iris: dark ? "#292635" : "#f6f2fb"
        case .glass: dark ? "#202d38" : "#f0f7fc"
        case .liquidGlass: dark ? "#24262a" : "#f7f8fa"
        case .graphite: dark ? "#24282e" : "#fafafa"
        }
        let surface = RGB(hex: surfaceHex)!
        let text = RGB(hex: green ? (dark ? "#f6f8ee" : "#293323") : (dark ? "#f1f3f5" : "#22272c"))!
        let secondary = RGB(hex: green ? (dark ? "#bac3b3" : "#59634f") : (dark ? "#b7bec8" : "#62666c"))!
        let keyHex: String = switch preferences.preset {
        case .graphite: dark ? "#424a54" : "#e5e7e9"; case .tabnax: "#d9f68c"
        case .sage: dark ? "#c0d9ba" : "#dcebdd"; case .iris: dark ? "#d0c2ee" : "#e7e1fa"
        case .glass: dark ? "#b8ddec" : "#dbeef8"
        case .liquidGlass: dark ? "#45494f" : "#e7e9ed"
        }
        let selectionHex: String = switch preferences.preset {
        case .graphite, .liquidGlass: dark ? "#79adff" : "#2563eb"
        case .tabnax: dark ? "#a8d15c" : "#536f28"
        case .sage: dark ? "#8fbc93" : "#3b7152"
        case .iris: dark ? "#b29de2" : "#7450b1"
        case .glass: dark ? "#85cee9" : "#176b91"
        }
        let custom = preferences.overrides[preferences.preset.rawValue]?[dark ? "dark" : "light"] ?? [:]
        let key = RGB(hex:custom["keyBg"] ?? keyHex) ?? RGB(hex:keyHex)!
        let requested = RGB(hex:custom["selection"] ?? selectionHex) ?? RGB(hex:selectionHex)!
        var selection = requested
        if requested.contrast(surface) < 3 {
            let end = surface.readableText
            for step in 1...100 { selection = requested.mixed(with:end,amount:Double(step)/100); if selection.contrast(surface) >= 3 { break } }
        }
        let resolvedText = Self.ensureContrast(text, against: surface, minimum: 4.5)
        let resolvedSecondary = Self.ensureContrast(secondary, against: surface, minimum: 4.5)
        return Self(surface:surface,text:resolvedText,secondary:resolvedSecondary,key:key,keyText:key.readableText,selection:selection,adjustedSelection:selection != requested,surfaceStyle:preferences.preset.surfaceStyle)
    }

    private static func ensureContrast(_ color: RGB, against surface: RGB, minimum: Double) -> RGB {
        guard color.contrast(surface) < minimum else { return color }
        let end = surface.readableText
        var adjusted = color
        for step in 1...100 {
            adjusted = color.mixed(with: end, amount: Double(step)/100)
            if adjusted.contrast(surface) >= minimum { break }
        }
        return adjusted
    }
}
