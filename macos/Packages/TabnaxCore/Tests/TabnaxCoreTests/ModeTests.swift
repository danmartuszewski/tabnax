import Foundation
import CoreGraphics
import Testing
@testable import TabnaxCore

private func modeFixture(_ count: Int = 10, alphabet: String = AddressBook.rightHand) throws -> CatalogueSnapshot {
    // Windows, tabs, and apps share one pool now, so both draw from it here too.
    var pool = try AddressBook(alphabet: alphabet)
    let processes = (0..<3).map { _ in UUID() }
    let appTargets = try processes.enumerated().map { index, process in
        let id = TargetID(process: process)
        let address = try pool.address(for: id)
        // Mirrors LabelSession.map(): an app's own head letter (published via foldAddress)
        // is a separate concept from its flat pool address, but this fixture keeps them
        // equal since it isn't exercising the dedicated `heads` book itself.
        return Target(id: id, app: "App \(index)", title: "App \(index)", address: address, foldAddress: address)
    }
    var children = try processes.map { _ in try AddressBook(alphabet: alphabet) }
    let targets = try (0..<count).map { index in
        let family = index == 0 ? 0 : index == 1 ? 1 : 2
        let id = TargetID(process: processes[family], window: UUID())
        return Target(id: id, app: appTargets[family].app, title: index == 0 ? "Unique editor" : "Duplicate title",
            address: try pool.address(for: id), minimized: index == 7,
            foldAddress: appTargets[family].address + (try children[family].address(for: id)))
    }
    return CatalogueSnapshot(windows: targets, apps: appTargets, alphabet: alphabet, allocated: pool.allocated)
}
@Test func fiveFlatModesShareEveryDirectAddress() throws {
    for count in [6, 8, 10] {
        let snapshot = try modeFixture(count)
        for mode in DisplayMode.allCases where mode != .fold {
            // Canopy nests tabs/windows under their app container and shows the grouped
            // fold address; the other flat modes mix apps in and use the raw pool address.
            let expected = mode == .canopy ? snapshot.windows : snapshot.windows + snapshot.apps
            let addressOf: (Target) -> String = mode == .canopy ? \.foldAddress : \.address
            for target in snapshot.windows {
                var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
                #expect(state.targets.map(\.address) == expected.map(addressOf))
                var outcome = SelectionEffect.none
                for key in addressOf(target) { outcome = state.handle(.letter(String(key))) }
                #expect(outcome == .selected(target.id))
            }
        }
    }
}
@Test func foldSingletonAppsSelectDirectlyMultiWindowAppsStillRequireBothStages() throws {
    let snapshot = try modeFixture()
    // Fixture families 0 and 1 hold exactly one window each; family 2 holds the rest.
    let singletonProcesses: Set<UUID> = [snapshot.apps[0].id.process, snapshot.apps[1].id.process]
    for target in snapshot.windows {
        var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
        let firstKey = state.handle(.letter(String(target.foldAddress.first!)))
        if singletonProcesses.contains(target.id.process) {
            #expect(firstKey == .selected(target.id))
            #expect(!state.active)
        } else {
            #expect(firstKey == .changed)
            #expect(state.active)
            var outcome = SelectionEffect.none
            for key in target.foldAddress.dropFirst() { outcome = state.handle(.letter(String(key))) }
            #expect(outcome == .selected(target.id))
        }
    }
    // Arrow-key/Enter navigation into a family spine entry still unfolds rather than
    // activating a singleton immediately — only direct letter-typing gets the shortcut.
    var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
    #expect(state.handle(.enter) == .changed) // Enter unfolds; it does not activate the singleton.
    #expect(state.active)
    #expect(state.handle(.enter) == .selected(snapshot.windows[0].id))
}
@Test func foldBackSearchAndChurnKeepSiblingAddresses() throws {
    var snapshot = try modeFixture()
    var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
    _ = state.handle(.prefix(snapshot.apps[2].address)); #expect(state.foldFamily?.id == snapshot.apps[2].id)
    _ = state.handle(.backspace); #expect(state.foldFamily == nil)
    _ = state.handle(.prefix(snapshot.apps[2].address)); _ = state.handle(.escape); #expect(state.active && state.prefix.isEmpty)
    let stable = snapshot.windows[2].foldAddress; snapshot.windows.removeLast(); state.update(snapshot)
    #expect(state.targets.first { $0.id == snapshot.windows[2].id }?.address == stable)
}
@Test func latticeHoldsCellsAndCanNarrowOverflowWithoutAFrame() throws {
    for alphabet in [AddressBook.rightHand, AddressBook.leftHand, "abcdef"] {
        var snapshot = try modeFixture(alphabet: alphabet)
        var state = SelectionState(); state.configure(mode: .lattice); state.update(snapshot); state.open()
        let code = snapshot.windows.removeFirst().address; state.update(snapshot)
        let held = try #require(state.latticeCells.first { $0.address == code })
        #expect(held.held && held.target == nil && held.descendants.isEmpty)
        #expect(Set(state.latticeCells.map(\.address)) == Set(alphabet.map(String.init)))
        let overflow = try #require(state.latticeCells.first { !$0.descendants.isEmpty })
        #expect(state.handle(.prefix(overflow.address)) == .changed)
        let target = try #require(state.matches.first)
        var outcome = SelectionEffect.none
        for key in target.address.dropFirst(state.prefix.count) { outcome = state.handle(.letter(String(key))) }
        #expect(outcome == .selected(target.id))
    }
}
@Test func relayUsesObservedDistinctHistoryAndNeverInventsFallback() throws {
    var snapshot = try modeFixture()
    let a = snapshot.windows[0].id, b = snapshot.windows[1].id
    var state = SelectionState(); state.configure(mode: .relay); state.update(snapshot); state.open()
    #expect(state.handle(.enter) == .none)
    snapshot.history.observe(a); snapshot.history.observe(a); #expect(snapshot.history.previous == nil)
    snapshot.history.observe(b); snapshot.history.observe(b); state.update(snapshot)
    #expect(state.handle(.enter) == .none) // Session return history stays frozen.
    state.cancel(); state.open()
    #expect(state.handle(.enter) == .selected(a))
    #expect(snapshot.history.current == b) // Selecting isn't proof of focus.
    snapshot.history.observe(a); state.update(snapshot); state.open()
    #expect(state.handle(.enter) == .selected(b))
    snapshot.windows.removeAll { $0.id == b }; snapshot.history.retain(live: Set(snapshot.windows.map(\.id)))
    state.update(snapshot); state.open(); #expect(state.handle(.enter) == .none)
    #expect(state.active)
}
@Test func relayDoesNotChangeHistoryOnCancelSearchModeOrSameWindow() throws {
    var snapshot = try modeFixture(); let a = snapshot.windows[0].id, b = snapshot.windows[1].id
    snapshot.history.observe(a); snapshot.history.observe(b)
    var state = SelectionState(); state.update(snapshot); state.configure(mode: .relay); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("unique editor")); _ = state.handle(.escape)
    _ = state.handle(.escape); state.configure(mode: .fold); state.configure(mode: .relay)
    #expect(state.snapshot.history == snapshot.history)
    snapshot.windows[0].available = false; state.update(snapshot); state.open()
    #expect(state.handle(.enter) == .none)
}
@Test func searchIsGlobalAndNeverTreatsTextAsAddressesInAnyMode() throws {
    let snapshot = try modeFixture()
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        if mode == .fold { _ = state.handle(.prefix(snapshot.apps[2].address)) }
        _ = state.handle(.beginSearch); _ = state.handle(.query("app 0 unique"))
        #expect(state.matches.map(\.id) == [snapshot.windows[0].id])
        #expect(state.handle(.letter("j")) == .none)
        #expect(state.handle(.enter) == .selected(snapshot.windows[0].id))
        state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query("missing"))
        #expect(state.handle(.enter) == .none)
        #expect(state.handle(.escape) == .changed && state.query == nil)
        #expect(state.handle(.escape) == .cancelled)
        state.open(); _ = state.handle(.beginSearch)
        #expect(state.handle(.dismiss) == .cancelled && !state.active)
    }
}
@Test func flatModesExposeAppsInlineWhileFoldAndCanopyTreatThemAsContainers() throws {
    let snapshot = try modeFixture()
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        if mode == .fold || mode == .canopy {
            #expect(!state.targets.contains { $0.id == snapshot.apps[0].id })
        } else {
            #expect(state.handle(.letter(snapshot.apps[0].address)) == .selected(snapshot.apps[0].id))
        }
        #expect(state.snapshot.windows == snapshot.windows)
    }
}
@Test func beaconCollisionHiddenUnknownAndOffscreenGoToBank() throws {
    var targets = try modeFixture(6).windows
    for i in targets.indices { targets[i].onScreen = true }
    targets[2].minimized = true; targets[3].hidden = true; targets[4].onScreen = false
    let same = CGRect(x: -900, y: 200, width: 500, height: 500)
    let frames = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, same) })
    let plan = BeaconPlan.make(targets: targets, frames: frames, screens: [CGRect(x: -1000, y: 0, width: 1000, height: 800)], reserved: CGRect(x: -900, y: 0, width: 800, height: 150))
    #expect(plan.plaques.count == 1 && plan.bank.count == 5)
    #expect(Set(plan.plaques.keys).union(plan.bank.map(\.id)) == Set(targets.map(\.id)))
    #expect(plan.plaques.values.allSatisfy { CGRect(x: -1000, y: 0, width: 1000, height: 800).contains($0) })
    let reasons = Dictionary(uniqueKeysWithValues: plan.bank.map { ($0.id, $0.reason) })
    #expect(reasons[targets[2].id] == .offScreen) // minimized
    #expect(reasons[targets[3].id] == .occluded) // hidden
    #expect(reasons[targets[4].id] == .offScreen) // onScreen == false
    #expect(reasons[targets[1].id] == .colliding) // shares target[0]'s exact frame
    #expect(reasons[targets[5].id] == .colliding) // shares target[0]'s exact frame
    let unknown = BeaconPlan.make(targets: targets, frames: [:], screens: [], reserved: .zero)
    #expect(unknown.plaques.isEmpty && unknown.bank.count == targets.count)
    let unknownReasons = Dictionary(uniqueKeysWithValues: unknown.bank.map { ($0.id, $0.reason) })
    #expect(unknownReasons[targets[0].id] == .ambiguousPosition) // no frame available
}

@Test func repeatedHoverOnTheHighlightedItemCostsNoRender() throws {
    let snapshot = try modeFixture(6)
    var state = SelectionState(); state.configure(mode: .shore); state.update(snapshot); state.open()
    let second = snapshot.windows[1].id
    #expect(state.handle(.highlight(.target(second))) == .changed)
    #expect(state.handle(.highlight(.target(second))) == .none)
    #expect(state.highlightedAction == .target(second))
    // Fold keeps a hovered app as pointer focus; reporting it again is equally free.
    var fold = SelectionState(); fold.configure(mode: .fold); fold.update(snapshot); fold.open()
    let head = snapshot.apps[2].foldAddress
    _ = fold.handle(.highlight(.branch(head)))
    #expect(fold.handle(.highlight(.branch(head))) == .none)
    #expect(fold.highlightedAction == .branch(head))
}

@Test func storedTargetsFollowModeAndSnapshot() throws {
    let snapshot = try modeFixture(8)
    var state = SelectionState(); state.update(snapshot)
    #expect(state.targets.map(\.address) == (snapshot.windows + snapshot.apps).map(\.address))
    state.configure(mode: .canopy)
    #expect(state.targets.map(\.address) == snapshot.windows.map(\.foldAddress))
    state.configure(mode: .relay); state.update(CatalogueSnapshot())
    #expect(state.targets.isEmpty)
}

@Test func revisionAloneDoesNotChangeWhatIsRendered() throws {
    var snapshot = try modeFixture(6)
    var state = SelectionState(); state.configure(mode: .lattice); state.update(snapshot); state.open()
    var later = state; snapshot.revision += 1; later.update(snapshot)
    #expect(later != state); #expect(later.rendersSame(as: state))
    snapshot.windows[0].title = "Renamed"; later.update(snapshot)
    #expect(!later.rendersSame(as: state))
    var moved = state; _ = moved.handle(.next)
    #expect(!moved.rendersSame(as: state))
}

@Test func canopyNavigationKeepsFirstSeenGroupOrder() throws {
    let snapshot = try modeFixture(10)
    var state = SelectionState(); state.configure(mode: .canopy); state.update(snapshot); state.open()
    var order: [UUID] = []
    for target in state.targets where !order.contains(target.groupOwner) { order.append(target.groupOwner) }
    let expected = order.flatMap { group in state.targets.filter { $0.groupOwner == group && $0.available } }.map { NavigationAction.target($0.id) }
    #expect(state.navigationItems.map(\.action) == expected)
}

@Test func searchWalksResultsInEachLayoutsOwnOrder() throws {
    let snapshot = try modeFixture(10)
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        _ = state.handle(.beginSearch); _ = state.handle(.query(""))
        let walked = state.navigationItems.map(\.action)
        let results = state.matches.filter(\.available)
        // Every available result is reachable exactly once, and never through a branch.
        #expect(Set(walked) == Set(results.map { .target($0.id) }), "\(mode)")
        #expect(walked.count == results.count, "\(mode)")
        guard mode == .shore || mode == .canopy || mode == .fold || mode == .lattice else { continue }
        // Grouped layouts keep one app's results adjacent, matching their columns and spine.
        let owners = walked.compactMap { action -> UUID? in
            guard case .target(let id) = action else { return nil }
            return results.first { $0.id == id }?.groupOwner
        }
        var seen: [UUID] = []
        for owner in owners where seen.last != owner { seen.append(owner) }
        #expect(seen.count == Set(seen).count, "\(mode)")
    }
}

@Test func foldSearchFollowsTheAppSpineOrder() throws {
    let snapshot = try modeFixture(10)
    var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
    _ = state.handle(.beginSearch)
    let spine = state.foldFamilies.map(\.id.process)
    var owners: [UUID] = []
    for case .target(let id) in state.navigationItems.map(\.action) {
        guard let owner = state.matches.first(where: { $0.id == id })?.groupOwner else { continue }
        if owners.last != owner { owners.append(owner) }
    }
    #expect(owners == spine.filter(owners.contains))
}

@Test func canopyFilteringKeepsTheOriginalAppOrderIncludingOwnedTabs() {
    let a = UUID(), b = UUID()
    let a1 = Target(id: .init(process: a, window: UUID()), app: "A", title: "Other", foldAddress: "jj")
    let b1 = Target(id: .init(process: b, window: UUID()), app: "B", title: "Needle", foldAddress: "kj")
    let a2 = Target(id: .init(process: a, window: UUID()), app: "A", title: "Needle", foldAddress: "jk")
    let tab = Target(id: .init(process: UUID(), window: UUID()), app: "A", title: "Needle tab", foldAddress: "jl", owner: a)
    var state = SelectionState(); state.configure(mode: .canopy)
    state.update(.init(windows: [a1, b1, a2], tabs: [tab])); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("needle"))
    #expect(state.navigationItems.map(\.action) == [a2, tab, b1].map { .target($0.id) })
    #expect(state.navigationGroupSizes == [2, 1])
    #expect(state.handle(.enter) == .selected(a2.id))
}

@Test func shoreGroupsWindowsTabsAndAppRowsInVisualAndKeyboardOrder() {
    let a = UUID(), b = UUID()
    let a1 = Target(id:.init(process:a,window:UUID()),app:"Alpha",title:"Other",address:"j")
    let b1 = Target(id:.init(process:b,window:UUID()),app:"Beta",title:"Needle",address:"k")
    let a2 = Target(id:.init(process:a,window:UUID()),app:"Alpha",title:"Needle",address:"l")
    let tab = Target(id:.init(process:UUID(),window:UUID()),app:"Alpha",title:"Needle tab",address:"u",owner:a)
    let appA = Target(id:.init(process:a),app:"Alpha",title:"Alpha",address:"i")
    let appB = Target(id:.init(process:b),app:"Beta",title:"Beta",address:"o")
    let snapshot = CatalogueSnapshot(windows:[a1,b1,a2],apps:[appA,appB],tabs:[tab])
    var state = SelectionState(); state.configure(mode:.shore); state.update(snapshot); state.open()
    let expected = [a1,a2,tab,appA,b1,appB]
    #expect(state.displayTargets == expected)
    #expect(state.displayMatches == expected)
    #expect(state.navigationItems.map(\.action) == expected.map { .target($0.id) })
    for target in expected {
        #expect(state.highlightedAction == .target(target.id))
        _ = state.handle(.next)
    }
    // Filtering out the group's first window must not reorder the remaining groups.
    _ = state.handle(.beginSearch); _ = state.handle(.query("needle"))
    #expect(state.displayMatches == [a2,tab,b1])
    #expect(state.navigationItems.map(\.action) == [a2,tab,b1].map { .target($0.id) })
    #expect(state.handle(.enter) == .selected(a2.id))
    // Grouping changes presentation only: direct addresses and the source stay intact.
    state.open(); #expect(state.handle(.letter("k")) == .selected(b1.id))
    #expect(state.snapshot == snapshot)
    state.configure(mode:.beacons)
    #expect(state.displayTargets == snapshot.windows + snapshot.tabs + snapshot.apps)
}

@Test func foldSearchRejectsBranchHighlightsAndEmptySearchCannotSelect() throws {
    let snapshot = try modeFixture()
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        let original = state.targets
        _ = state.handle(.beginSearch)
        #expect(state.handle(.highlight(.branch(snapshot.apps[0].foldAddress))) == .none)
        _ = state.handle(.query("no-such-result"))
        #expect(state.highlightedAction == nil)
        #expect(state.handle(.enter) == .none)
        #expect(state.active && state.mode == mode)
        _ = state.handle(.query(""))
        #expect(state.matches == original)
        _ = state.handle(.escape)
        #expect(state.query == nil && state.targets == original && state.mode == mode)
    }
}

@Test func latticeGroupsAppTilesBeforeHeldSlotsAndKeepsOverflowReachable() {
    let a = UUID(), b = UUID()
    let a1 = Target(id:.init(process:a,window:UUID()),app:"Alpha",title:"Other",address:"j")
    let b1 = Target(id:.init(process:b,window:UUID()),app:"Beta",title:"Needle",address:"k")
    let a2 = Target(id:.init(process:a,window:UUID()),app:"Alpha",title:"Needle",address:"l")
    let tab = Target(id:.init(process:UUID(),window:UUID()),app:"Alpha",title:"Needle tab",address:"uu",owner:a)
    let appA = Target(id:.init(process:a),app:"Alpha",title:"Alpha",address:"i")
    let appB = Target(id:.init(process:b),app:"Beta",title:"Beta",address:"o")
    let source = CatalogueSnapshot(windows:[a1,b1,a2],apps:[appA,appB],allocated:["j","k","l","uu","i","o","p"],tabs:[tab])
    var state = SelectionState(); state.configure(mode:.lattice); state.update(source); state.open()
    #expect(state.latticeCells.prefix(6).map(\.address) == ["j","l","u","i","k","o"])
    #expect(state.latticeCells.last?.address == "p" && state.latticeCells.last?.held == true)
    let actions: [NavigationAction] = [.target(a1.id),.target(a2.id),.branch("u"),.target(appA.id),.target(b1.id),.target(appB.id)]
    #expect(state.navigationItems.map(\.action) == actions)
    for action in actions {
        #expect(state.highlightedAction == action); _ = state.handle(.next)
    }
    #expect(state.handle(.letter("u")) == .changed)
    #expect(state.handle(.letter("u")) == .selected(tab.id))
    state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query("needle"))
    #expect(state.displayMatches.map(\.id) == [a2,tab,b1].map(\.id))
    #expect(state.navigationItems.map(\.action) == [a2,tab,b1].map { .target($0.id) })
    #expect(state.snapshot == source)
}

@Test func latticeGroupsTargetsInsideSharedOverflowBranches() {
    let a = UUID(), b = UUID()
    let windows = [(a,"uj"),(b,"uk"),(a,"ul")].map { owner, address in
        Target(id:.init(process:owner,window:UUID()),app:"App",title:"Window",address:address)
    }
    var state = SelectionState(); state.configure(mode:.lattice)
    state.update(.init(windows:windows,allocated:Set(windows.map(\.address)))); state.open()
    #expect(state.handle(.letter("u")) == .changed)
    #expect(state.latticeCells.prefix(3).map(\.address) == ["uj","ul","uk"])
    #expect(state.navigationItems.map(\.action) == [windows[0],windows[2],windows[1]].map { .target($0.id) })
    #expect(state.handle(.letter("k")) == .selected(windows[1].id))
}

@Test func committingAHighlightedGroupSwitchesToItsFirstMember() throws {
    let snapshot = try modeFixture(10)
    var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
    guard case .branch(let code)? = state.highlightedAction else { Issue.record("Fold starts on an app"); return }
    let app = try #require(snapshot.apps.first { $0.foldAddress == code })
    let first = try #require(state.targets.first { $0.groupOwner == app.id.process && $0.available })
    #expect(state.commitHighlight() == .selected(first.id))
    #expect(!state.active)
    var searching = SelectionState(); searching.configure(mode: .shore); searching.update(snapshot); searching.open()
    _ = searching.handle(.beginSearch)
    #expect(searching.commitHighlight() == .none)
}
