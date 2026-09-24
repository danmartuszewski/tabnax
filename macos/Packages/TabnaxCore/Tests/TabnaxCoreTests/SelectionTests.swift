import Foundation
import Testing
@testable import TabnaxCore

private func fixture(_ count: Int = 10) throws -> [Target] {
    var book = try AddressBook(); let process = UUID()
    return try (0..<count).map { i in
        let id = TargetID(process: process, window: UUID())
        return Target(id: id, app: "Fixture", title: "Duplicate title", address: try book.address(for: id), minimized: i == 7)
    }
}
@Test func sixEightTenAndImmediateOverflow() throws {
    for count in [6, 8, 10] {
        let targets = try fixture(count)
        var state = SelectionState(); state.update(.init(windows: targets)); state.open()
        for letter in targets.last!.address { _ = state.handle(.letter(String(letter))) }
        #expect(!state.active)
        #expect(targets.prefix(9).allSatisfy { $0.address.count == 1 })
    }
    var state = SelectionState(); let targets = try fixture(); state.update(.init(windows: targets)); state.open()
    #expect(state.handle(.letter("p")) == .changed)
    #expect(state.handle(.letter("j")) == .selected(targets[9].id)) // No render/open completion.
    #expect(state.handle(.letter("j"), repeated: true) == .none)
}
@Test func prefixFreeAndBoundedRetirement() throws {
    var book = try AddressBook(); let process = UUID()
    var codes: [String] = []
    for _ in 0..<36 {
        let id = TargetID(process: process, window: UUID())
        codes.append(try book.address(for: id)); book.retain(live: [])
    }
    #expect(Set(codes).count == 36)
    #expect(codes.allSatisfy { $0.count <= 4 })
    for a in codes { #expect(!codes.contains { $0 != a && $0.hasPrefix(a) }) }
    #expect(throws: AlphabetError.exhausted) { try book.address(for: TargetID(process: process, window: UUID())) }
}
@Test func titleReorderAndChurn() throws {
    var targets = try fixture(); var state = SelectionState(); state.update(.init(windows: targets)); state.open()
    _ = state.handle(.letter("p")); targets[0].title = "Renamed"
    state.update(.init(revision: 1, windows: targets.reversed())); #expect(state.prefix == "p")
    targets.removeLast(); state.update(.init(revision: 2, windows: targets)); #expect(state.prefix.isEmpty)
    #expect(state.handle(.letter("p")) == .none)
}
@Test func cancellationNavigationAndAvailability() throws {
    var targets = try fixture(); targets[0].available = false
    var state = SelectionState(); state.update(.init(windows: targets)); state.open()
    #expect(state.handle(.letter("j")) == .none); #expect(state.active)
    _ = state.handle(.letter("p")); #expect(state.handle(.escape) == .changed); #expect(state.active)
    _ = state.handle(.next); #expect(state.handle(.enter) == .selected(targets[2].id))
    state.open(); #expect(state.handle(.escape) == .cancelled)
    state.open(); _ = state.handle(.letter("p")); _ = state.handle(.backspace); #expect(state.prefix.isEmpty)
    #expect(state.handle(.letter("J")) == .none)
}
@Test func processLifetimesAndAlphabetReset() throws {
    var book = try AddressBook(); let old = TargetID(process: UUID(), window: UUID())
    #expect(try book.address(for: old) == "j")
    #expect(try book.address(for: old) == "j")
    book.retain(live: [])
    #expect(try book.address(for: TargetID(process: UUID(), window: UUID())) == "k")
    book = try AddressBook(alphabet: AddressBook.leftHand)
    #expect(try book.address(for: old) == "a")
    for bad in ["abc", "jjklui", "ąsdfgh", "ASDFGH"] { #expect(throws: AlphabetError.invalid) { try AddressBook(alphabet: bad) } }
}
@Test func returningIdentityReclaimsHeldCodeEvenWhenVocabularyIsFull() throws {
    var book = try AddressBook(alphabet: "abcdef")
    let ids = book.vocabulary.map { _ in TargetID(process: UUID(), window: UUID()) }
    let codes = try ids.map { try book.address(for: $0) }
    for _ in 0..<100 {
        book.retain(live: [])
        #expect(book.assignments.isEmpty)
        #expect(try ids.map { try book.address(for: $0) } == codes)
        #expect(book.allocatedCount == codes.count)
    }
    // Reclaiming a code never hands it to a different window/process lifetime.
    book.retain(live: [])
    #expect(throws: AlphabetError.exhausted) { try book.address(for: TargetID(process: UUID(), window: UUID())) }
}

@Test func displayMigrationPreservesShortcutsAcrossTemporaryOmissions() throws {
    let process = UUID()
    let app = Target(id: TargetID(process: process), app: "Arc", title: "Arc")
    let windows = ["Toggl Track", "Merge Requests", "Article"].enumerated().map { index, title in
        Target(id: TargetID(process: process, window: UUID()), app: "Arc", title: title,
               bounds: CGRect(x: 1920 + index * 100, y: 100, width: 900, height: 700))
    }
    var labels = LabelSession()
    let original = labels.map(.init(windows: windows, apps: [app]))
    let allocations = labels.pool.allocatedCount
    for cycle in 0..<100 {
        // App stays running while its windows are temporarily absent from discovery.
        _ = labels.map(.init(apps: [app]))
        let moved = windows.reversed().map { window in
            var window = window
            window.bounds = CGRect(x: cycle.isMultiple(of: 2) ? 20 : 1920, y: 40, width: 900, height: 700)
            return window
        }
        let restored = labels.map(.init(windows: moved, apps: [app]))
        #expect(labels.pool.allocatedCount == allocations)
        for window in restored.windows {
            let before = try #require(original.windows.first { $0.id == window.id })
            #expect(!window.address.isEmpty && window.address == before.address)
            #expect(!window.foldAddress.isEmpty && window.foldAddress == before.foldAddress)
            for mode in DisplayMode.allCases {
                var state = SelectionState(); state.configure(mode: mode); state.update(restored); state.open()
                let code = mode == .fold || mode == .canopy ? window.foldAddress : window.address
                var effect = SelectionEffect.none
                for letter in code { effect = state.handle(.letter(String(letter))) }
                #expect(effect == .selected(window.id))
            }
        }
    }
}
@Test func keyupAndRepeatDoNotLeakAfterSelection() {
    var keys = KeyOwnership(); keys.claim(38)
    #expect(keys.contains(38)); let owned = keys.release(38); let again = keys.release(38)
    #expect(owned); #expect(!again)
    keys.claim(49); keys.reset(); #expect(!keys.contains(49))
}
@Test func flatPoolSelectsAppsAlongsideWindowsAndDropsStaleSelection() throws {
    let windows = try fixture(); var state = SelectionState()
    let app = Target(id: TargetID(process: UUID()), app: "App", title: "App", address: "z")
    state.update(.init(windows: windows, apps: [app])); state.open()
    #expect(state.handle(.letter("z")) == .selected(app.id))
    state.open(); state.update(.init()); #expect(state.select(app.id) == .none)
}
