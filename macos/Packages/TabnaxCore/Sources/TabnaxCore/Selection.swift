import Foundation
import CoreGraphics
import Synchronization

public struct TargetID: Hashable, Sendable, Codable {
    public let process: UUID
    public let window: UUID?
    public init(process: UUID, window: UUID? = nil) { self.process = process; self.window = window }
}
public enum DisplayMode: String, Sendable, CaseIterable, Codable {
    case shore, beacons, canopy, lattice, fold, relay
    public var title: String { rawValue.capitalized }
    public var usesGeometry: Bool { self == .beacons || self == .relay }
    public var explanation: String {
        switch self {
        case .shore: "A compact list of windows, tabs and apps."
        case .beacons: "Letters beside visible windows, with everything else in a list."
        case .canopy: "Windows and tabs grouped into app columns."
        case .lattice: "A grid with windows and tabs grouped by app."
        case .fold: "Choose an app, then a window. Apps with just one window select directly."
        case .relay: "Press Enter to return to your previous window, or type a letter to choose another."
        }
    }
}
public struct Target: Equatable, Sendable {
    public let id: TargetID
    public var app: String { didSet { rebuildSearchText() } }
    public var title: String { didSet { rebuildSearchText() } }
    public var address: String
    public var minimized: Bool
    public var hidden: Bool
    public var available: Bool
    public var foldAddress: String
    public var bounds: CGRect?
    public var group: String { didSet { rebuildSearchText() } }
    public var excluded: Bool
    public var onScreen: Bool
    public var bundleID: String
    public var isRunning: Bool
    /// Known and still answering, but left out of the app's current window list: it lives on
    /// another Space or behind a full-screen app. Selecting it lets macOS travel there.
    public var elsewhere: Bool
    /// The owning app's process identity, when it differs from `id.process` (browser tabs
    /// own a per-connection process; their real owning app is resolved separately).
    /// Windows and apps are self-owning and leave this nil.
    public var owner: UUID?
    /// Cached until searchable metadata changes, keeping normalization off the keystroke path.
    public var searchText: String { search.text }
    private var search: SearchCache
    /// Derived entirely from app/title/group, which equality already compares, so it always
    /// compares equal: presenter change checks never re-walk every field's folded characters.
    private struct SearchCache: Equatable, Sendable {
        let text: String
        let fields: [SearchField]
        init(app: String, title: String, group: String) {
            text = SearchText.fold(app + " " + title + " " + group)
            fields = [app, title, group].map(SearchField.init)
        }
        static func == (_: Self, _: Self) -> Bool { true }
    }
    public init(id: TargetID, app: String, title: String, address: String = "", minimized: Bool = false,
                hidden: Bool = false, available: Bool = true, foldAddress: String = "", bounds: CGRect? = nil, onScreen: Bool = false, group: String = "", excluded: Bool = false, bundleID: String = "", isRunning: Bool = true, owner: UUID? = nil, elsewhere: Bool = false) {
        self.id = id; self.app = app; self.title = title; self.address = address
        self.minimized = minimized; self.hidden = hidden; self.available = available
        self.group = group; self.excluded = excluded
        self.foldAddress = foldAddress; self.bounds = bounds; self.onScreen = onScreen
        self.bundleID = bundleID; self.isRunning = isRunning; self.owner = owner; self.elsewhere = elsewhere
        self.search = SearchCache(app: app, title: title, group: group)
    }
    private mutating func rebuildSearchText() {
        search = SearchCache(app: app, title: title, group: group)
    }
    fileprivate func searchScore(_ terms: [SearchTerm]) -> Int? {
        var score = 0
        for term in terms {
            var best: Int?
            for field in search.fields { if let value = field.score(term) { best = max(best ?? value, value) } }
            guard let best else { return nil }
            score += best
        }
        return score
    }
    /// The identity to group by: the real owning app for a browser tab, or itself otherwise.
    public var groupOwner: UUID { owner ?? id.process }
}

public enum AlphabetError: Error, Equatable { case invalid, exhausted }
public struct AddressBook: Sendable {
    public static let rightHand = "jkluionmhp"
    public static let leftHand = "asdfwercgq"
    public let alphabet: String
    public let capacity: Int
    public let policy: AssignmentPolicy
    /// Depends only on alphabet/policy, both immutable after init, so it is computed
    /// once here instead of rebuilding fresh Strings on every address(for:)/pin(:to:) call.
    public let vocabulary: [String]
    private let vocabularySet: Set<String>
    private var assigned: [TargetID: String] = [:]
    // Keep the owner of a held code: a transient catalogue omission is not a new
    // window. Storage is bounded by the same finite vocabulary as `allocated`.
    private var held: [TargetID: String] = [:]
    public private(set) var allocated = Set<String>()
    public init(alphabet: String = Self.rightHand, capacity: Int = 512, policy: AssignmentPolicy = .stable) throws {
        let bytes = Array(alphabet.utf8)
        guard (6...26).contains(bytes.count), Set(bytes).count == bytes.count,
              bytes.allSatisfy({ (97...122).contains($0) }), capacity > 0 else { throw AlphabetError.invalid }
        self.alphabet = alphabet; self.capacity = capacity; self.policy = policy
        let a = alphabet.map(String.init)
        self.vocabulary = policy == .pairs ? a.flatMap { first in a.map { first + $0 } }
            : (0..<4).flatMap { depth in a.dropLast().map { String(repeating: a.last!, count: depth) + $0 } }
        self.vocabularySet = Set(vocabulary)
    }
    /// Appends an unused letter beyond `alphabet` (searched from `z` down, so it lands on
    /// a letter nobody wants as an initial rather than squatting on `a`) so that filler —
    /// not any real letter of `alphabet` — absorbs the multi-depth prefix-marker role
    /// `.stable`/`.mnemonic` vocabularies place on their last letter. Every letter the
    /// caller actually configured is then free to stand alone as a complete address.
    /// Fixed letters outside the alphabet must also be excluded when this book supplies
    /// app prefixes. If no filler is available, the alphabet is returned unchanged.
    public static func extended(_ alphabet: String, excluding reserved: Set<String> = []) -> String {
        guard alphabet.utf8.count < 26 else { return alphabet }
        let used = Set(alphabet)
        guard let filler = "abcdefghijklmnopqrstuvwxyz".reversed().first(where: { !used.contains($0) && !reserved.contains(String($0)) }) else { return alphabet }
        return alphabet + String(filler)
    }
    /// The one letter a `.stable`/`.mnemonic` vocabulary can never hand out as a complete
    /// address on its own — normally the hidden filler from `extended(_:)`, or `alphabet`'s
    /// own last letter when the alphabet already spans all 26. `.pairs` has no single such
    /// letter (every letter opens a two-letter combination instead), so this returns nil.
    public static func overflowLetter(alphabet: String, policy: AssignmentPolicy) -> String? {
        guard policy != .pairs else { return nil }
        return extended(alphabet).last.map(String.init)
    }
    public mutating func address(for id: TargetID, name: String = "") throws -> String {
        if let old = assigned[id] { return old }
        if let old = held.removeValue(forKey: id) {
            assigned[id] = old; return old
        }
        guard allocated.count < capacity else { throw AlphabetError.exhausted }
        let pool = vocabularySet
        var preferred: String?
        // Stability means retaining an assigned address, not choosing it by position.
        // Use the same name-first allocation in every layout, including saved `.stable`
        // preferences. Only the explicit pairs policy skips single-letter mnemonics.
        if policy != .pairs {
            let lowered = name.lowercased()
            let initials = lowered.split(whereSeparator: { !$0.isLetter }).compactMap { $0.first.map(String.init) }
            preferred = initials.first { pool.contains($0) && !allocated.contains($0) }
            // No word initial is free (e.g. another target already claimed it): still favor a
            // letter that actually appears in the name, in reading order, over comfort order —
            // it keeps the code recognizably connected to the name it labels.
            if preferred == nil {
                preferred = lowered.compactMap { $0.isLetter ? String($0) : nil }.first { pool.contains($0) && !allocated.contains($0) }
            }
        }
        guard let code = preferred ?? vocabulary.first(where: { !allocated.contains($0) }) else { throw AlphabetError.exhausted }
        assigned[id] = code; allocated.insert(code); return code
    }
    public mutating func pin(_ id: TargetID, to code: String) throws {
        guard vocabularySet.contains(code) else { throw SettingsError.invalid("That label is not a complete label in this alphabet and policy.") }
        if assigned[id] == code { return }
        guard !allocated.contains(code) else { throw SettingsError.invalid("That label is occupied or held for a closed window. Reset assignments to reclaim held labels.") }
        held[id] = nil; assigned[id] = code; allocated.insert(code)
    }
    /// App reservations may use any letter this book's own `alphabet` doesn't itself need
    /// as a prefix marker — under `.pairs` that's every letter in `alphabet` (each one
    /// opens a two-letter combination); otherwise it's just `alphabet`'s own last letter,
    /// which callers typically arrange (via `extended(_:)`) to be a hidden filler rather
    /// than a letter the user actually configured.
    public mutating func reserveApp(_ id: TargetID, letter: String) throws {
        let reserved = policy == .pairs ? alphabet.contains(letter) : letter == alphabet.last.map(String.init)
        guard letter.utf8.count == 1, letter.utf8.allSatisfy({ (97...122).contains($0) }),
              !reserved, !allocated.contains(letter) else {
            throw SettingsError.invalid("Choose an unused app letter other than the overflow key.")
        }
        assigned[id] = letter; allocated.insert(letter)
    }
    public mutating func retain(live: Set<TargetID>) {
        for (id, code) in assigned where !live.contains(id) { held[id] = code }
        assigned = assigned.filter { live.contains($0.key) }
    }
    public var assignments: [TargetID: String] { assigned }
    public var allocatedCount: Int { allocated.count }

}

public struct CatalogueSnapshot: Sendable, Equatable {
    public var suppressedIDs: Set<TargetID> = []
    public var revision: UInt64
    public var windows: [Target]
    public var apps: [Target]
    public var tabs: [Target]
    public var alphabet: String
    public var allocated: Set<String>
    public var history: FocusHistory
    public init(revision: UInt64 = 0, windows: [Target] = [], apps: [Target] = [], alphabet: String = AddressBook.rightHand,
                allocated: Set<String> = [], tabs: [Target] = [], history: FocusHistory = .init()) {
        self.revision = revision; self.windows = windows; self.apps = apps
        self.tabs = tabs; self.alphabet = alphabet; self.allocated = allocated; self.history = history
    }
}
public enum SelectionKey: Equatable, Sendable {
    case navigate(Int), highlight(NavigationAction), letter(String), escape, dismiss, backspace, next, previous, enter, prefix(String), beginSearch, query(String)
    /// Left (-1) or right (+1) arrow. Its meaning follows the mode's layout.
    case lateral(Int)
}
internal final class DerivedMemo: Sendable {
    struct Values { var navigationItems: [NavigationItem]?; var displayMatches: [Target]?; var displayTargets: [Target]? }
    let values = Mutex(Values())
}
/// Always equal: it only caches values derived from fields that equality already compares.
internal struct DerivedCache: Equatable, Sendable {
    let memo = DerivedMemo()
    static func == (_: Self, _: Self) -> Bool { true }
}
public enum SelectionEffect: Equatable, Sendable { case none, changed, cancelled, selected(TargetID) }
public struct SelectionState: Equatable, Sendable {
    public private(set) var active = false { didSet { derived = .init() } }
    public private(set) var prefix = "" { didSet { derived = .init() } }
    public private(set) var cursor = 0
    public private(set) var pointerFocus: NavigationAction?
    public private(set) var mode: DisplayMode = .shore { didSet { derived = .init() } }
    public private(set) var query: String? { didSet { derived = .init() } }
    /// Acknowledges native search edits even when publications coalesce or text repeats.
    public private(set) var queryRevision: UInt64 = 0
    public private(set) var snapshot = CatalogueSnapshot() { didSet { derived = .init() } }
    public init() {}
    public private(set) var ordering: TraversalOrder = .stable { didSet { derived = .init() } }
    public private(set) var openingHistory = FocusHistory() { didSet { derived = .init() } }
    /// Return, preview and group selection share the history captured on opening.
    public var focusHistory: FocusHistory { active ? openingHistory : snapshot.history }
    private var targetRanks: [TargetID: Int] = [:]
    internal var ownerRanks: [UUID: Int] = [:] { didSet { derived = .init() } }
    internal var cellRanks: [String: Int] = [:] { didSet { derived = .init() } }
    /// Memoized presentation/navigation lists. Every stored input they read resets it on
    /// write (cursor and pointer focus are not inputs), so a copy that diverges gets a fresh
    /// memo and never reads another state's results; identical copies may share one.
    internal var derived = DerivedCache()
    internal func memoized<T: Sendable>(_ key: WritableKeyPath<DerivedMemo.Values, T?>, _ compute: () -> T) -> T {
        if let cached = derived.memo.values.withLock({ $0[keyPath: key] }) { return cached }
        // Computed outside the lock: navigationItems itself reads memoized displayMatches.
        let value = compute()
        derived.memo.values.withLock { $0[keyPath: key] = value }
        return value
    }
    public mutating func configure(ordering: TraversalOrder) {
        guard !active else { return } // Settings take effect on the next opening.
        self.ordering = ordering
    }
    private mutating func captureOrder() {
        targets = ordering.sorted(Self.leaves(snapshot, mode: mode), history: snapshot.history)
        targetRanks = Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($1.id, $0) })
        let childOwners = Set(targets.filter { $0.id.window != nil }.map(\.groupOwner))
        let owners = ordering == .stable ? (mode == .fold ? snapshot.apps : targets)
            : targets.filter { $0.id.window != nil || !childOwners.contains($0.groupOwner) }
        ownerRanks = Dictionary(owners.enumerated().map { ($1.groupOwner, $0) }, uniquingKeysWith: { first, _ in first })
        // Freeze every address branch, including shared overflow branches. Removing a
        // child later cannot move a branch ahead of a different app or address.
        let grouped = appGroupedOrder(targets)
        let ranks = Dictionary(uniqueKeysWithValues: grouped.enumerated().map { ($1.id, $0) })
        cellRanks = [:]
        var branchOwners: [String: UUID] = [:], shared = Set<String>()
        for target in targets where target.isRunning && !target.address.isEmpty {
            for depth in 1...target.address.count {
                let code = String(target.address.prefix(depth))
                if let owner = branchOwners[code], owner != target.groupOwner { shared.insert(code) }
                else { branchOwners[code] = target.groupOwner }
                cellRanks[code] = min(cellRanks[code] ?? .max, ranks[target.id] ?? .max)
            }
        }
        for code in shared { cellRanks[code] = Int.max }

    }
    /// Fold and Canopy nest tabs under their owning app, so apps stay containers rather
    /// than addressable leaves there; every other mode is one flat, mixed pool.
    private static func leaves(_ snapshot: CatalogueSnapshot, mode: DisplayMode) -> [Target] {
        let base = (mode == .fold || mode == .canopy)
            ? snapshot.windows + snapshot.tabs + snapshot.apps.filter { !$0.isRunning }
            : snapshot.windows + snapshot.tabs + snapshot.apps
        guard mode == .fold || mode == .canopy else { return base }
        return base.map { target in var t = target; t.address = t.foldAddress; return t }
    }
    /// Derived from `snapshot` and `mode` only. Stored because nearly every accessor and the
    /// presenter read it several times per keystroke; both writers below keep it current.
    public private(set) var targets: [Target] = [] { didSet { derived = .init() } }
    public var matches: [Target] {
        if query != nil { return searchMatches }
        if mode == .fold, let family = foldFamily {
            return targets.filter { ($0.groupOwner) == family.id.process && ($0.address.isEmpty || $0.address.hasPrefix(prefix)) }
        }
        return targets.filter { $0.address.hasPrefix(prefix) }
    }
    /// A closed assigned app stays a real, addressable target — its letter still opens it —
    /// but it has no window of its own, so the switcher never draws a tile for it until it
    /// actually runs. These are what a presenter should draw in place of `targets`/`matches`.
    public var displayTargets: [Target] { memoized(\.displayTargets) { computeDisplayTargets() } }
    private func computeDisplayTargets() -> [Target] {
        let visible = targets.filter(\.isRunning)
        if mode == .relay && ordering == .stable { return relayOrder(visible) }
        return [.shore, .lattice, .canopy].contains(mode) ? appGroupedOrder(visible) : visible
    }
    public var displayMatches: [Target] { memoized(\.displayMatches) { computeDisplayMatches() } }
    private func computeDisplayMatches() -> [Target] {
        let visible = matches.filter(\.isRunning)
        if query != nil {
            if hasSearchTerms { return [.shore, .canopy, .lattice, .fold].contains(mode) ? Self.groupedByOwner(visible) : visible }
            if mode == .fold {
                return Self.groupedByOwner(visible, rank: ownerRanks)
            }
            if [.shore, .canopy, .lattice].contains(mode) { return appGroupedOrder(visible) }
        }
        if query == nil, mode == .relay && ordering == .stable { return relayOrder(visible) }
        return [.shore, .lattice, .canopy].contains(mode) ? appGroupedOrder(visible) : visible
    }
    public private(set) var searchMemory: SearchMemory?
    private var searchMatches: [Target] = [] { didSet { derived = .init() } }
    /// Every non-nil query assignment refreshes search, which keeps this current.
    private var queryHasTerms = false { didSet { derived = .init() } }
    public var hasSearchTerms: Bool { query != nil && queryHasTerms }
    public mutating func configureSearch(memory: SearchMemory?) {
        searchMemory = memory; refreshSearch()
    }
    private mutating func refreshSearch() {
        guard let query else { searchMatches = []; queryHasTerms = false; return }
        let terms = SearchText.terms(query).map(SearchTerm.init)
        queryHasTerms = !terms.isEmpty
        guard !terms.isEmpty else { searchMatches = targets; return }
        // Stable ties follow catalogue group order in grouped layouts.
        let base = [.shore, .canopy, .lattice, .fold].contains(mode) ? appGroupedOrder(targets) : targets
        let bonuses = searchMemory?.bonuses(query: query, targets: base) ?? [:]
        searchMatches = base.enumerated().compactMap { index, target -> (Int, Int, Target)? in
            guard let score = target.searchScore(terms) else { return nil }
            return (score + (bonuses[target.id] ?? 0), index, target)
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.map { $0.2 }
    }
    public var returnTarget: Target? { targets.first { $0.id == focusHistory.previous && $0.available } }
    private var navigationCount: Int { navigationItems.count }
    public mutating func configure(mode: DisplayMode) {
        self.mode = mode; ownerRanks = [:]; cellRanks = [:]; targets = Self.leaves(snapshot, mode: mode)
        pointerFocus = nil; prefix = ""; cursor = 0; query = nil
        if active { captureOrder() }
    }
    public mutating func update(_ new: CatalogueSnapshot) {
        let highlighted = highlightedAction
        // Metadata-only updates keep a partially typed address. Churn clears it.
        let leaves = Self.leaves(new, mode: mode)
        let oldMeaning = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.address) })
        let newMeaning = Dictionary(uniqueKeysWithValues: leaves.map { ($0.id, $0.address) })
        if oldMeaning != newMeaning { prefix = ""; cursor = 0 }
        snapshot = new
        targets = active ? leaves.enumerated().sorted {
            (targetRanks[$0.element.id] ?? .max, $0.offset) < (targetRanks[$1.element.id] ?? .max, $1.offset)
        }.map(\.element) : leaves
        refreshSearch()
        // Hoisted: both checks below read navigationItems against the same just-updated
        // snapshot/mode/prefix, so one computation covers both (a third, earlier read for
        // `highlighted` above uses the pre-update snapshot and must stay separate).
        let items = navigationItems
        if let pointerFocus, !items.contains(where: { $0.action == pointerFocus }) {
            if case .branch(let code) = pointerFocus, mode == .fold, query == nil,
               foldFamilies.contains(where: { app in app.foldAddress == code && targets.contains(where: { ($0.groupOwner) == app.id.process && $0.available }) }) { }
            else { self.pointerFocus = nil }
        }
        if let highlighted, let index = items.firstIndex(where: { $0.action == highlighted }) { cursor = index } else { cursor = min(cursor, max(0, items.count - 1)) }
    }
    public private(set) var session: UInt64 = 0
    /// Opens on the window used before the current one, like the system switcher, so Enter (or
    /// letting go in hold behavior) returns to it. Capture the chosen presentation order
    /// without changing addresses; the starting highlight still follows recency. Returns whether such a window was found.
    @discardableResult public mutating func open() -> Bool {
        session &+= 1; pointerFocus = nil; prefix = ""; cursor = 0; query = nil
        openingHistory = snapshot.history; captureOrder(); active = true
        let items = navigationItems
        for id in focusHistory.recent {
            guard let target = targets.first(where: { $0.id == id && $0.available }) else { continue }
            let index = items.firstIndex { item in
                switch item.action {
                case .target(let candidate): return candidate == id
                case .branch(let code):
                    if mode == .fold { return snapshot.apps.contains { $0.foldAddress == code && $0.id.process == target.groupOwner } }
                    return target.address.hasPrefix(code)
                }
            }
            if let index { cursor = index; return true }
        }
        return false
    }
    public mutating func cancel() { pointerFocus = nil; active = false; prefix = ""; cursor = 0; query = nil }
    public mutating func select(_ id: TargetID) -> SelectionEffect {
        guard active, let target = targets.first(where: { $0.id == id && $0.available }) else { return .none }
        if let query {
            guard displayMatches.contains(where: { $0.id == id }) else { return .none }
            searchMemory?.remember(query: query, target: target)
        }
        cancel(); return .selected(id)
    }
    /// Letting go of the activation modifiers after cycling switches to the highlight, like
    /// the system switcher. A highlighted group stands for its most recently used member
    /// other than the current window, or its first listed member when none was observed.
    public mutating func commitHighlight() -> SelectionEffect {
        guard active, query == nil, let action = highlightedAction else { return .none }
        switch action {
        case .target(let id): return select(id)
        case .branch(let code):
            // Fold lists an app's windows by owner; Lattice lists a cell's by address.
            let family = mode == .fold ? snapshot.apps.first { $0.foldAddress == code } : nil
            let members = family.map { app in targets.filter { $0.groupOwner == app.id.process } } ?? targets.filter { $0.address.hasPrefix(code) }
            let usable = members.filter(\.available)
            let recent = focusHistory.recent.lazy.compactMap { id in usable.first { $0.id == id } }.first
            return (recent ?? usable.first).map { select($0.id) } ?? .none
        }
    }
    /// Arrow keys across the layout: Fold steps into and out of an app, Canopy moves between
    /// app columns, and the grid-like modes read left to right. A plain list ignores them.
    private mutating func moveLateral(_ direction: Int) -> SelectionEffect {
        guard query == nil, direction != 0 else { return .none }
        switch mode {
        case .shore: return .none
        case .fold:
            if direction > 0 {
                guard case .branch(let code)? = highlightedAction else { return .none }
                pointerFocus = nil; prefix = code; cursor = 0; return .changed
            }
            guard let family = foldFamily else { return .none }
            pointerFocus = nil; prefix = ""
            cursor = navigationItems.firstIndex { $0.action == .branch(family.foldAddress) } ?? 0
            return .changed
        case .canopy:
            let sizes = navigationGroupSizes
            var start = 0, group = 0
            while group < sizes.count, cursor >= start + sizes[group] { start += sizes[group]; group += 1 }
            guard group < sizes.count else { return .none }
            let destination = max(0, min(sizes.count - 1, group + (direction > 0 ? 1 : -1)))
            guard destination != group else { return .none }
            let offset = cursor - start
            cursor = sizes[..<destination].reduce(0, +) + min(offset, sizes[destination] - 1)
            pointerFocus = nil; return .changed
        case .beacons, .lattice, .relay:
            let count = navigationItems.count
            guard count > 0 else { return .none }
            pointerFocus = nil; cursor = (cursor + (direction > 0 ? 1 : count - 1)) % count; return .changed
        }
    }
    public mutating func handle(_ key: SelectionKey, repeated: Bool = false) -> SelectionEffect {
        guard active else { return .none }
        // Held keys autorepeat; only cycling should act on that, so every other
        // action stays a single shot even while its key is held down.
        if repeated, key != .next, key != .previous { return .none }
        if case .lateral(let direction) = key { return moveLateral(direction) }
        // Captured before the highlight is cleared below: Fold's left list keeps an app
        // highlighted (by cursor or hover) without committing it to `prefix`, so a typed
        // letter should first be tried as that app's second keystroke — the head is
        // "assumed" from the highlight instead of needing its own keypress.
        let impliedFoldHead: String? = {
            guard mode == .fold, prefix.isEmpty, case .branch(let code)? = highlightedAction else { return nil }
            return code
        }()
        switch key { case .highlight, .enter: break; default: pointerFocus = nil }
        switch key {
        case .highlight(let action):
            guard let index = navigationItems.firstIndex(where: { $0.action == action }) else {
                if mode == .fold, query == nil, case .branch(let code) = action, foldFamilies.contains(where:{$0.foldAddress == code}) {
                    if pointerFocus == action { return .none }
                    pointerFocus = action; return .changed
                }
                return .none
            }
            // Hover re-reports the row it is already on; that must not cost a full re-render.
            if pointerFocus == nil, cursor == index { return .none }
            pointerFocus = nil; cursor = index; return .changed
        case .lateral: return .none // Handled above.
        case .navigate(let steps): cursor = max(0,min(max(0,navigationCount-1),cursor+steps)); return .changed
        case .dismiss: cancel(); return .cancelled
        case .beginSearch: query = ""; prefix = ""; cursor = 0; refreshSearch(); return .changed
        case .query(let value): guard query != nil else { return .none }; queryRevision &+= 1; query = String(value.prefix(1024)); cursor = 0; refreshSearch(); return .changed
        case .prefix(let value):
            if mode == .fold, query == nil,
               let exact = targets.first(where: { $0.address == value && $0.available }) {
                return select(exact.id)
            }
            guard query == nil, targets.contains(where: { $0.address.hasPrefix(value) && $0.address != value }) else { return .none }
            prefix = value; cursor = 0; return .changed
        case .escape:
            if query != nil { query = nil; prefix = ""; cursor = 0; return .changed }
            if !prefix.isEmpty { prefix = ""; cursor = 0; return .changed }
            cancel(); return .cancelled
        case .backspace: if !prefix.isEmpty { prefix.removeLast(); cursor = 0 }; return .changed
        case .next: let count = navigationCount; if count > 0 { cursor = (cursor + 1) % count }; return .changed
        case .previous: let count = navigationCount; if count > 0 { cursor = (cursor + count - 1) % count }; return .changed
        case .enter:
            if mode == .relay && query == nil { return returnTarget.map { select($0.id) } ?? .none }
            guard let action = highlightedAction else { return .none }
            switch action { case .target(let id): return select(id); case .branch(let code): pointerFocus = nil; prefix = code; cursor = 0; return .changed }
        case .letter(let letter):
            guard query == nil else { return .none }
            guard letter.utf8.count == 1, let b = letter.utf8.first, (97...122).contains(b) else { return .none }
            if let impliedFoldHead {
                let implied = impliedFoldHead + letter
                let impliedFound = targets.filter { $0.address.hasPrefix(implied) }
                if let exact = impliedFound.first(where: { $0.address == implied }) { return select(exact.id) }
                if !impliedFound.isEmpty { prefix = implied; cursor = 0; return .changed }
            }
            let candidate = prefix + letter
            let found = targets.filter { $0.address.hasPrefix(candidate) }
            guard !found.isEmpty else { return .none }
            if let exact = found.first(where: { $0.address == candidate }) { return select(exact.id) }
            // A singleton app's only window shares its family's whole subtree; typing just
            // the app's head letter already uniquely identifies it, so it can select directly
            // instead of forcing a second, redundant keystroke. Multi-window apps are
            // unaffected: `found` still has more than one member and falls through as before.
            if mode == .fold, prefix.isEmpty, found.count == 1, found[0].available,
               snapshot.apps.contains(where: { $0.foldAddress == candidate }) {
                return select(found[0].id)
            }
            prefix = candidate; cursor = 0; return .changed
        }
    }
}

/// Only exact foreground-window observations feed history, never requests or UI navigation.
public struct FocusHistory: Equatable, Sendable {
    public static let depth = 32
    public private(set) var current: TargetID?
    /// Windows used before `current`, most recent first. Never contains `current`. Closing the
    /// previous window leaves the one before it as the place to return to.
    public private(set) var recent: [TargetID] = []
    public var previous: TargetID? { recent.first }
    public init() {}
    public mutating func observe(_ id: TargetID) {
        guard id.window != nil, id != current else { return }
        recent.removeAll { $0 == id }
        if let current { recent.insert(current, at: 0) }
        if recent.count > Self.depth { recent.removeLast(recent.count - Self.depth) }
        current = id
    }
    public mutating func retain(live: Set<TargetID>) {
        if let current, !live.contains(current) { self.current = nil }
        recent.removeAll { !live.contains($0) }
    }
}

public struct AddressCell: Equatable, Sendable {
    public let address: String
    public let target: Target?
    public let descendants: [Target]
    public let held: Bool
}
public extension SelectionState {
    var foldFamilies: [Target] {
        // Hoisted so targets/foldFamily (each an O(n) scan) aren't rebuilt on every app in the filter.
        let processes = Set(targets.map { $0.groupOwner }), currentFamily = foldFamily
        return snapshot.apps.enumerated().filter { _, app in processes.contains(app.id.process) && (currentFamily != nil || app.foldAddress.hasPrefix(prefix) || prefix.hasPrefix(app.foldAddress)) }
            .sorted { (ownerRanks[$0.element.id.process] ?? .max, $0.offset) < (ownerRanks[$1.element.id.process] ?? .max, $1.offset) }.map(\.element)
    }
    var foldFamily: Target? { snapshot.apps.first { !$0.foldAddress.isEmpty && prefix.hasPrefix($0.foldAddress) } }
    var latticeCells: [AddressCell] {
        let allocations = snapshot.allocated
        let extra = Set(allocations.compactMap(\.first)).subtracting(Set(snapshot.alphabet)).sorted()
        // Hoisted so targets (an O(n) scan) isn't rebuilt once per alphabet letter.
        // Closed assigned apps are actionable launcher targets too. Keep their cells
        // so click, arrows and Enter agree with direct letter selection.
        let currentTargets = targets
        // Bucket by the letter after `prefix` in one pass instead of rescanning every
        // target and allocation per cell. Addresses are ASCII, so this matches hasPrefix.
        var children: [Character: [Target]] = [:], heldLetters = Set<Character>()
        for target in currentTargets where target.address.hasPrefix(prefix) {
            if let letter = target.address.dropFirst(prefix.count).first { children[letter, default: []].append(target) }
        }
        for code in allocations where code.hasPrefix(prefix) {
            if let letter = code.dropFirst(prefix.count).first { heldLetters.insert(letter) }
        }
        let all = (Array(snapshot.alphabet) + extra).map { letter -> AddressCell in
            let address = prefix + String(letter), members = children[letter] ?? []
            return AddressCell(address: address, target: members.first { $0.address == address },
                               descendants: members.filter { $0.address != address }, held: heldLetters.contains(letter))
        }
        // Trim trailing empty cells so a handful of live targets doesn't render a full
        // alphabet grid of "Unassigned" placeholders. Keep held addresses and a small
        // minimum, then arrange occupied cells by app without changing their addresses.
        let minimumCells = 6
        let lastLive = all.lastIndex { $0.target != nil || $0.held || !$0.descendants.isEmpty }
        let needed = max(minimumCells, (lastLive.map { $0 + 1 }) ?? 0)
        let cells = Array(all.prefix(min(needed, all.count)))
        let ordered = appGroupedOrder(currentTargets)
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        func position(_ cell: AddressCell) -> Int {
            if active { return cellRanks[cell.address] ?? .max }
            if let target = cell.target, target.isRunning { return rank[target.id] ?? .max }
            let live = cell.descendants.filter(\.isRunning)
            // An overflow branch belonging to one app stays with that app. Shared
            // branches and empty/held slots follow the app groups in alphabet order.
            guard let first = live.first, live.allSatisfy({ $0.groupOwner == first.groupOwner }) else { return .max }
            return live.compactMap { rank[$0.id] }.min() ?? .max
        }
        return cells.enumerated().map { (cell:$0.element, rank:position($0.element), index:$0.offset) }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.cell)
    }
}

/// Tracks complete key pairs across selection, cancellation, and autorepeat.
/// A final keyup remains owned even after the overlay has already closed.
public struct KeyOwnership: Sendable {
    private var owned = Set<UInt16>()
    public init() {}
    public mutating func claim(_ code: UInt16) { owned.insert(code) }
    public func contains(_ code: UInt16) -> Bool { owned.contains(code) }
    public mutating func release(_ code: UInt16) -> Bool { owned.remove(code) != nil }
    public mutating func reset() { owned.removeAll() }
}

public extension SelectionState {
    /// True when `other` would draw the same switcher. `revision` advances on every catalogue
    /// publish, including ones that changed nothing a view reads, so it is left out here.
    func rendersSame(as other: Self) -> Bool {
        active == other.active && session == other.session && mode == other.mode && prefix == other.prefix
            && cursor == other.cursor && pointerFocus == other.pointerFocus && query == other.query
            && ordering == other.ordering && focusHistory == other.focusHistory && snapshot.alphabet == other.snapshot.alphabet
            && snapshot.allocated == other.snapshot.allocated && targets == other.targets && snapshot.apps == other.snapshot.apps
    }
}

public extension CatalogueSnapshot {
    /// Browser connections have separate identities; grouped layouts need the actual
    /// app owner in both the live switcher and the settings preview.
    func resolvingTabOwners() -> Self {
        let owners = Dictionary(apps.compactMap { app in
            app.bundleID.isEmpty ? nil : (app.bundleID, app.id.process)
        }, uniquingKeysWith: { first, _ in first })
        var result = self
        result.tabs = tabs.map { tab in
            var tab = tab; tab.owner = owners[tab.bundleID] ?? tab.owner; return tab
        }
        return result
    }
    /// An open session admits no new identity or new meaning for a learned code.
    /// Liveness/metadata may change; closed targets become unavailable until reopen.
    func reconcilingLive(_ latest: Self) -> Self {
        func reconcile(_ old:[Target],_ new:[Target]) -> [Target] {
            let live = Dictionary(uniqueKeysWithValues:new.map { ($0.id,$0) })
            return old.filter { !latest.suppressedIDs.contains($0.id) }.map { target in
                guard var updated = live[target.id], updated.address == target.address, updated.foldAddress == target.foldAddress else {
                    var unavailable = target; unavailable.available = false; return unavailable
                }
                updated.address = target.address; updated.foldAddress = target.foldAddress; return updated
            }
        }
        var result = self
        result.suppressedIDs = latest.suppressedIDs
        result.revision = latest.revision; result.windows = reconcile(windows,latest.windows)
        result.apps = reconcile(apps,latest.apps); result.tabs = reconcile(tabs,latest.tabs); result.history = latest.history
        return result
    }
}
