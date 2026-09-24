import Foundation
import Testing
@testable import TabnaxCore

private func window(_ app: String, _ address: String, process: UUID = UUID(), fold: String = "", available: Bool = true) -> Target {
    Target(id: TargetID(process: process, window: UUID()), app: app, title: app, address: address, available: available, foldAddress: fold)
}

@Test func historyKeepsARecencyStackSoClosingThePreviousWindowFallsBackToTheOneBefore() {
    let a = window("A","j"), b = window("B","k"), c = window("C","l")
    var history = FocusHistory()
    for id in [a.id, b.id, c.id] { history.observe(id) }
    #expect(history.current == c.id); #expect(history.previous == b.id); #expect(history.recent == [b.id, a.id])
    history.observe(a.id) // Revisiting moves a window to the front without duplicating it.
    #expect(history.current == a.id); #expect(history.recent == [c.id, b.id])
    history.retain(live: [a.id, b.id]) // C closed: B is the window before that.
    #expect(history.previous == b.id)
    history.retain(live: [b.id]) // The current window closed; nothing is promoted into its place.
    #expect(history.current == nil); #expect(history.previous == b.id)
    history.observe(b.id); #expect(history.current == b.id); #expect(history.previous == nil)
}

@Test func historyIsBounded() {
    var history = FocusHistory()
    for _ in 0..<(FocusHistory.depth + 10) { history.observe(TargetID(process: UUID(), window: UUID())) }
    #expect(history.recent.count == FocusHistory.depth)
}

@Test func openingStartsOnThePreviouslyUsedWindowWithoutReorderingRows() {
    let a = window("A","j"), b = window("B","k"), c = window("C","l")
    var history = FocusHistory(); history.observe(b.id); history.observe(c.id) // now on C, came from B
    var state = SelectionState(); state.update(.init(windows: [a,b,c], history: history))
    #expect(state.open() == true)
    #expect(state.targets.map(\.id) == [a.id,b.id,c.id])
    #expect(state.highlightedAction == .target(b.id))
    #expect(state.handle(.enter) == .selected(b.id))
}

@Test func openingSkipsAnUnavailablePreviousWindowAndFallsBackToTheTop() {
    let a = window("A","j"), b = window("B","k", available: false), c = window("C","l"), d = window("D","h")
    var history = FocusHistory(); history.observe(d.id); history.observe(b.id); history.observe(c.id)
    var state = SelectionState(); state.update(.init(windows: [a,b,c,d], history: history))
    #expect(state.open() == true); #expect(state.highlightedAction == .target(d.id))
    var empty = SelectionState(); empty.update(.init(windows: [a,c]))
    #expect(empty.open() == false); #expect(empty.cursor == 0)
}

@Test func foldOpensOnThePreviousWindowsAppAndCommitsToThatWindow() {
    let safari = UUID(), mail = UUID()
    let s1 = window("Safari","j",process:safari,fold:"sj"), s2 = window("Safari","k",process:safari,fold:"sk"), m = window("Mail","l",process:mail,fold:"mj")
    let apps = [Target(id:TargetID(process:mail),app:"Mail",title:"Mail",address:"m",foldAddress:"m"),
                Target(id:TargetID(process:safari),app:"Safari",title:"Safari",address:"s",foldAddress:"s")]
    var history = FocusHistory(); history.observe(s2.id); history.observe(m.id)
    var state = SelectionState(); state.configure(mode:.fold); state.update(.init(windows:[s1,s2,m],apps:apps,history:history))
    #expect(state.open() == true); #expect(state.highlightedAction == .branch("s"))
    // The group stands for its most recently used window, not merely its first listed one.
    #expect(state.commitHighlight() == .selected(s2.id))
}

@Test func arrowKeysFollowEachLayout() {
    let one = UUID(), two = UUID()
    let a1 = window("One","j",process:one,fold:"oj"), a2 = window("One","k",process:one,fold:"ok"), a3 = window("One","l",process:one,fold:"ol")
    let b1 = window("Two","u",process:two,fold:"tj")
    let apps = [Target(id:TargetID(process:one),app:"One",title:"One",address:"o",foldAddress:"o"),
                Target(id:TargetID(process:two),app:"Two",title:"Two",address:"t",foldAddress:"t")]
    let snapshot = CatalogueSnapshot(windows:[a1,a2,a3,b1],apps:apps)

    var shore = SelectionState(); shore.update(snapshot); shore.open()
    #expect(shore.handle(.lateral(1)) == .none); #expect(shore.active)

    var canopy = SelectionState(); canopy.configure(mode:.canopy); canopy.update(snapshot); canopy.open()
    _ = canopy.handle(.next); _ = canopy.handle(.next); #expect(canopy.highlightedAction == .target(a3.id))
    #expect(canopy.handle(.lateral(1)) == .changed); #expect(canopy.highlightedAction == .target(b1.id)) // Clamped to the shorter column.
    #expect(canopy.handle(.lateral(1)) == .none)
    #expect(canopy.handle(.lateral(-1)) == .changed); #expect(canopy.highlightedAction == .target(a1.id))

    var fold = SelectionState(); fold.configure(mode:.fold); fold.update(snapshot); fold.open()
    #expect(fold.highlightedAction == .branch("o"))
    #expect(fold.handle(.lateral(1)) == .changed); #expect(fold.prefix == "o")
    _ = fold.handle(.next)
    #expect(fold.handle(.lateral(-1)) == .changed); #expect(fold.prefix.isEmpty); #expect(fold.highlightedAction == .branch("o"))
    #expect(fold.handle(.lateral(-1)) == .none); #expect(fold.active)

    var lattice = SelectionState(); lattice.configure(mode:.lattice); lattice.update(snapshot); lattice.open()
    let first = lattice.highlightedAction
    #expect(lattice.handle(.lateral(1)) == .changed); #expect(lattice.highlightedAction != first)
    #expect(lattice.handle(.lateral(-1)) == .changed); #expect(lattice.highlightedAction == first)
}

@Test func elsewhereWindowsStaySelectable() {
    var far = window("Far","j"); far.elsewhere = true
    var state = SelectionState(); state.update(.init(windows:[far])); state.open()
    #expect(state.navigationItems.map(\.action) == [.target(far.id)])
    #expect(state.handle(.letter("j")) == .selected(far.id))
}
