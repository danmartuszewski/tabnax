import Foundation
import Testing
@testable import TabnaxCore

@Test func actionsFollowHighlightedWindowsAndFoldAppsInEveryMode() {
    let owner = UUID(), id = TargetID(process: owner, window: UUID()), appID = TargetID(process: owner)
    let window = Target(id: id, app: "App", title: "Window", address: "j", minimized: true, foldAddress: "aj")
    let app = Target(id: appID, app: "App", title: "App", address: "i", foldAddress: "a")
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode)
        state.update(.init(windows: [window], apps: [app])); state.open()
        #expect(state.actionTarget(for: .quitApplication) == appID)
        #expect(state.actionTarget(for: .restoreWindow) == id)
        if mode == .fold { _ = state.handle(.prefix("a")) }
        _ = state.handle(.highlight(.target(id)))
        #expect(state.actionTarget(for: .restoreWindow) == id)
        #expect(state.active)
    }
}

@Test func actionsUseSearchHighlightAndBrowserOwnerWithoutTreatingTabsAsWindows() {
    let owner = UUID(), appID = TargetID(process: owner)
    let tab = Target(id: TargetID(process: UUID(), window: UUID()), app: "Browser", title: "Result", address: "j", owner: owner)
    let window = Target(id: TargetID(process: UUID(), window: UUID()), app: "Other", title: "Window", address: "k")
    var state = SelectionState(); state.update(.init(windows: [window], tabs: [tab])); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("Result"))
    #expect(state.actionTarget(for: .quitApplication) == appID)
    #expect(state.actionTarget(for: .restoreWindow) == nil)
    var unresolved = tab; unresolved.owner = nil
    state.update(.init(tabs: [unresolved]))
    #expect(state.actionTarget(for: .quitApplication) == nil)
}

@Test func actionsRejectClosedUnavailableAndAmbiguousTargets() {
    let id = TargetID(process: UUID())
    var state = SelectionState()
    state.update(.init(apps: [Target(id: id, app: "Closed", title: "Closed", address: "j", isRunning: false)])); state.open()
    #expect(state.actionTarget(for: .quitApplication) == nil)
    #expect(state.actionTarget(for: .restoreWindow) == nil)
    state.update(.init(apps: [Target(id: id, app: "Gone", title: "Gone", address: "j", available: false)]))
    #expect(state.actionTarget(for: .quitApplication) == nil)
    let first = Target(id: TargetID(process: UUID(), window: UUID()), app: "A", title: "A", address: "pj")
    let second = Target(id: TargetID(process: UUID(), window: UUID()), app: "B", title: "B", address: "pk")
    state.configure(mode: .lattice); state.update(.init(windows: [first, second])); state.open()
    #expect(state.highlightedAction == .branch("p"))
    #expect(state.actionTarget(for: .quitApplication) == nil)
    #expect(state.actionTarget(for: .restoreWindow) == nil)
    _ = state.handle(.prefix("p"))
    #expect(state.actionTarget(for: .quitApplication) == TargetID(process: first.id.process))
    state.cancel()
    #expect(state.actionTarget(for: .quitApplication) == nil)
}

@Test func quitReconciliationAdvancesHighlightWithoutReassigningLetters() {
    let a = Target(id: TargetID(process: UUID()), app: "A", title: "A", address: "j")
    let b = Target(id: TargetID(process: UUID()), app: "B", title: "B", address: "k")
    var state = SelectionState(); state.update(.init(apps: [a, b])); state.open()
    state.update(state.snapshot.reconcilingLive(.init(apps: [b])))
    #expect(state.actionTarget(for: .quitApplication) == b.id)
    #expect(state.snapshot.apps.first?.address == "j")
    #expect(state.snapshot.apps.first?.available == false)
    #expect(state.active)
}

@Test func restoreIgnoresVisibleWindowsAndUsesRecentMinimizedChildForApps() {
    let owner = UUID(), appID = TargetID(process: owner)
    let visible = Target(id: .init(process: owner, window: UUID()), app: "App", title: "Visible", address: "j", foldAddress: "aj")
    var first = Target(id: .init(process: owner, window: UUID()), app: "App", title: "First", address: "k", minimized: true, foldAddress: "ak")
    var recent = Target(id: .init(process: owner, window: UUID()), app: "App", title: "Recent", address: "l", minimized: true, foldAddress: "al")
    let app = Target(id: appID, app: "App", title: "App", address: "i", foldAddress: "a")
    var history = FocusHistory(); history.observe(first.id); history.observe(recent.id); history.observe(visible.id)
    for mode in DisplayMode.allCases {
        first.available = true; recent.available = true
        var state = SelectionState(); state.configure(mode: mode)
        state.update(.init(windows: [visible, first, recent], apps: [app], history: history)); state.open()
        _ = state.handle(.beginSearch); _ = state.handle(.query("Visible"))
        #expect(state.actionTarget(for: .restoreWindow) == nil)
        _ = state.handle(.escape)
        if mode == .fold { _ = state.handle(.highlight(.branch("a"))) }
        else if mode == .canopy { continue } // Canopy exposes windows, not app targets.
        else { _ = state.handle(.highlight(.target(appID))) }
        #expect(state.actionTarget(for: .restoreWindow) == recent.id)
        recent.available = false
        state.update(.init(windows: [visible, first, recent], apps: [app], history: history))
        #expect(state.actionTarget(for: .restoreWindow) == first.id)
        first.minimized = false
        state.update(.init(windows: [visible, first, recent], apps: [app], history: history))
        #expect(state.actionTarget(for: .restoreWindow) == nil)
        first.minimized = true
    }
}

@Test func restoreFollowsLiveMinimizedStateWithoutChangingAddresses() {
    let id = TargetID(process: UUID(), window: UUID())
    var window = Target(id: id, app: "App", title: "Window", address: "j", minimized: true)
    var state = SelectionState(); state.update(.init(windows: [window])); state.open()
    #expect(state.actionTarget(for: .restoreWindow) == id)
    window.minimized = false
    state.update(state.snapshot.reconcilingLive(.init(windows: [window])))
    #expect(state.actionTarget(for: .restoreWindow) == nil)
    #expect(state.snapshot.windows.first?.address == "j")
}

@Test func windowMenuNeverResolvesAnotherWindowFromAppsTabsOrOverflow() {
    let owner = UUID(), appID = TargetID(process: owner)
    let window = Target(id: .init(process: owner, window: UUID()), app: "Browser", title: "Document", address: "j", foldAddress: "aj")
    let tab = Target(id: .init(process: UUID(), window: UUID()), app: "Browser", title: "Web tab", address: "k", foldAddress: "ak", owner: owner)
    let app = Target(id: appID, app: "Browser", title: "Browser", address: "l", foldAddress: "a")
    let operations: [SwitcherAction] = [.closeWindow, .minimizeWindow, .zoomWindow, .toggleFullscreen]
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode)
        state.update(.init(windows: [window], apps: [app], tabs: [tab])); state.open()
        _ = state.handle(.beginSearch); _ = state.handle(.query("Document"))
        for action in operations { #expect(state.actionTarget(for: action) == window.id) }
        let frozen = state.actionMenuItems
        _ = state.handle(.query("Web tab"))
        for action in operations { #expect(state.actionTarget(for: action) == nil) }
        #expect(state.actionMenuItems.first?.disabledReason == "Browser tab has no exact window target")
        #expect(state.actionTarget(for: .hideApplication) == appID)
        #expect(frozen.first?.target == window.id)
        #expect(state.snapshot.windows.first?.address == "j")
        _ = state.handle(.escape)
        if mode == .fold { _ = state.handle(.highlight(.branch("a"))) }
        else if mode != .canopy { _ = state.handle(.highlight(.target(appID))) }
        else { continue }
        for action in operations { #expect(state.actionTarget(for: action) == nil) }
        #expect(state.actionMenuItems.first?.disabledReason == "Highlight an individual window")
    }
}

@Test func hiddenMenuOffersUnhideAndClosedTargetExplainsWhyDisabled() {
    let app = Target(id: .init(process: UUID()), app: "App", title: "App", address: "j", hidden: true)
    var state = SelectionState(); state.update(.init(apps: [app])); state.open()
    #expect(state.actionMenuItems.contains { $0.action == .unhideApplication && $0.target == app.id })
    var closed = app; closed.isRunning = false
    state.update(.init(apps: [closed]))
    #expect(state.actionMenuItems.allSatisfy { $0.target == nil && $0.disabledReason != nil })
}

@Test func actionsSettingLoadsOlderDocumentsAndRoundTripsOff() throws {
    var document = SettingsDocument(); document.windowActionsEnabled = false
    let data = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: data).windowActionsEnabled == false)
    var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    old.removeValue(forKey: "windowActionsEnabled")
    let migrated = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(migrated.windowActionsEnabled)
    #expect(migrated.selection == document.selection)
    #expect(migrated.activation == document.activation)
}
