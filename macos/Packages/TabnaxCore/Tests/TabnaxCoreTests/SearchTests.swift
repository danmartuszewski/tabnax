import Foundation
import Testing
@testable import TabnaxCore

private func search(_ query: String, in targets: [Target], mode: DisplayMode = .shore) -> [TargetID] {
    var state = SelectionState()
    state.configure(mode: mode)
    state.update(CatalogueSnapshot(windows: targets))
    state.open()
    _ = state.handle(.beginSearch)
    _ = state.handle(.query(query))
    return state.matches.map(\.id)
}

private func target(_ title: String, app: String = "Browser", group: String = "") -> Target {
    Target(id: TargetID(process: UUID(), window: UUID()), app: app, title: title, group: group)
}

@Test func searchIgnoresFormattingSeparatorsInEveryMode() {
    let titles = ["web-1", "web_1", "web 1", "web.1", "web/1", "web－1", "web．1", "web／1", "web\\1", "web–1", "web‑1", "web\u{00a0}1", "Web1"]
    let targets = titles.map { target($0) }
    for mode in DisplayMode.allCases {
        for query in ["web1", "WEB-1", "web_1", "web 1"] {
            #expect(search(query, in: targets, mode: mode) == targets.map(\.id))
        }
    }
}

@Test func searchHandlesAccentsWidthAndJoinedNames() {
    for (query, title) in [("cafe", "Café"), ("café", "Cafe"), ("resume", "Re\u{0301}sume\u{0301}"),
                           ("web1", "ＷＥＢ１"), ("github", "Git Hub"), ("dont", "Don’t"),
                           ("readmemd", "README.md")] {
        let item = target(title)
        #expect(search(query, in: [item]) == [item.id])
    }
}

@Test func searchKeepsAllTermsAndFieldBoundaries() {
    let item = target("Web-1 dashboard", app: "Google Chrome", group: "Work_space")
    #expect(search(" workspace  WEB1\tchrome ", in: [item]) == [item.id])
    #expect(search("web1 missing", in: [item]).isEmpty)
    #expect(search("chromeweb1", in: [item]).isEmpty)
    #expect(search("dashboardworkspace", in: [item]).isEmpty)
    #expect(search("wb1", in: [item]) == [item.id])
    #expect(search(" \t\n", in: [item]) == [item.id])
}

@Test func searchPreservesSymbolsAndSeparatorOnlyQueries() {
    let targets = [target("C++ reference"), target("C# reference"), target("C reference"), target("web-1")]
    #expect(search("c++", in: targets) == [targets[0].id])
    #expect(search("c#", in: targets) == [targets[1].id])
    #expect(search("-", in: targets) == [targets[3].id])
    #expect(search("...", in: targets).isEmpty)
}

@Test func searchRefreshesWhenMetadataChanges() {
    var item = target("old-title", app: "Old Browser", group: "Old Group")
    item.title = "New-Title"
    item.app = "New Browser"
    item.group = "New Group"
    #expect(search("newtitle newbrowser newgroup", in: [item]) == [item.id])
    #expect(search("old", in: [item]).isEmpty)
}

@Test func ranksExactPrefixWordSubstringInitialsAndSubsequence() {
    let titles = ["D o c u m e n t s", "Archived Documents", "Documents draft", "Documents", "MyDocuments", "distant oak cedar", "day of code"]
    let targets = titles.map { target($0) }
    #expect(search("documents", in: targets) == [targets[0], targets[3], targets[2], targets[1], targets[4]].map(\.id))
    let abbreviation = [target("Remote Configuration"), target("Release Candidate"), target("recorder"), target("rc")]
    #expect(search("rc", in: abbreviation) == [abbreviation[3], abbreviation[0], abbreviation[1], abbreviation[2]].map(\.id))
    let code = target("InputRouter.swift", app: "Visual Studio Code", group: "Work Projects")
    for query in ["vsc", "inptrtr", "ir", "wp", "vsc ir wp"] { #expect(search(query, in: [code]) == [code.id], "\(query)") }
}

@Test func fuzzySearchRejectsTyposReversedLettersAndSymbolOmissions() {
    let item = target("Keyboard guide", app: "Safari", group: "Personal")
    for query in ["keybaord", "keyboarrd", "safrai", "safarikeyboard", "guidepersonal"] {
        #expect(search(query, in: [item]).isEmpty, "\(query)")
    }
    let symbols = [target("C++ Primer"), target("C# Primer"), target("C Primer")]
    #expect(search("cp", in: symbols) == [symbols[2].id])
    #expect(search("c+p", in: symbols).isEmpty)
    #expect(search("c++p", in: symbols) == [symbols[0].id])
    #expect(search("c#p", in: symbols) == [symbols[1].id])
    #expect(search("-", in: [target("nothing")]).isEmpty)
}

@Test func rankedSearchUsesOneVisibleEligibleOrderAndEnterInEveryMode() {
    let a = UUID(), b = UUID()
    let weak = Target(id: .init(process: a, window: UUID()), app: "Alpha", title: "Remote configuration", address: "j", foldAddress: "aj")
    let strong = Target(id: .init(process: b, window: UUID()), app: "Beta", title: "rc", address: "k", foldAddress: "bk")
    let sibling = Target(id: .init(process: b, window: UUID()), app: "Beta", title: "recent changes", address: "l", foldAddress: "bl")
    let closed = Target(id: .init(process: UUID()), app: "rc", title: "rc", address: "c", foldAddress: "c", isRunning: false)
    let apps = [Target(id: .init(process: a), app: "Alpha", title: "Alpha", foldAddress: "a"), Target(id: .init(process: b), app: "Beta", title: "Beta", foldAddress: "b"), closed]
    var history = FocusHistory(); history.observe(strong.id); history.observe(weak.id)
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode: mode)
        state.update(.init(windows: [weak, sibling, strong], apps: apps, history: history)); state.open()
        let addresses = state.targets.map(\.address)
        _ = state.handle(.beginSearch); _ = state.handle(.query("rc"))
        #expect(state.displayMatches.first?.id == strong.id, "\(mode)")
        #expect(state.navigationItems.map(\.action) == state.displayMatches.filter(\.available).map { .target($0.id) })
        #expect(state.select(closed.id) == .none)
        for target in state.displayMatches {
            var pointer = state
            _ = pointer.handle(.highlight(.target(target.id)))
            #expect(pointer.handle(.enter) == .selected(target.id))
        }
        #expect(state.handle(.enter) == .selected(strong.id), "\(mode)")
        #expect(state.targets.map(\.address) == addresses)
        state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query(" \t"))
        #expect(!state.navigationItems.contains(.init(.target(closed.id))))
        #expect(state.handle(.enter) != .selected(closed.id))
        state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query("rc missing"))
        #expect(state.handle(.enter) == .none)
        state.open(); #expect(state.handle(.letter("c")) == .selected(closed.id), "Direct launch remains available in \(mode)")
    }
}

@Test func searchChurnPreservesIdentityAndRejectsDisappearedOrUnavailableSelection() {
    var strong = target("needle"), weak = target("needle draft")
    var state = SelectionState(); state.update(.init(windows: [weak, strong])); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("ndl"))
    _ = state.handle(.highlight(.target(weak.id)))
    strong.title = "unrelated"; state.update(.init(windows: [strong, weak]))
    #expect(state.highlightedAction == .target(weak.id))
    weak.available = false; state.update(.init(windows: [strong, weak]))
    #expect(state.handle(.enter) == .none)
    #expect(state.select(weak.id) == .none)
    weak.available = true; weak.isRunning = false; state.update(.init(windows: [weak]))
    #expect(state.displayMatches.isEmpty && state.navigationItems.isEmpty)
    #expect(state.handle(.enter) == .none)
    state.update(.init(windows: [])); #expect(state.select(strong.id) == .none)
}

@Test func rememberedSearchChoicesAreOptionalBoundedPrivateAndCannotChangeAddresses() throws {
    let a = target("Private project draft"), b = target("Private project review")
    var state = SelectionState(); state.update(.init(windows: [a,b])); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("private")); _ = state.select(b.id)
    #expect(state.searchMemory == nil)
    state.configureSearch(memory: SearchMemory()); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("private")); _ = state.select(b.id)
    let memory = try #require(state.searchMemory)
    #expect(memory.count == 1)
    state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query("private"))
    #expect(state.displayMatches.first?.id == b.id)
    #expect(state.snapshot.windows == [a,b])
    let encoded = try JSONEncoder().encode(memory)
    let serialized = String(decoding: encoded, as: UTF8.self)
    #expect(!serialized.localizedCaseInsensitiveContains("private"))
    #expect(!serialized.contains("review"))
    let restored = try JSONDecoder().decode(SearchMemory.self, from: encoded)
    #expect(restored == memory)
    var bounded = restored
    for i in 0..<200 { bounded.remember(query: "query\(i)", target: b) }
    #expect(bounded.count == SearchMemory.capacity)
    #expect(bounded.bonus(query: "private", target: b) == 0)
    #expect(bounded.bonus(query: "query199", target: b) > 0)
    // A new process/window ID with the same metadata can reuse a ranking hint only.
    let replacement = target(b.title)
    #expect(restored.bonus(query: "private", target: replacement) > 0)
    state.configureSearch(memory: nil)
    #expect(state.displayMatches.first?.id == a.id)
    var noEmpty = SearchMemory(); noEmpty.remember(query: "  ", target: a)
    #expect(noEmpty.count == 0)
}

@Test func searchConsentMigratesMissingAndMalformedValuesToOff() throws {
    var original = SettingsDocument(); original.windowActionsEnabled = false; original.mode = .fold
    let data = try JSONEncoder().encode(original)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for value: Any? in [nil, "yes", NSNull()] {
        json["rememberSearchChoices"] = value
        let decoded = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!decoded.rememberSearchChoices && decoded.mode == .fold && !decoded.windowActionsEnabled)
    }
    original.rememberSearchChoices = true
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(original)) == original)
}

@Test func memoryDecodeBoundsAndDeduplicatesEntriesAndRankingNeverOverridesAnExactMatch() throws {
    let exact = target("project"), prefix = target("project review")
    var memory = SearchMemory(); memory.remember(query: "project", target: prefix)
    let data = try JSONEncoder().encode(memory)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(json["entries"] as? [[String: String]])
    json["entries"] = Array(repeating: entries[0], count: 200) + [["query": "bad", "target": "bad"]]
    let decoded = try JSONDecoder().decode(SearchMemory.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.count == 1)
    var state = SelectionState(); state.configureSearch(memory: decoded)
    state.update(.init(windows: [prefix, exact])); state.open()
    _ = state.handle(.beginSearch); _ = state.handle(.query("project"))
    #expect(state.displayMatches.map(\.id) == [exact.id, prefix.id])
}

@Test func searchEditRevisionsAcknowledgeRepeatedAndBoundedInput() {
    var state = SelectionState(); state.open(); _ = state.handle(.beginSearch)
    for (index, query) in ["A", "AB", "A", String(repeating:"x",count:1100)].enumerated() {
        _ = state.handle(.query(query))
        #expect(state.queryRevision == UInt64(index+1))
        #expect(state.query == String(query.prefix(1024)))
    }
    _ = state.handle(.escape); _ = state.handle(.query("ignored"))
    #expect(state.queryRevision == 4)
}
