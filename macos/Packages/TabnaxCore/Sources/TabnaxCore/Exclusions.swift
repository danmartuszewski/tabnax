import Foundation

/// Bundle identifiers are durable, exact, case-sensitive identities. Names are display only.
public struct AppRule: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }
    public init(bundleID: String, name: String = "") { self.bundleID = bundleID; self.name = name }
    public static func validBundleID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [45, 46, 95].contains($0)
        }
    }
}

public enum TitleMatch: String, Codable, CaseIterable, Sendable {
    case contains, exact, wildcard
    public var title: String { switch self { case .contains: "Contains"; case .exact: "Equals"; case .wildcard: "Wildcard" } }
}
public struct TitleRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Empty means every app, including apps without a bundle ID.
    public var bundleID: String
    public var pattern: String
    public var match: TitleMatch
    public init(id: UUID = UUID(), bundleID: String = "", pattern: String, match: TitleMatch = .contains) {
        self.id = id; self.bundleID = bundleID; self.pattern = pattern; self.match = match
    }
    public var validationError: String? {
        if !bundleID.isEmpty && !AppRule.validBundleID(bundleID) { return "Use a bundle ID with letters, digits, dots, hyphens or underscores, or leave it empty for all apps." }
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a nonempty title pattern." }
        if pattern.count > 256 { return "Use at most 256 characters in a title pattern." }
        if pattern.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return "Title patterns cannot contain control characters." }
        if match == .wildcard && tokens == nil { return "In wildcards, escape only *, ? or \\ with \\. A trailing \\ is invalid." }
        return nil
    }
    fileprivate enum Token { case literal(Character), one, many }
    private var tokens: [Token]? {
        var result: [Token] = [], escaped = false
        for ch in pattern.lowercased() {
            if escaped {
                guard ch == "*" || ch == "?" || ch == "\\" else { return nil }
                result.append(.literal(ch)); escaped = false
            } else if ch == "\\" { escaped = true }
            else if ch == "*" { result.append(.many) }
            else if ch == "?" { result.append(.one) }
            else { result.append(.literal(ch)) }
        }
        return escaped ? nil : result
    }
    public func matches(title: String, bundleID: String) -> Bool {
        matcher?.matches(lowercasedTitle: title.lowercased(), bundleID: bundleID) ?? false
    }
    /// Nil for invalid rules. Validation, lowercasing and tokenizing happen once here, so
    /// filtering a snapshot doesn't repeat them for every target and rule.
    var matcher: Matcher? { validationError == nil ? Matcher(bundleID: bundleID, pattern: pattern.lowercased(), match: match, tokens: tokens ?? []) : nil }
    struct Matcher {
        let bundleID: String, pattern: String, match: TitleMatch
        fileprivate let tokens: [Token]
        func matches(lowercasedTitle title: String, bundleID: String) -> Bool {
            guard self.bundleID.isEmpty || self.bundleID == bundleID else { return false }
            switch match {
            case .contains: return title.contains(pattern)
            case .exact: return title == pattern
            case .wildcard: return TitleRule.glob(tokens, title)
            }
        }
    }
    private static func glob(_ tokens: [Token], _ title: String) -> Bool {
        // Whole-title glob, O(title × pattern), with bounded pattern length and no regex backtracking.
        let chars = Array(title)
        var row = [Bool](repeating: false, count: chars.count + 1); row[0] = true
        for token in tokens {
            var next = [Bool](repeating: false, count: row.count)
            if case .many = token { next[0] = row[0] }
            for i in chars.indices {
                switch token {
                case .many: next[i + 1] = row[i + 1] || next[i]
                case .one: next[i + 1] = row[i]
                case .literal(let ch): next[i + 1] = row[i] && chars[i] == ch
                }
            }
            row = next
        }
        return row.last == true
    }
}

public struct ExclusionPreferences: Codable, Equatable, Sendable {
    public var apps: [AppRule] = []
    public var titles: [TitleRule] = []
    public var shortcutExceptions: [AppRule] = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case apps, titles, shortcutExceptions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = (try? c.decode(RuleList<AppRule>.self, forKey: .apps))?.values ?? []
        titles = (try? c.decode(RuleList<TitleRule>.self, forKey: .titles))?.values ?? []
        shortcutExceptions = (try? c.decode(RuleList<AppRule>.self, forKey: .shortcutExceptions))?.values ?? []
        // Bad rules must never lock unrelated settings or become accidental match-all rules.
        apps = Self.sanitized(apps); shortcutExceptions = Self.sanitized(shortcutExceptions)
        var ids = Set<UUID>()
        titles = titles.filter { $0.validationError == nil && ids.insert($0.id).inserted }
    }
    private static func sanitized(_ rules: [AppRule]) -> [AppRule] {
        var ids = Set<String>()
        return rules.filter { AppRule.validBundleID($0.bundleID) && ids.insert($0.bundleID).inserted }
    }
    public func validate() throws {
        for rules in [apps, shortcutExceptions] {
            guard Self.sanitized(rules) == rules else { throw SettingsError.invalid("Use valid, unique bundle IDs for each app list.") }
        }
        guard Set(titles.map(\.id)).count == titles.count else { throw SettingsError.invalid("Title rules must have unique identities.") }
        for rule in titles { if let error = rule.validationError { throw SettingsError.invalid(error) } }
    }
    /// Shared by all activation shortcuts, independent of target visibility.
    public func passesActivationShortcuts(to bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return shortcutExceptions.contains { $0.bundleID == bundleID }
    }
    /// Call only AFTER resolving tab owners and mapping labels, including closed launch targets.
    public func applying(to source: CatalogueSnapshot) -> CatalogueSnapshot {
        let excludedBundles = Set(apps.filter { AppRule.validBundleID($0.bundleID) }.map(\.bundleID))
        let owners = Dictionary(source.apps.map { ($0.id.process, $0.bundleID) }, uniquingKeysWith: { first, _ in first })
        let matchers = titles.compactMap(\.matcher)
        func hidden(_ target: Target, title: Bool) -> Bool {
            let bundle = target.bundleID.isEmpty ? (owners[target.groupOwner] ?? "") : target.bundleID
            if !bundle.isEmpty && excludedBundles.contains(bundle) { return true }
            guard title, !matchers.isEmpty else { return false }
            let lowered = target.title.lowercased()
            return matchers.contains { $0.matches(lowercasedTitle: lowered, bundleID: bundle) }
        }
        var result = source
        result.windows.removeAll { hidden($0, title: true) }
        result.tabs.removeAll { hidden($0, title: true) }
        result.apps.removeAll { hidden($0, title: false) }
        let kept = Set((result.windows + result.tabs + result.apps).map(\.id))
        result.suppressedIDs.formUnion((source.windows + source.tabs + source.apps).map(\.id).filter { !kept.contains($0) })
        return result
    }
}

private struct RuleList<Value: Decodable>: Decodable {
    var values: [Value] = []
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            let decoder = try c.superDecoder()
            if let value = try? Value(from: decoder) { values.append(value) }
        }
    }
}
