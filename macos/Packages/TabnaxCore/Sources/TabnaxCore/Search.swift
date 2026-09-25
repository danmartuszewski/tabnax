import Foundation
import CryptoKit

/// Search never joins fields or drops meaningful symbols. Formatting separators are
/// optional, but a separator-only term still has to occur literally in one field.
enum SearchText {
    static let locale = Locale(identifier: "en_US_POSIX")
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
    }
    static func isSeparator(_ c: Character) -> Bool { c.isWhitespace || "-_./\\'’‐‑‒–—−".contains(c) }
    static func compact(_ text: String) -> String { text.filter { !isSeparator($0) } }
    static func terms(_ query: String) -> [String] { fold(query).split(whereSeparator: \.isWhitespace).map(String.init) }
}

/// A query term with its separator-free needle, derived once per query instead of once
/// per target field on every keystroke.
struct SearchTerm: Sendable {
    let text: String
    let needle: [Character]
    init(_ text: String) { self.text = text; needle = Array(SearchText.compact(text)) }
}

struct SearchField: Equatable, Sendable {
    let text: String
    let compact: [Character]
    let starts: Set<Int>
    /// Per-character lookups for the scorer's inner loop, derived from `compact`/`starts`.
    private let isStart: [Bool]
    private let isSymbol: [Bool]
    private let initials: [Character]
    init(_ value: String) {
        text = SearchText.fold(value)
        var characters: [Character] = [], boundaries = Set<Int>(), segment = ""
        var previous: Character?
        func appendSegment() {
            guard !segment.isEmpty else { return }
            boundaries.insert(characters.count)
            characters.append(contentsOf: SearchText.fold(segment))
            segment = ""
        }
        let widthFolded = value.folding(options: [.widthInsensitive], locale: SearchText.locale)
        for character in widthFolded {
            if SearchText.isSeparator(character) { appendSegment(); previous = character; continue }
            // Camel-case initials work alongside ordinary word initials. Fold words,
            // not individual characters, so catalogue refresh remains inexpensive.
            if character.isUppercase && previous?.isLowercase == true { appendSegment() }
            segment.append(character); previous = character
        }
        appendSegment()
        compact = characters; starts = boundaries
        isStart = characters.indices.map { boundaries.contains($0) }
        isSymbol = characters.map { !$0.isLetter && !$0.isNumber }
        initials = characters.indices.filter { boundaries.contains($0) }.map { characters[$0] }
    }
    func score(_ term: String) -> Int? { score(SearchTerm(term)) }
    func score(_ term: SearchTerm) -> Int? {
        let needle = term.needle
        guard !needle.isEmpty else { return text.contains(term.text) ? 5_000 : nil }
        guard needle.count <= compact.count else { return nil }
        if needle == compact { return 8_000 }
        // Best contiguous occurrence: whole field, prefix, word prefix, then substring.
        var contiguous: Int?
        for start in compact.indices where compact[start] == needle[0] && start + needle.count <= compact.count {
            if compact[start..<(start + needle.count)].elementsEqual(needle) {
                let score = start == 0 ? 7_000 : isStart[start] ? 6_000 : 5_000
                contiguous = max(contiguous ?? 0, score)
            }
        }
        if let contiguous { return contiguous }
        // A lone character is already covered above. Never treat symbols as omissions:
        // c# cannot become c++, nor can cp skip the ++ in C++ Primer.
        guard needle.count >= 2 else { return nil }
        // Every scored match is an ordered subsequence; most fields fail that linear check,
        // so they skip the quadratic scorer below entirely.
        var matched = 0
        for character in compact where matched < needle.count && character == needle[matched] { matched += 1 }
        guard matched == needle.count else { return nil }
        var previous = Array(repeating: Int.min, count: compact.count)
        for i in compact.indices where compact[i] == needle[0] { previous[i] = (isStart[i] ? 100 : 0) - min(i, 100) }
        for character in needle.dropFirst() {
            var next = Array(repeating: Int.min, count: compact.count), best = Int.min
            for i in compact.indices {
                if i > 0 {
                    let p = i - 1
                    if previous[p] != Int.min { best = max(best, previous[p] + p) }
                    // Gaps may contain letters/digits only, never meaningful symbols.
                    if isSymbol[p] { best = previous[p] == Int.min ? Int.min : previous[p] + p }
                }
                if compact[i] == character, best != Int.min {
                    next[i] = best - i + (isStart[i] ? 100 : 0)
                    if i > 0, previous[i-1] != Int.min { next[i] = max(next[i], previous[i-1] + 30) }
                }
            }
            previous = next
        }
        guard let best = previous.max(), best != Int.min else { return nil }
        var index = 0
        for initial in initials where index < needle.count { if initial == needle[index] { index += 1 } }
        return (index == needle.count ? 4_000 : 2_000) + max(0, min(500, best))
    }
}

/// Opt-in, bounded local choice memory. Only salted digests are encoded: no raw
/// query, title, app name or context. Digests affect ranking, never target identity.
public struct SearchMemory: Codable, Equatable, Sendable {
    public static let capacity = 128
    public let salt: UUID
    public private(set) var revision: UInt64 = 0
    private struct Entry: Codable, Equatable, Sendable { let query: String; let target: String }
    private var entries: [Entry] = []
    public var count: Int { entries.count }
    public init() { salt = UUID() }
    private enum CodingKeys: CodingKey { case salt, entries, revision }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        salt = try values.decode(UUID.self, forKey: .salt)
        revision = try values.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        let decoded = try values.decode([Entry].self, forKey: .entries)
        var seen = Set<String>()
        entries = decoded.suffix(Self.capacity).reversed().filter {
            $0.query.count == 64 && $0.target.count == 64 && ($0.query + $0.target).allSatisfy { $0.isHexDigit }
                && seen.insert($0.query + $0.target).inserted
        }.reversed()
    }
    private func digest(_ fields: [String]) -> String {
        // Length framing prevents field-boundary collisions. The random local salt
        // also prevents a portable hash dictionary across installations or clears.
        let data = (salt.uuidString + fields.map { "\($0.utf8.count):\($0)" }.joined()).data(using: .utf8)!
        let hex = Array("0123456789abcdef".utf8)
        return String(decoding: SHA256.hash(data: data).flatMap { [hex[Int($0 >> 4)], hex[Int($0 & 15)]] }, as: UTF8.self)
    }
    private func queryKey(_ query: String) -> String? {
        let terms = SearchText.terms(query).map { let compact = SearchText.compact($0); return compact.isEmpty ? $0 : compact }.sorted()
        return terms.isEmpty ? nil : digest(terms)
    }
    private func targetKey(_ target: Target) -> String {
        digest([target.bundleID.isEmpty ? target.app : target.bundleID,
                target.id.window == nil ? "app" : "item", target.title, target.group])
    }
    public func bonus(query: String, target: Target) -> Int {
        guard !entries.isEmpty, let key = queryKey(query) else { return 0 }
        let identity = targetKey(target)
        guard let index = entries.lastIndex(where: { $0.query == key && $0.target == identity }) else { return 0 }
        return 300 + index // A nudge within a match tier; exact matches remain strongest.
    }
    func bonuses(query: String, targets: [Target]) -> [TargetID: Int] {
        guard !entries.isEmpty, let key = queryKey(query) else { return [:] }
        let ranks = Dictionary(entries.enumerated().filter { $0.element.query == key }.map { ($0.element.target, 300 + $0.offset) }, uniquingKeysWith: max)
        guard !ranks.isEmpty else { return [:] }
        return Dictionary(targets.compactMap { target in ranks[targetKey(target)].map { (target.id, $0) } }, uniquingKeysWith: max)
    }
    public mutating func remember(query: String, target: Target) {
        guard let key = queryKey(query), target.isRunning, target.available else { return }
        let entry = Entry(query: key, target: targetKey(target))
        entries.removeAll { $0 == entry }; entries.append(entry)
        revision &+= 1
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }
}
