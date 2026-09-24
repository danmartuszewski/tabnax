import Foundation
import Testing
@testable import TabnaxCore

private func orderingFixture() -> CatalogueSnapshot {
    let a = UUID(), b = UUID()
    let windows = [
        Target(id: .init(process: a, window: UUID()), app: "Alpha", title: "Report 10", address: "j", foldAddress: "ij"),
        Target(id: .init(process: b, window: UUID()), app: "Beta", title: "Report 1", address: "k", minimized: true, foldAddress: "oj"),
        Target(id: .init(process: a, window: UUID()), app: "Alpha", title: "Report 2", address: "l", hidden: true, foldAddress: "ik"),
        Target(id: .init(process: b, window: UUID()), app: "Beta", title: "Report 2", address: "u", foldAddress: "ok", elsewhere: true)
    ]
    let apps = [Target(id: .init(process: a), app: "Alpha", title: "Alpha", address: "i", foldAddress: "i"),
                Target(id: .init(process: b), app: "Beta", title: "Beta", address: "o", foldAddress: "o"),
                Target(id: .init(process: UUID()), app: "Closed", title: "Closed", address: "c", foldAddress: "c", isRunning: false)]
    let tab = Target(id: .init(process: UUID(), window: UUID()), app: "Alpha", title: "Report 3", address: "m", foldAddress: "il", owner: a)
    var history = FocusHistory()
    for target in [windows[0], windows[2], windows[3], windows[1]] { history.observe(target.id) }
    return .init(windows: windows, apps: apps, allocated: Set((windows + apps + [tab]).map(\.address)), tabs: [tab], history: history)
}

@Test func ordersUseExactObservedHistoryNaturalNamesAndExplicitStatePriority() {
    let s = orderingFixture(), w = s.windows
    #expect(TraversalOrder.stable.sorted(w, history: s.history).map(\.id) == w.map(\.id))
    #expect(TraversalOrder.recent.sorted(w, history: s.history).map(\.id) == [w[1], w[3], w[2], w[0]].map(\.id))
    #expect(TraversalOrder.alphabetical.sorted(w, history: s.history).map(\.id) == [w[2], w[0], w[1], w[3]].map(\.id))
    #expect(TraversalOrder.state.sorted(w, history: s.history).map(\.id) == [w[0], w[3], w[1], w[2]].map(\.id))
    #expect(TraversalOrder.recent.sorted(w + s.tabs, history: .init()).map(\.id) == (w + s.tabs).map(\.id))
    var dead = w[0]; dead.available = false
    #expect(TraversalOrder.state.sorted([s.apps[2], dead, w[2], w[1], w[3]], history: .init()).map(\.id) == [w[3], w[1], w[2], dead, s.apps[2]].map(\.id))
    var closedHistory = s.history; closedHistory.retain(live: Set([w[0].id, w[2].id]))
    #expect(TraversalOrder.recent.sorted([w[0], w[2]], history: closedHistory).map(\.id) == [w[2].id, w[0].id])
}

@Test func groupedOrderUsesBestChildAndTabsKeepTheirRealOwner() {
    let s = orderingFixture(), w = s.windows
    for mode in [DisplayMode.shore, .canopy, .fold, .lattice] {
        var state = SelectionState(); state.configure(mode: mode); state.configure(ordering: .recent); state.update(s); state.open()
        let children = state.displayTargets.filter { $0.id.window != nil }
        if mode != .fold { #expect(children.map(\.id) == [w[1], w[3], w[2], w[0], s.tabs[0]].map(\.id)) }
        #expect(state.foldFamilies.filter(\.isRunning).map(\.id) == [s.apps[1].id, s.apps[0].id])
        if mode == .canopy {
            #expect(state.navigationGroupSizes == [2, 3])
            _ = state.handle(.highlight(.target(w[1].id))); _ = state.handle(.lateral(1))
            #expect(state.highlightedAction == .target(w[2].id))
        }
        if mode == .fold {
            #expect(state.highlightedAction == .branch("o"))
            var held = state; #expect(held.commitHighlight() == .selected(w[3].id))
            _ = state.handle(.enter)
            #expect(state.navigationItems.map(\.action) == [.target(w[1].id), .target(w[3].id)])
        }
    }
}

@Test func allOrdersCycleBothDirectionsAndSelectExactVisibleTargetsInEveryLayout() {
    let s = orderingFixture()
    for mode in DisplayMode.allCases {
        for order in TraversalOrder.allCases {
            var state = SelectionState(); state.configure(mode: mode); state.configure(ordering: order); state.update(s); state.open()
            let history = state.focusHistory, items = state.navigationItems
            #expect(!items.isEmpty)
            #expect(!items.contains { $0.action == .target(s.apps[2].id) || $0.action == .branch("c") })
            _ = state.handle(.highlight(items[0].action))
            for item in items {
                #expect(state.highlightedAction == item.action)
                var chosen = state
                if case .target(let id) = item.action {
                    #expect(chosen.commitHighlight() == .selected(id))
                    chosen = state
                    #expect(chosen.handle(.enter) == .selected(mode == .relay ? s.history.previous! : id))
                } else {
                    #expect(chosen.handle(.enter) == .changed)
                    for child in chosen.navigationItems {
                        var selecting = chosen; _ = selecting.handle(.highlight(child.action))
                        if case .target(let id) = child.action { #expect(selecting.commitHighlight() == .selected(id)) }
                    }
                }
                _ = state.handle(.next)
                #expect(state.focusHistory == history)
            }
            #expect(state.highlightedAction == items[0].action)
            _ = state.handle(.previous); #expect(state.highlightedAction == items.last?.action)
            let closed = s.apps[2]
            #expect(state.handle(.letter(closed.address)) == .selected(closed.id))
        }
    }
}

@Test func sessionOrderHistoryGroupsAndAddressesSurviveLiveMetadataAndSuppression() {
    let original = orderingFixture()
    for mode in DisplayMode.allCases {
        for order in TraversalOrder.allCases {
            var state = SelectionState(); state.configure(mode: mode); state.configure(ordering: order); state.update(original); state.open()
            let ids = state.targets.map(\.id), items = state.navigationItems, cells = state.latticeCells.map(\.address)
            let addresses = state.targets.map(\.address), history = state.focusHistory
            var latest = original
            latest.windows.reverse(); latest.apps.reverse()
            for i in latest.windows.indices { latest.windows[i].title = "Renamed \(i)"; latest.windows[i].hidden.toggle(); latest.windows[i].minimized.toggle(); latest.windows[i].elsewhere.toggle() }
            latest.history.observe(original.windows[0].id)
            latest.windows.append(Target(id: .init(process: UUID(), window: UUID()), app: "New", title: "New", address: "h"))
            state.update(state.snapshot.reconcilingLive(latest))
            #expect(state.targets.map(\.id) == ids); #expect(state.targets.map(\.address) == addresses)
            #expect(state.navigationItems == items); #expect(state.latticeCells.map(\.address) == cells)
            #expect(state.focusHistory == history)
            state.configure(ordering: order == .stable ? .recent : .stable)
            #expect(state.ordering == order)
            // A closed target stays in its original position, disabled; exclusion removes it.
            latest.windows.removeAll { $0.id == original.windows[1].id }
            state.update(state.snapshot.reconcilingLive(latest))
            #expect(state.targets.first { $0.id == original.windows[1].id }?.available == false)
            latest.suppressedIDs = [original.windows[0].id]
            state.update(state.snapshot.reconcilingLive(latest))
            #expect(!state.targets.contains { $0.id == original.windows[0].id })
            #expect(state.foldFamilies.filter(\.isRunning).map(\.id) == (order == .recent ? [original.apps[1].id, original.apps[0].id] : [original.apps[0].id, original.apps[1].id]))
            state.cancel(); state.update(latest); state.open()
            #expect(state.focusHistory == latest.history)
            #expect(state.targets.contains { $0.id == latest.windows.last?.id })
        }
    }
}

@Test func latticeSharedOverflowRemainsAfterAppCellsAndFrozenAfterExclusions() {
    var s = orderingFixture()
    s.windows[0].address = "pj"; s.windows[1].address = "pk"
    s.allocated = Set((s.windows + s.apps + s.tabs).map(\.address))
    for order in TraversalOrder.allCases {
        var state = SelectionState(); state.configure(mode: .lattice); state.configure(ordering: order); state.update(s); state.open()
        let cells = state.latticeCells.map(\.address)
        #expect(cells.firstIndex(of: "p")! > cells.firstIndex(of: "l")!)
        var latest = s; latest.suppressedIDs = [s.windows[0].id]
        state.update(state.snapshot.reconcilingLive(latest))
        #expect(state.latticeCells.map(\.address) == cells)
        _ = state.handle(.prefix("p"))
        #expect(state.navigationItems.map(\.action) == [.target(s.windows[1].id)])
        #expect(state.handle(.enter) == .selected(s.windows[1].id))
    }
}

@Test func strongSearchMatchesWinAndEqualScoresUseChosenOrderWithoutChangingAddresses() {
    var s = orderingFixture()
    for i in s.windows.indices { s.windows[i].title = "Report" }
    let direct = Dictionary(uniqueKeysWithValues: (s.windows + s.apps + s.tabs).map { ($0.id, $0.address) })
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.configure(ordering: .recent); state.update(s); state.open()
        _ = state.handle(.beginSearch); _ = state.handle(.query("report"))
        #expect(state.displayMatches.prefix(4).map(\.id) == [s.windows[1], s.windows[3], s.windows[2], s.windows[0]].map(\.id))
        var latest = s; latest.windows[0].title = "rep"; state.update(state.snapshot.reconcilingLive(latest))
        _ = state.handle(.query("rep"))
        #expect(state.displayMatches.first?.id == s.windows[0].id)
        #expect(state.snapshot.windows.allSatisfy { $0.address == direct[$0.id] })
        #expect(state.handle(.enter) == .selected(s.windows[0].id))
    }
}

@Test func orderingPreferenceIsBackwardCompatibleAndMalformedValuesFallBack() throws {
    let encoder = JSONEncoder(), decoder = JSONDecoder()
    #expect(SettingsDocument().traversalOrder == .stable)
    for order in TraversalOrder.allCases {
        var settings = SettingsDocument(); settings.traversalOrder = order
        #expect(try decoder.decode(SettingsDocument.self, from: encoder.encode(settings)).traversalOrder == order)
    }
    var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(SettingsDocument())) as? [String: Any])
    object.removeValue(forKey: "traversalOrder")
    #expect(try decoder.decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: object)).traversalOrder == .stable)
    for value in ["future-order", 42, NSNull()] as [Any] {
        object["traversalOrder"] = value
        #expect(try decoder.decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: object)).traversalOrder == .stable)
    }
}
