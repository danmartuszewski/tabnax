import Foundation
import Testing
@testable import TabnaxCore

private func shortcut(_ name: String, _ letter: String) -> AppAssignment {
    .init(bundleID: "test.\(name)", name: name, path: "/Applications/\(name).app", letter: letter)
}
private func appTarget(_ assignment: AppAssignment) -> Target {
    .init(id: .init(process: UUID()), app: assignment.name, title: assignment.name, bundleID: assignment.bundleID)
}
@Test func oldSettingsDecodeWithLauncherDisabledAndAssignmentsRoundTrip() throws {
    var document = SettingsDocument()
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    var selection = try #require(json["selection"] as? [String: Any]); selection.removeValue(forKey: "appShortcuts"); json["selection"] = selection
    let legacy = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy == document)
    document.selection.appShortcuts.enabled = true; document.selection.appShortcuts.launchClosedApps = true
    document.selection.appShortcuts.assignments = [shortcut("Chrome", "c")]
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(document)).validated() == document)
}
@Test func fixedAppReservationsSurviveQuitRelaunchAndDoNotStealWindowLetters() throws {
    let fixed = shortcut("Chrome", "j"), other = shortcut("Other", "k")
    let running = appTarget(fixed), automatic = appTarget(other)
    let window = Target(id: .init(process: running.id.process, window: UUID()), app: fixed.name, title: "Document")
    var selection = SelectionPreferences(); selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [fixed]
    var session = LabelSession(selection: selection)
    let first = session.map(.init(windows: [window], apps: [automatic, running]))
    #expect(first.apps.map(\.address) == ["o", "j"])
    // The window shares the same pool as apps now, so it must land on a third, distinct code.
    let windowAddress = first.windows.first?.address
    #expect(windowAddress != nil && windowAddress != "j" && windowAddress != "o")
    // Chrome has exactly one window, so its Fold address collapses to the app's head
    // letter alone — no second, redundant keystroke needed to reach a singleton.
    #expect(first.windows.first?.foldAddress == "j")
    _ = session.map(.init(apps: [automatic]))
    let newcomer = appTarget(shortcut("New", "l"))
    let relaunched = appTarget(fixed)
    let after = session.map(.init(apps: [automatic, newcomer, relaunched]))
    #expect(after.apps.first { $0.id == relaunched.id }?.address == "j") // Fixed reservation survives relaunch.
    #expect(after.apps.first { $0.id == automatic.id }?.address == "o")
    #expect(after.apps.first { $0.id == newcomer.id }?.address != windowAddress) // Never reissues a held pool code.
    #expect(session.pool.allocated.isSuperset(of: ["j", "o"]))
    var launching = selection; launching.appShortcuts.launchClosedApps = true
    var changed = try session.changing(to: launching, source: .init(apps: [automatic, newcomer, relaunched]))
    let remapped = changed.map(.init(apps: [automatic, newcomer, relaunched]))
    #expect(remapped.apps.first { $0.id == relaunched.id }?.address == "j")
    #expect(remapped.apps.first { $0.id == automatic.id }?.address == "o")
}
@Test func forceAssignmentReallocatesAutomaticOwnerOnlyOnApply() throws {
    let fixed = shortcut("Keyboard", "j"), other = shortcut("Journal", "k")
    let a = appTarget(other), b = appTarget(fixed), source = CatalogueSnapshot(apps: [a,b])
    var session = LabelSession(); #expect(session.map(source).apps.map(\.address) == ["j", "k"])
    var proposed = session.selection; proposed.appShortcuts.enabled = true; proposed.appShortcuts.assignments = [fixed]
    var staged = try session.changing(to: proposed, source: source)
    #expect(session.map(source).apps.map(\.address) == ["j", "k"])
    #expect(staged.map(source).apps.map(\.address) == ["o", "j"])
    proposed.appShortcuts.enabled = false
    var disabled = try staged.changing(to: proposed, source: source)
    #expect(disabled.map(source).apps.map(\.address) == ["j", "k"])
    #expect(disabled.selection.appShortcuts.assignments == [fixed])
}
@Test func rejectDuplicateLettersAppsAndOverflowAndAlphabetConflicts() throws {
    var p = AppShortcutPreferences(); p.enabled = true
    // "z" is outside both alphabets below, so it's the hidden filler each one borrows as
    // its overflow marker (searched from the end of a–z) — the one letter that can't be
    // a fixed app letter. Every letter actually in the alphabet, including its former
    // "last" one ("p"/"c"), is fair game now.
    for assignments in [[shortcut("A","j"),shortcut("B","j")], [shortcut("A","j"),shortcut("A","k")], [shortcut("A","z")], [shortcut("A","jj")]] {
        p.assignments = assignments
        #expect(throws: (any Error).self) { try p.validate(alphabet: "jkluionmhp") }
    }
    p.assignments = [shortcut("Chrome","c")]
    try p.validate(alphabet: "jkluionmhp")
    p.assignments = [shortcut("A","p")]
    try p.validate(alphabet: "jkluionmhp") // Alphabet's own last letter is no longer reserved.
    p.assignments = [shortcut("A","c")]
    try p.validate(alphabet: "asdfgc") // Ditto for this alphabet's last letter.
    p.assignments = [shortcut("A","z")]
    #expect(throws: (any Error).self) { try p.validate(alphabet: "asdfgc") }
}
@Test func fixedLettersOutsideAlphabetWorkInEveryFlatModeAndLatticeNavigation() {
    let fixed = shortcut("Chrome","c")
    var selection = SelectionPreferences(); selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [fixed]
    let target = appTarget(fixed)
    var session = LabelSession(selection: selection); let snapshot = session.map(.init(apps: [target]))
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        if mode == .fold || mode == .canopy {
            // A childless app has nothing to fold or group into, so it isn't navigable there.
            #expect(!state.targets.contains { $0.id == target.id })
        } else {
            #expect(state.navigationItems.contains { $0.action == .target(target.id) })
            #expect(state.handle(.letter("c")) == .selected(target.id))
        }
    }
}
@Test func closedLaunchTargetDoesNotChangeMeaningDuringOpenSession() {
    let fixed = shortcut("Chrome","c")
    let closed = Target(id: fixed.targetID, app: fixed.name, title: fixed.name, address: "c", bundleID: fixed.bundleID, isRunning: false)
    var running = appTarget(fixed); running.address = "c"
    let frozen = CatalogueSnapshot(apps: [closed]).reconcilingLive(.init(apps: [running]))
    #expect(frozen.apps.count == 1); #expect(frozen.apps[0].id == fixed.targetID); #expect(!frozen.apps[0].available)
}
@Test func multipleInstancesOfOneAppNeverShareACompleteLetter() {
    let fixed = shortcut("Chrome","c")
    var selection = SelectionPreferences(); selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [fixed]
    let a = appTarget(fixed), b = appTarget(fixed)
    var session = LabelSession(selection:selection)
    let first = session.map(.init(apps:[a,b]))
    #expect(Set(first.apps.map(\.address)).count == 2)
    let owner = first.apps.first { $0.address == "c" }?.id
    let reordered = session.map(.init(apps:[b,a]))
    #expect(reordered.apps.first { $0.address == "c" }?.id == owner)
}

private func sourceWithWindows(_ apps: [Target]) -> CatalogueSnapshot {
    .init(windows: apps.map { app in
        Target(id: .init(process: app.id.process, window: UUID()), app: app.app,
               title: "Document", bundleID: app.bundleID)
    }, apps: apps)
}

@Test func fixedLettersAreExclusiveAcrossFlatAndGroupedModesWithAllLetters() throws {
    let ghostty = shortcut("Ghostty", "g"), obsidian = shortcut("Obsidian", "o")
    let automatic = [appTarget(shortcut("GarageBand", "g")), appTarget(shortcut("Opera", "o"))]
    let fixed = [appTarget(ghostty), appTarget(obsidian)]
    let source = sourceWithWindows(automatic + fixed)
    var selection = SelectionPreferences(); selection.choose(.all); selection.policy = .mnemonic
    selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [ghostty, obsidian]
    try selection.appShortcuts.validate(alphabet: selection.alphabet, policy: selection.policy)
    var session = LabelSession(selection: selection)
    let mapped = session.map(source)
    #expect(mapped.apps.suffix(2).map(\.address) == ["g", "o"])
    #expect(mapped.apps.suffix(2).map(\.foldAddress) == ["g", "o"])
    #expect(mapped.apps.prefix(2).allSatisfy { !["g", "o"].contains($0.address) && !["g", "o"].contains($0.foldAddress) })
    #expect(Set(mapped.apps.map(\.foldAddress)).count == mapped.apps.count)
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(mapped); state.open()
        let target = mode == .fold || mode == .canopy ? source.windows[2].id : fixed[0].id
        #expect(state.handle(.letter("g")) == .selected(target))
    }
}

@Test func closedAppLettersStayReservedForGroupedWindowsAndTabsUntilRelaunch() {
    let fixed = shortcut("Ghostty", "g")
    let other = appTarget(shortcut("GarageBand", "g"))
    var selection = SelectionPreferences(); selection.choose(.all)
    selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [fixed]
    for launchClosedApps in [false, true] {
        selection.appShortcuts.launchClosedApps = launchClosedApps
        var session = LabelSession(selection: selection)
        // Map once with no app process, as happens while the assigned app is closed.
        _ = session.map(.init())
        var source = sourceWithWindows([other])
        source.tabs = [Target(id: .init(process: UUID(), window: UUID()), app: other.app,
                              title: "Tab", bundleID: other.bundleID, owner: other.id.process)]
        let closed = session.map(source)
        #expect(closed.apps[0].foldAddress != "g")
        #expect(closed.windows.allSatisfy { !$0.foldAddress.hasPrefix("g") })
        #expect(closed.tabs.allSatisfy { !$0.foldAddress.hasPrefix("g") })
        source = sourceWithWindows([other, appTarget(fixed)])
        let relaunched = session.map(source)
        #expect(relaunched.apps[0].foldAddress == closed.apps[0].foldAddress)
        #expect(relaunched.apps[1].address == "g" && relaunched.apps[1].foldAddress == "g")
    }
}

@Test func changingFixedLettersEvictsOldAutomaticHeadsAndReleasesRemovedReservations() throws {
    let other = appTarget(shortcut("GarageBand", "g")), ghostty = appTarget(shortcut("Ghostty", "g"))
    let source = sourceWithWindows([other, ghostty])
    var selection = SelectionPreferences(); selection.choose(.all)
    var session = LabelSession(selection: selection)
    let before = session.map(source)
    #expect(before.apps[0].foldAddress == "g")
    var proposed = selection
    proposed.appShortcuts.enabled = true; proposed.appShortcuts.assignments = [shortcut("Ghostty", "g")]
    var staged = try session.changing(to: proposed, source: source)
    #expect(session.map(source) == before)
    let applied = staged.map(source)
    #expect(applied.apps[0].foldAddress != "g" && applied.apps[1].foldAddress == "g")
    // Unrelated settings and repeated publications must preserve the cached allocations.
    proposed.appShortcuts.launchClosedApps = true
    var launching = try staged.changing(to: proposed, source: source)
    #expect(launching.map(source) == applied)
    proposed.appShortcuts.assignments[0].letter = "p"
    var reassigned = try launching.changing(to: proposed, source: source)
    #expect(reassigned.map(source).apps.map(\.foldAddress) == ["g", "p"])
    proposed.appShortcuts.assignments = []
    var removed = try reassigned.changing(to: proposed, source: source)
    #expect(removed.map(source).apps.map(\.foldAddress) == before.apps.map(\.foldAddress))
    proposed.appShortcuts.assignments = [shortcut("Ghostty", "g")]; proposed.appShortcuts.enabled = false
    var disabled = try staged.changing(to: proposed, source: source)
    #expect(disabled.map(source).apps.map(\.foldAddress) == before.apps.map(\.foldAddress))
    // A disabled assignment must no longer make this app's windows require an app prefix.
    try disabled.pin(source.windows[1].id, code: "y")
    #expect(disabled.map(source).windows[1].address == "y")
}

@Test func labelResetsKeepFixedReservationsInBothNamespaces() {
    let fixed = shortcut("Ghostty", "g")
    let source = sourceWithWindows([appTarget(shortcut("GarageBand", "g")), appTarget(fixed)])
    var selection = SelectionPreferences(); selection.choose(.all); selection.policy = .mnemonic
    selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [fixed]
    var session = LabelSession(selection: selection)
    _ = session.map(source)
    for namespace in [LabelNamespace.pool, .fold] {
        var reset = session.resetting(namespace)
        let mapped = reset.map(source)
        #expect(mapped.apps[1].address == "g" && mapped.apps[1].foldAddress == "g")
        #expect(mapped.apps[0].address != "g" && mapped.apps[0].foldAddress != "g")
        #expect(reset.pool.assignments[fixed.targetID] == "g")
    }
}

@Test func takingAPinnedFoldPrefixRequiresResetAndDoesNotChangeLiveAssignments() throws {
    let source = sourceWithWindows([appTarget(shortcut("GarageBand", "g")), appTarget(shortcut("Ghostty", "g"))])
    var selection = SelectionPreferences(); selection.choose(.all)
    var session = LabelSession(selection: selection)
    _ = session.map(source)
    try session.pin(source.windows[0].id, code: "gx", fold: true)
    let before = session.map(source)
    selection.appShortcuts.enabled = true; selection.appShortcuts.assignments = [shortcut("Ghostty", "g")]
    #expect(throws: (any Error).self) { try session.changing(to: selection, source: source) }
    #expect(session.map(source) == before)
    var reset = try session.resetting(.fold).changing(to: selection, source: source)
    #expect(reset.map(source).apps[0].foldAddress != "g")
}

@Test func fixedLettersOutsidePairAlphabetCannotBecomeAutomaticOverflowPrefixes() throws {
    var selection = SelectionPreferences(); selection.policy = .pairs; selection.appShortcuts.enabled = true
    // Pairs allows every letter outside its alphabet, including the usual overflow filler.
    selection.appShortcuts.assignments = [shortcut("Zen", "z"), shortcut("Yate", "y")]
    try selection.appShortcuts.validate(alphabet:selection.alphabet,policy:selection.policy)
    let automatic = (0..<20).map { appTarget(shortcut("App\($0)", "a")) }
    let source = sourceWithWindows(automatic + selection.appShortcuts.assignments.map(appTarget))
    var session = LabelSession(selection:selection)
    let mapped = session.map(source)
    #expect(mapped.apps.suffix(2).map(\.foldAddress) == ["z", "y"])
    #expect(mapped.apps.prefix(20).contains { $0.foldAddress.count > 1 })
    #expect(mapped.apps.prefix(20).allSatisfy { !$0.foldAddress.isEmpty && !$0.foldAddress.hasPrefix("z") && !$0.foldAddress.hasPrefix("y") })
    #expect(Set(mapped.apps.map(\.foldAddress)).count == mapped.apps.count)
}

@Test func closedAssignedAppsRemainReachableInEveryMode() {
    let fixed = shortcut("Editor", "e")
    var selection = SelectionPreferences()
    selection.appShortcuts.enabled = true; selection.appShortcuts.launchClosedApps = true
    selection.appShortcuts.assignments = [fixed]
    var session = LabelSession(selection:selection)
    let closed = Target(id:fixed.targetID,app:fixed.name,title:fixed.name,bundleID:fixed.bundleID,isRunning:false)
    let snapshot = session.map(.init(apps:[closed]))
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode:mode); state.update(snapshot); state.open()
        #expect(state.targets.contains { $0.id == closed.id })
        #expect(state.navigationItems.isEmpty) // Invisible launchers do not take a cycling stop.
        #expect(state.handle(.letter("e")) == .selected(closed.id))
        state.open()
        #expect(state.commitHighlight() == .none)
        if mode == .fold {
            state.open(); #expect(state.handle(.prefix("e")) == .selected(closed.id))
        }
        state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query("Editor"))
        #expect(state.displayMatches.isEmpty && state.navigationItems.isEmpty)
        #expect(state.handle(.enter) == .none)
    }
}

@Test func browserOwnersResolveConsistentlyWithMultipleAppInstances() {
    let app = Target(id:.init(process:UUID()),app:"Browser",title:"Browser",bundleID:"test.browser")
    let duplicate = Target(id:.init(process:UUID()),app:"Browser",title:"Browser",bundleID:"test.browser")
    let tab = Target(id:.init(process:UUID(),window:UUID()),app:"Browser",title:"Document",bundleID:"test.browser")
    let source = CatalogueSnapshot(apps:[app,duplicate],tabs:[tab]).resolvingTabOwners()
    #expect(source.tabs[0].owner == app.id.process)
    var session = LabelSession()
    let mapped = session.map(source)
    for mode in [DisplayMode.fold,.canopy] {
        var state = SelectionState(); state.configure(mode:mode); state.update(mapped); state.open()
        #expect(!state.targets[0].address.isEmpty)
        #expect(state.commitHighlight() == .selected(tab.id))
    }
}
