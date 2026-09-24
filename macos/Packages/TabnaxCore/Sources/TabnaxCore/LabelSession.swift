import Foundation

public enum LabelNamespace: String, Sendable { case pool, fold }

/// Runtime-only labels: copying this value is a transaction/Undo checkpoint.
/// Filter after mapping so hidden/excluded live identities retain reservations.
public struct LabelSession: Sendable {
    public private(set) var selection: SelectionPreferences
    /// Windows, tabs, and apps all draw addresses from this one book, so nothing
    /// visible together can ever collide on the same label.
    public private(set) var pool: AddressBook
    /// Fold/Canopy app head letters live in their own book, separate from `pool`, so a
    /// handful of apps never gets crowded out of single-letter addresses by windows/tabs,
    /// and so an app's own initial (the alphabet's last letter included) is never
    /// foreclosed by `pool`'s prefix-free overflow reservation. Fixed app letters are
    /// reserved in both books before either allocates any automatic addresses.
    private var heads: AddressBook
    private var children: [UUID: AddressBook] = [:]
    /// Flat (non-Fold) pins for a window/tab whose app has a fixed letter are anchored
    /// to that letter, so they read the same as the app's Fold address. Per-owner books
    /// hold just the suffix, mirroring `children`'s role for Fold.
    private var flatChildren: [UUID: AddressBook] = [:]
    private var appHeads: [UUID: String] = [:]
    private var fixedOwners: [String: TargetID] = [:]
    /// Cached owner (real app process) per window/tab id, refreshed every map(), so
    /// pin(_:fold:) can resolve a tab's Fold family without needing a fresh snapshot.
    private var owners: [TargetID: UUID] = [:]
    public private(set) var pins: [TargetID: String] = [:]
    public private(set) var foldPins: [TargetID: String] = [:]
    /// `.stable`/`.mnemonic` vocabularies reserve their alphabet's last letter as a
    /// multi-depth overflow marker so every address stays prefix-free; extending the
    /// alphabet with a hidden filler (see `AddressBook.extended(_:)`) shifts that
    /// reservation onto the filler instead, freeing every real letter — including the
    /// base alphabet's own last one — as a fixed app letter or single-letter address.
    /// `.pairs` has no such marker (every letter already prefixes a real two-letter
    /// address), so it's left untouched.
    private static func poolAlphabet(_ base: String, policy: AssignmentPolicy) -> String {
        policy == .pairs ? base : AddressBook.extended(base)
    }
    public init(selection: SelectionPreferences = .init()) {
        self.selection = selection
        pool = try! AddressBook(alphabet:Self.poolAlphabet(selection.alphabet,policy:selection.policy),policy:selection.policy)
        let reserved = selection.appShortcuts.enabled ? Set(selection.appShortcuts.assignments.map(\.letter)) : []
        heads = try! AddressBook(alphabet:AddressBook.extended(selection.alphabet,excluding:reserved),policy:.mnemonic)
        if selection.appShortcuts.enabled {
            for app in selection.appShortcuts.assignments {
                try? pool.reserveApp(app.targetID,letter:app.letter)
                try? heads.reserveApp(app.targetID,letter:app.letter)
            }
        }
    }
    public mutating func map(_ source: CatalogueSnapshot) -> CatalogueSnapshot {
        var result = source
        result.alphabet = selection.alphabet
        var appIdentities: [TargetID: TargetID] = [:]
        var currentFixedOwners: [String: TargetID] = [:]
        if selection.appShortcuts.enabled {
            // Hoisted so each assignment looks its apps up by key instead of scanning all apps.
            let appsByBundleID = Dictionary(grouping: source.apps, by: \.bundleID)
            for assignment in selection.appShortcuts.assignments {
                let matches = appsByBundleID[assignment.bundleID] ?? []
                let owner = matches.first { $0.id == fixedOwners[assignment.bundleID] }
                    ?? matches.sorted { $0.id.process.uuidString < $1.id.process.uuidString }.first
                currentFixedOwners[assignment.bundleID] = owner?.id
                if let owner { appIdentities[owner.id] = assignment.targetID }
            }
        }
        fixedOwners = currentFixedOwners
        // Windows and tabs are the primary destinations in flat layouts. Give them
        // first choice of name-based letters before app rows consume those initials.
        // Explicit app letters are already reserved by init and still take priority.
        result.windows = source.windows.map { t in
            var t = t; t.address = (try? pool.address(for:t.id,name:t.app + " " + t.title)) ?? ""; return t
        }
        result.tabs = source.tabs.map { t in
            var t = t; t.address = (try? pool.address(for:t.id,name:t.app + " " + t.title)) ?? ""; return t
        }
        result.apps = source.apps.map { t in
            var t = t
            let identity = appIdentities[t.id] ?? t.id
            t.address = (try? pool.address(for:identity,name:t.app)) ?? ""; return t
        }
        // Apps with a manually-fixed shortcut letter keep that exact letter as their Fold
        // head too, so it reads the same everywhere; every other app's head comes from the
        // dedicated `heads` book instead of the flat pool address, so a handful of apps is
        // never crowded into multi-letter codes by however many windows/tabs are open.
        let fixedIdentities = Set(appIdentities.values)
        let childCounts = Dictionary(grouping: source.windows + source.tabs, by: { $0.groupOwner }).mapValues(\.count)
        // An app with nothing to switch to never appears in Fold/Canopy, so it takes no head
        // until it does: otherwise running-but-windowless apps quietly use up the single
        // letters (and the initials) that the apps actually on screen would have had.
        appHeads = Dictionary(uniqueKeysWithValues:result.apps.map { app in
            let identity = appIdentities[app.id] ?? app.id
            if fixedIdentities.contains(identity) { return (app.id.process, app.address) }
            guard childCounts[app.id.process] != nil || heads.assignments[app.id] != nil else { return (app.id.process, "") }
            return (app.id.process, (try? heads.address(for:app.id,name:app.app)) ?? "")
        })
        // Fold/Canopy's own family screen keys off an app's head letter, which now differs
        // from its flat `address` for most apps, so publish it via `foldAddress` (unused by
        // apps otherwise) instead of leaving callers to reach into `appHeads` themselves.
        result.apps = result.apps.map { app in var app = app; app.foldAddress = appHeads[app.id.process] ?? ""; return app }
        // A singleton app's only window/tab needs no disambiguating second keystroke: its
        // head letter alone already identifies it uniquely, so the child suffix is hidden
        // (though still reserved below, so it reappears seamlessly if a sibling shows up).
        func withFold(_ target: Target) -> Target {
            var t = target
            let owner = t.groupOwner
            // Mnemonic, like `heads`, regardless of `selection.policy`: a window's Fold
            // suffix should read from its own title whenever a free letter allows it.
            if children[owner] == nil { children[owner] = try! AddressBook(alphabet:selection.alphabet,policy:.mnemonic) }
            let head = appHeads[owner] ?? ""
            let child = (try? children[owner]!.address(for:t.id,name:t.title)) ?? ""
            let onlyChild = (childCounts[owner] ?? 0) <= 1
            t.foldAddress = head.isEmpty || child.isEmpty ? "" : (onlyChild ? head : head + child)
            return t
        }
        func withFlatPin(_ target: Target) -> Target {
            var t = target
            let owner = t.groupOwner
            guard let head = appHeads[owner], !head.isEmpty, let suffix = flatChildren[owner]?.assignments[t.id] else { return t }
            t.address = head + suffix; return t
        }
        result.windows = result.windows.map { withFold(withFlatPin($0)) }
        result.tabs = result.tabs.map { withFold(withFlatPin($0)) }
        // Hoisted once and reused below instead of reconcatenating windows+tabs per owner/pin check.
        let combined = source.windows + source.tabs
        owners = Dictionary(uniqueKeysWithValues: combined.map { ($0.id, $0.groupOwner) })
        let combinedIDs = Set(owners.keys)
        let reserved = selection.appShortcuts.enabled ? selection.appShortcuts.assignments.map(\.targetID) : []
        pool.retain(live:Set(source.windows.map(\.id) + source.tabs.map(\.id) + source.apps.map { appIdentities[$0.id] ?? $0.id } + reserved))
        heads.retain(live:Set(source.apps.filter { !fixedIdentities.contains(appIdentities[$0.id] ?? $0.id) }.map(\.id) + reserved))
        let liveOwners = Set(source.apps.map(\.id.process))
        for owner in children.keys {
            if !liveOwners.contains(owner) { children[owner] = nil }
            else { children[owner]?.retain(live:Set(combined.filter { $0.groupOwner == owner }.map(\.id))) }
        }
        for owner in flatChildren.keys {
            if !liveOwners.contains(owner) { flatChildren[owner] = nil }
            else { flatChildren[owner]?.retain(live:Set(combined.filter { $0.groupOwner == owner }.map(\.id))) }
        }
        pins = pins.filter { id,_ in combinedIDs.contains(id) }
        foldPins = foldPins.filter { id,_ in combinedIDs.contains(id) }
        result.allocated = pool.allocated
        return result
    }
    public func changing(to proposed: SelectionPreferences, source: CatalogueSnapshot, reset: Bool = false) throws -> Self {
        _ = try AddressBook(alphabet:proposed.alphabet)
        try proposed.appShortcuts.validate(alphabet:proposed.alphabet,policy:proposed.policy)
        var candidate = self
        let shortcutsChanged = proposed.appShortcuts.enabled != selection.appShortcuts.enabled || proposed.appShortcuts.assignments != selection.appShortcuts.assignments
        if reset || proposed.alphabet != selection.alphabet { candidate = Self(selection:proposed); candidate.fixedOwners = fixedOwners }
        else if proposed.policy != selection.policy || shortcutsChanged {
            let fresh = Self(selection:proposed)
            candidate.pool = fresh.pool
            // A newly fixed letter can already belong to an automatic Fold/Canopy head.
            // Rebuild that cache on assignment changes, reserving fixed letters first.
            // Ordinary catalogue updates and launching toggles keep the cached books.
            if shortcutsChanged { candidate.heads = fresh.heads }
        }
        candidate.selection = proposed
        // A flat pin anchored to an app letter (see flatChildren) can't be re-pinned into
        // `pool` as-is: its code isn't a plain pool vocabulary entry.
        func flatAppHead(for id: TargetID) -> String? {
            let owner = owners[id] ?? id.process
            guard let head = appHeads[owner], !head.isEmpty, flatChildren[owner]?.assignments[id] != nil else { return nil }
            return head
        }
        if !reset {
            if proposed.alphabet != selection.alphabet || proposed.policy != selection.policy || shortcutsChanged {
                for (id,code) in pins where flatAppHead(for:id) == nil { try candidate.pool.pin(id,to:code) }
                candidate.pins = pins
            }
            if proposed.alphabet != selection.alphabet {
                // Preserve full Fold pins by reserving each app head before children.
                for (id,code) in foldPins {
                    let owner = owners[id] ?? id.process
                    let oldHead = appHeads[owner] ?? ""
                    guard !oldHead.isEmpty, code.hasPrefix(oldHead) else { throw SettingsError.invalid("A Fold pin no longer has a valid app address.") }
                    let app = source.apps.first { $0.id.process == owner }
                    let fixedIdentity = app.flatMap { app -> TargetID? in
                        guard fixedOwners[app.bundleID] == app.id else { return nil }
                        return proposed.appShortcuts.assignment(for:app)?.targetID
                    }
                    if let fixedIdentity {
                        if candidate.pool.assignments[fixedIdentity] != oldHead { try candidate.pool.pin(fixedIdentity,to:oldHead) }
                    } else {
                        // Ordinary (non-shortcut) apps now get their head letter from the
                        // dedicated `heads` book, not `pool`, so reserve it there instead.
                        let identity = app?.id ?? TargetID(process:owner)
                        if candidate.heads.assignments[identity] != oldHead { try candidate.heads.pin(identity,to:oldHead) }
                    }
                    if candidate.children[owner] == nil { candidate.children[owner] = try AddressBook(alphabet:proposed.alphabet,policy:.mnemonic) }
                    try candidate.children[owner]!.pin(id,to:String(code.dropFirst(oldHead.count)))
                }
                candidate.foldPins = foldPins
                // Preserve app-anchored flat pins the same way, reusing the same app head.
                for (id,code) in pins {
                    let owner = owners[id] ?? id.process
                    guard let oldHead = flatAppHead(for:id) else { continue }
                    guard code.hasPrefix(oldHead) else { throw SettingsError.invalid("A flat pin no longer has a valid app letter.") }
                    let app = source.apps.first { $0.id.process == owner }
                    let identity = app.flatMap { app -> TargetID? in
                        guard fixedOwners[app.bundleID] == app.id else { return nil }
                        return proposed.appShortcuts.assignment(for:app)?.targetID
                    } ?? TargetID(process:owner)
                    if candidate.pool.assignments[identity] != oldHead { try candidate.pool.pin(identity,to:oldHead) }
                    if candidate.flatChildren[owner] == nil { candidate.flatChildren[owner] = try AddressBook(alphabet:proposed.alphabet) }
                    try candidate.flatChildren[owner]!.pin(id,to:String(code.dropFirst(oldHead.count)))
                }
            }
        }
        _ = candidate.map(source)
        if !reset {
            for (id,_) in foldPins where source.windows.contains(where: { $0.id == id }) || source.tabs.contains(where: { $0.id == id }) {
                let owner = owners[id] ?? id.process
                guard candidate.appHeads[owner] == appHeads[owner] else {
                    throw SettingsError.invalid("An app letter conflicts with a Fold window pin. Reset Fold assignments first.")
                }
            }
            for (id,_) in pins where flatAppHead(for:id) != nil && (source.windows.contains(where: { $0.id == id }) || source.tabs.contains(where: { $0.id == id })) {
                let owner = owners[id] ?? id.process
                guard candidate.appHeads[owner] == appHeads[owner] else {
                    throw SettingsError.invalid("An app letter conflicts with a flat window pin. Reset assignments first.")
                }
            }
        }
        return candidate
    }
    public mutating func pin(_ id: TargetID, code: String, fold: Bool = false) throws {
        if fold {
            let owner = owners[id] ?? id.process
            guard !(appHeads[owner] ?? "").isEmpty, code.hasPrefix(appHeads[owner] ?? ""), children[owner] != nil else {
                throw SettingsError.invalid("Keep this window’s app prefix when pinning its Fold label.")
            }
            try children[owner]!.pin(id,to:String(code.dropFirst((appHeads[owner] ?? "").count))); foldPins[id] = code
        } else {
            let owner = owners[id] ?? id.process
            // A window/tab whose app has a fixed letter keeps that letter in every flat
            // pin too, so its pin reads the same as its Fold address.
            if fixedOwners.values.contains(where: { $0.process == owner }), let head = appHeads[owner], !head.isEmpty {
                guard code.hasPrefix(head) else { throw SettingsError.invalid("Keep this window’s app letter when pinning.") }
                if flatChildren[owner] == nil { flatChildren[owner] = try AddressBook(alphabet:selection.alphabet) }
                try flatChildren[owner]!.pin(id,to:String(code.dropFirst(head.count))); pins[id] = code
            } else { try pool.pin(id,to:code); pins[id] = code }
        }
    }
    public mutating func pin(_ id: TargetID, code: String, namespace: LabelNamespace) throws {
        try pin(id,code:code,fold:namespace == .fold)
    }
    public func resetting(_ namespace: LabelNamespace) -> Self {
        var result = self
        let fresh = Self(selection:selection)
        switch namespace {
        case .pool: result.pool = fresh.pool; result.pins = [:]; result.flatChildren = [:]
        case .fold: result.children = [:]; result.foldPins = [:]; result.heads = fresh.heads
        }
        return result
    }
}
