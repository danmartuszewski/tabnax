import Foundation
import Testing
@testable import TabnaxCore

private func exclusionFixture() -> CatalogueSnapshot {
    let a = UUID(), b = UUID()
    return .init(windows: [
        Target(id: .init(process: a, window: UUID()), app: "Same name", title: "Private report"),
        Target(id: .init(process: a, window: UUID()), app: "Same name", title: "Public report"),
        Target(id: .init(process: b, window: UUID()), app: "Same name", title: "Private report")
    ], apps: [Target(id: .init(process: a), app: "Same name", title: "Private report", bundleID: "test.One"),
              Target(id: .init(process: b), app: "Same name", title: "Same name", bundleID: "test.Two"),
              Target(id: .init(process: UUID()), app: "Closed", title: "Closed", bundleID: "test.Closed", isRunning: false)],
    tabs: [Target(id: .init(process: UUID(), window: UUID()), app: "Same name", title: "Private tab", bundleID: "test.One"),
           Target(id: .init(process: UUID(), window: UUID()), app: "Same name", title: "Public tab", bundleID: "test.One")])
}

@Test func titleMatchingSemanticsAndValidation() {
    #expect(TitleRule(pattern: "REPORT").matches(title: "Private report", bundleID: ""))
    #expect(!TitleRule(pattern: "report", match: .exact).matches(title: "Private report", bundleID: ""))
    #expect(TitleRule(pattern: "PRIVATE REPORT", match: .exact).matches(title: "Private report", bundleID: ""))
    #expect(TitleRule(pattern: "*report?", match: .wildcard).matches(title: "Any report1", bundleID: ""))
    #expect(!TitleRule(pattern: "report?", match: .wildcard).matches(title: "Any report1", bundleID: ""))
    #expect(TitleRule(pattern: #"\*\?\\"#, match: .wildcard).matches(title: #"*?\"#, bundleID: ""))
    #expect(TitleRule(pattern: "[abc].*", match: .wildcard).matches(title: "[abc].txt", bundleID: ""))
    #expect(!TitleRule(pattern: "cafe").matches(title: "café", bundleID: ""))
    #expect(!TitleRule(pattern: " report ").matches(title: "report", bundleID: ""))
    for pattern in ["", "  ", "a\n", String(repeating: "x", count: 257)] {
        #expect(TitleRule(pattern: pattern).validationError != nil)
        #expect(!TitleRule(pattern: pattern).matches(title: "Anything", bundleID: ""))
    }
    for pattern in [#"ends\"#, #"bad\d"#] { #expect(TitleRule(pattern: pattern, match: .wildcard).validationError != nil) }
    #expect(TitleRule(bundleID: "bad id", pattern: "report").validationError != nil)
    #expect(!TitleRule(bundleID: "test.One", pattern: "report").matches(title: "report", bundleID: "test.one"))
}

@Test func appRulesExcludeOwnedWindowsTabsRowsAndLaunchesByIdentity() {
    let raw = exclusionFixture().resolvingTabOwners()
    var session = LabelSession(), rules = ExclusionPreferences()
    let mapped = session.map(raw)
    rules.apps = [.init(bundleID: "test.One"), .init(bundleID: "test.Closed")]
    let visible = rules.applying(to: mapped)
    #expect(visible.windows.map(\.id) == [mapped.windows[2].id])
    #expect(visible.tabs.isEmpty)
    #expect(visible.apps.map(\.bundleID) == ["test.Two"])
    #expect(visible.suppressedIDs.count == 6)
    #expect(visible.allocated == mapped.allocated)
    #expect(session.map(raw) == mapped, "Filtering cannot recycle label reservations")
    #expect(ExclusionPreferences().applying(to: session.map(raw)) == mapped)
}

@Test func titleRulesKeepOtherWindowsAppsAndTabsAndStableAddressesInEveryMode() {
    let raw = exclusionFixture().resolvingTabOwners()
    var session = LabelSession(), rules = ExclusionPreferences()
    let mapped = session.map(raw)
    rules.titles = [.init(bundleID: "test.One", pattern: "private")]
    let visible = rules.applying(to: mapped)
    #expect(visible.windows.map(\.id) == Array(mapped.windows.dropFirst()).map(\.id))
    #expect(visible.apps == mapped.apps)
    #expect(visible.tabs == [mapped.tabs[1]])
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode); state.update(visible); state.open()
        #expect(!state.targets.contains { visible.suppressedIDs.contains($0.id) })
        for target in state.targets {
            let original = (mapped.windows + mapped.tabs + mapped.apps).first { $0.id == target.id }!
            #expect(target.address == ([.fold, .canopy].contains(mode) ? original.foldAddress : original.address))
        }
        _ = state.handle(.beginSearch); _ = state.handle(.query("private"))
        #expect(!state.displayMatches.contains { visible.suppressedIDs.contains($0.id) })
        #expect(state.select(mapped.windows[0].id) == .none)
        #expect(state.select(mapped.tabs[0].id) == .none)
    }
}

@Test func liveTitleChangesRemoveExplicitlyExcludedRowsInsteadOfKeepingGhosts() {
    var session = LabelSession(), rules = ExclusionPreferences()
    let original = session.map(exclusionFixture().resolvingTabOwners())
    var latest = original; latest.windows[1].title = "Private now"
    rules.titles = [.init(pattern: "Private")]
    let reconciled = original.reconcilingLive(rules.applying(to: latest))
    #expect(reconciled.windows.isEmpty)
    #expect(reconciled.tabs.count == 1)
    var closed = original; closed.windows.removeLast()
    #expect(original.reconcilingLive(closed).windows.last?.available == false, "Ordinary disappearance retains existing semantics")
}

@Test func missingIDsNeverUseDisplayNamesAndShortcutExceptionsAreIndependent() {
    var source = exclusionFixture(), rules = ExclusionPreferences()
    source.apps[0].bundleID = ""
    rules.apps = [.init(bundleID: "test.One", name: "Same name")]
    rules.shortcutExceptions = [.init(bundleID: "test.Two")]
    #expect(rules.applying(to: source).windows == source.windows)
    #expect(rules.passesActivationShortcuts(to: "test.Two"))
    #expect(!rules.passesActivationShortcuts(to: "test.One"))
    #expect(!rules.passesActivationShortcuts(to: nil))
    #expect(!rules.passesActivationShortcuts(to: ""))
    rules.titles = [.init(pattern: "Private")]
    #expect(rules.applying(to: source).windows.count == 1)
}

@Test func exclusionMigrationRoundTripAndMalformedEntriesStayLocal() throws {
    var doc = SettingsDocument(); doc.rememberSearchChoices = true
    doc.exclusions.apps = [.init(bundleID: "test.Uninstalled", name: "Old app")]
    doc.exclusions.shortcutExceptions = [.init(bundleID: "test.VM")]
    doc.exclusions.titles = [.init(pattern: "Secret?", match: .wildcard)]
    let data = try JSONEncoder().encode(doc)
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: data) == doc)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "exclusions")
    let old = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.exclusions == .init()); #expect(old.rememberSearchChoices)
    json["exclusions"] = ["apps": [["bundleID": "test.Valid", "name": "Valid"], ["bad": 42], ["bundleID": "", "name": "Empty"]],
                          "titles": [["id": UUID().uuidString, "bundleID": "", "pattern": "", "match": "wildcard"]],
                          "shortcutExceptions": false]
    let repaired = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: json)).validated()
    #expect(repaired.exclusions.apps == [.init(bundleID: "test.Valid", name: "Valid")])
    #expect(repaired.exclusions.titles.isEmpty); #expect(repaired.exclusions.shortcutExceptions.isEmpty)
    #expect(repaired.rememberSearchChoices)
    doc.exclusions.titles = [.init(pattern: "")]
    #expect(throws: SettingsError.self) { try doc.validated() }
}
