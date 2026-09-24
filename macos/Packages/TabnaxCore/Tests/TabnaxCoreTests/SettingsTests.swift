import Foundation
import Testing
@testable import TabnaxCore

@Test func validatedSettingsRoundTripAndFutureVersion() throws {
    let defaults = SettingsDocument()
    let data = try JSONEncoder().encode(defaults)
    #expect(try JSONDecoder().decode(SettingsDocument.self,from:data).validated() == defaults)
    var changed = defaults; changed.schemaVersion = 99
    #expect(throws: SettingsError.unsupportedVersion) { try changed.validated() }
    changed = defaults; changed.selection.alphabet = "jkljkl"
    #expect(throws: (any Error).self) { try changed.validated() }
    changed = defaults; changed.activation.modifiers = 0
    #expect(throws: (any Error).self) { try changed.validated() }
}
@Test func restoreScopesKeepUnrelatedPreferences() {
    for hand in [HandPreset.right,.left,.both] {
        var settings = SettingsDocument(); settings.selection.choose(hand)
        settings.selection.hand = .custom; settings.selection.alphabet = "qwerty"
        settings.selection.policy = .pairs; settings.selection.restoreOrder()
        #expect(settings.selection.alphabet == hand.alphabet)
        #expect(settings.selection.policy == .pairs)
    }
    var activation = ActivationPreferences(); activation.behavior = .hold; activation.side = .right; activation.keyCode = 1
    activation.restoreChord(); #expect(activation.keyCode == 49 && activation.behavior == .hold && activation.side == .right)
    var appearance = AppearancePreferences(); appearance.preset = .tabnax
    appearance.setColor("#112233",token:"keyBg",dark:true); appearance.setColor("#445566",token:"selection",dark:true)
    appearance.setColor("#abcdef",token:"keyBg",dark:false); appearance.resetColor("keyBg",dark:true)
    #expect(appearance.overrides["tabnax"]?["dark"]?["selection"] == "#445566")
    #expect(appearance.overrides["tabnax"]?["light"]?["keyBg"] == "#abcdef")
}
@Test func commandTabIsValidPersistsAndRestoresWithoutChangingBehavior() throws {
    var settings = SettingsDocument()
    settings.activation.behavior = .hold; settings.activation.side = .right
    settings.activation.useCommandTab()
    #expect(settings.activation.valid)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(SettingsDocument.self,from:data).validated() == settings)
    settings.activation.restoreChord()
    #expect(settings.activation == { var a = ActivationPreferences(); a.behavior = .hold; a.side = .right; return a }())
    for (code, flags): (UInt16, UInt64) in [(48,0),(48,1 << 17),(48,1 << 19),(49,1 << 20),(53,(1 << 18) | (1 << 19))] {
        settings.activation.keyCode = code; settings.activation.modifiers = flags
        #expect(!settings.activation.valid)
    }
    // A single modifier is now sufficient, as long as the key isn't reserved.
    settings.activation.keyCode = 0; settings.activation.modifiers = 1 << 20
    #expect(settings.activation.valid)
}
@Test func contrastForAllPresetsAndCustomColors() {
    for preset in ThemePreset.allCases { for dark in [true,false] { for color in ["#000000","#ffffff","#888888","#d9f68c"] {
        var p = AppearancePreferences(); p.preset = preset; p.setColor(color,token:"keyBg",dark:dark); p.setColor(color,token:"selection",dark:dark)
        let t = ThemeTokens.resolve(p,dark:dark)
        #expect(t.key.contrast(t.keyText) >= 4.5)
        #expect(t.surface.contrast(t.selection) >= 3)
    } } }
}
@Test func placementsStayInUsableScreenForEveryModeAndAnchor() {
    for mode in DisplayMode.allCases { for anchor in Anchor.allCases {
        var p = Placement.defaults(for:mode); p.anchor = anchor
        for size in [CGSize(width:800,height:600),CGSize(width:1800,height:1400)] {
            let screen = CGRect(x:-1200,y:80,width:1100,height:700)
            #expect(screen.contains(p.frame(size:size,visible:screen)))
        }
    } }
}
@Test func placementPreviewProjectsTheRealPanelForAllModesAndAnchors() {
    let screen = CGRect(x:-1600,y:100,width:1440,height:960)
    let visible = CGRect(x:-1600,y:176,width:1440,height:856)
    let canvas = CGSize(width:330,height:224)
    let scale = canvas.width/screen.width, verticalPadding = (canvas.height-screen.height*scale)/2
    for mode in DisplayMode.allCases { for anchor in Anchor.allCases { for inset in [12.0,24.0,64.0] {
        var p = Placement.defaults(for:mode); p.anchor = anchor; p.inset = inset
        let panel = p.frame(size:SwitcherGeometry.size(mode:mode,count:4),visible:visible)
        let preview = SwitcherGeometry.previewFrame(placement:p,mode:mode,count:4,screen:screen,visible:visible,canvas:canvas)
        #expect(abs(preview.minX-(panel.minX-screen.minX)*scale) < 0.001)
        #expect(abs(preview.minY-verticalPadding-(screen.maxY-panel.maxY)*scale) < 0.001)
        #expect(abs(preview.width-panel.width*scale) < 0.001)
        #expect(CGRect(origin:.zero,size:canvas).contains(preview))
    } } }
    var p = Placement(); p.anchor = .center
    let before = SwitcherGeometry.previewFrame(placement:p,mode:.shore,count:4,screen:screen,visible:visible,canvas:canvas)
    p.inset = 64
    let after = SwitcherGeometry.previewFrame(placement:p,mode:.shore,count:4,screen:screen,visible:visible,canvas:canvas)
    #expect(before.midX == after.midX && before.midY == after.midY)
}
@Test func mnemonicPairsPinsAndExhaustion() throws {
    let process = UUID(), id = TargetID(process:UUID(),window:UUID())
    var mnemonic = try AddressBook(policy:.mnemonic)
    #expect(try mnemonic.address(for:id,name:"Notes Journal") == "n")
    #expect(try mnemonic.address(for:id,name:"Changed title") == "n")
    var pairs = try AddressBook(policy:.pairs)
    let first = try pairs.address(for:id); #expect(first == "jj")
    try pairs.pin(id,to:"kk")
    #expect(pairs.allocated.contains("jj"))
    #expect(throws: (any Error).self) { try pairs.pin(TargetID(process:process),to:"jj") }
    for _ in 0..<98 { _ = try pairs.address(for:TargetID(process:process,window:UUID())) }
    #expect(throws: AlphabetError.exhausted) { try pairs.address(for:TargetID(process:process,window:UUID())) }
}
@Test func foldChildSuffixReflectsWindowTitleMnemonically() throws {
    var session = LabelSession(selection:SelectionPreferences())
    let owner = UUID()
    let app = Target(id:TargetID(process:owner),app:"Arc",title:"Arc")
    let journal = Target(id:TargetID(process:owner,window:UUID()),app:"Arc",title:"Journal")
    let notes = Target(id:TargetID(process:owner,window:UUID()),app:"Arc",title:"Notes")
    let mapped = session.map(CatalogueSnapshot(windows:[journal,notes],apps:[app]))
    #expect(mapped.windows.first{$0.id == journal.id}!.foldAddress.hasSuffix("j"))
    #expect(mapped.windows.first{$0.id == notes.id}!.foldAddress.hasSuffix("n"))
}
@Test func windowlessAppsDoNotTakeHeadLettersFromAppsThatShowWindows() throws {
    var session = LabelSession(selection:SelectionPreferences())
    // Sorted first, as the catalogue publishes them, so they would otherwise claim letters first.
    let windowless = ["Activity Monitor","Keychain Access","Messages","Xcode"].map { Target(id:TargetID(process:UUID()),app:$0,title:$0) }
    let shown = ["Arc","ChatGPT","Finder","Google Chrome","Obsidian","PhpStorm"].map { Target(id:TargetID(process:UUID()),app:$0,title:$0) }
    let windows = shown.map { Target(id:TargetID(process:$0.id.process,window:UUID()),app:$0.app,title:$0.app) }
    let mapped = session.map(CatalogueSnapshot(windows:windows,apps:windowless + shown))
    #expect(mapped.windows.allSatisfy { $0.foldAddress.count == 1 })
    #expect(mapped.windows.first{$0.app == "Google Chrome"}!.foldAddress == "o")
    let idle = Set(windowless.map(\.id))
    #expect(mapped.apps.filter { idle.contains($0.id) }.allSatisfy { $0.foldAddress.isEmpty })
    // A head appears as soon as the app has something to switch to.
    let late = Target(id:TargetID(process:windowless[3].id.process,window:UUID()),app:"Xcode",title:"Project")
    let next = session.map(CatalogueSnapshot(windows:windows + [late],apps:windowless + shown))
    #expect(next.windows.first{$0.id == late.id}!.foldAddress.count == 1)
    #expect(next.windows.prefix(shown.count).map(\.foldAddress) == mapped.windows.map(\.foldAddress))
}
@Test func wheelNeverWrapsCommitsOrUsesMomentum() throws {
    var wheel = WheelNavigation()
    #expect(wheel.steps(delta:30,precise:true,momentum:false) == 0)
    #expect(wheel.steps(delta:30,precise:true,momentum:false) == 1)
    #expect(wheel.steps(delta:100,precise:true,momentum:true) == 0)
    #expect(wheel.steps(delta:-20,precise:true,momentum:false) == 0)
    #expect(wheel.steps(delta:-20,precise:true,momentum:false) == -1)
    #expect(wheel.steps(delta:0.1,precise:false,momentum:false,horizontal:10) == 0)
    let t = Target(id:TargetID(process:UUID(),window:UUID()),app:"A",title:"B",address:"j")
    var state = SelectionState(); state.update(.init(windows:[t])); state.open()
    #expect(state.handle(.navigate(5)) == .changed); #expect(state.active && state.cursor == 0)
}
@Test func latticeNavigationChoosesVisibleBranchForATabInTheSharedPool() {
    let t = Target(id:TargetID(process:UUID(),window:UUID()),app:"Arc",title:"Tab",address:"jj")
    var state = SelectionState(); state.configure(mode:.lattice); state.update(.init(tabs:[t])); state.open()
    #expect(state.highlightedAction == .branch("j"))
    #expect(state.handle(.enter) == .changed)
    #expect(state.handle(.enter) == .selected(t.id))
}

@Test func wheelGesturesRequireAnOwnedStartAndKeepTheirFoldRegion() {
    var gesture = WheelGesture()
    #expect(gesture.navigate(region:nil,phase:.began,delta:40,precise:true,momentum:false) == nil)
    #expect(gesture.navigate(region:"targets",phase:.changed,delta:80,precise:true,momentum:false) == nil)
    #expect(gesture.navigate(region:"family",phase:.began,delta:30,precise:true,momentum:false) == nil)
    let move = gesture.navigate(region:"targets",phase:.changed,delta:30,precise:true,momentum:false)
    #expect(move?.region == "family" && move?.steps == 1)
    #expect(gesture.navigate(region:"targets",phase:.changed,delta:80,precise:true,momentum:true) == nil)
    gesture.reset() // A prefix, search, scope or session change invalidates the gesture.
    #expect(gesture.navigate(region:"targets",phase:.changed,delta:80,precise:true,momentum:false) == nil)
    #expect(gesture.navigate(region:"targets",phase:.unphased,delta:1,precise:false,momentum:false)?.steps == 1)
    #expect(gesture.navigate(region:"targets",phase:.changed,delta:80,precise:true,momentum:false) == nil)
}

@Test func labelTransactionsRetainFiltersAndRejectIncompatiblePins() throws {
    let process = UUID(), a = TargetID(process:process,window:UUID()), b = TargetID(process:process,window:UUID())
    var source = CatalogueSnapshot(windows:[Target(id:a,app:"A",title:"One"),Target(id:b,app:"A",title:"Two",hidden:true)],apps:[Target(id:TargetID(process:process),app:"A",title:"A")])
    var session = LabelSession(); let original = session.map(source)
    // Windows prefer name letters, then keyboard order, before the app claims a code.
    #expect(original.windows.map(\.address) == ["o","j"])
    source.windows[1].hidden = false
    #expect(session.map(source).windows[1].address == "j")
    try session.pin(a,code:"h")
    var selection = session.selection; selection.choose(.left)
    #expect(throws:(any Error).self) { try session.changing(to:selection,source:source) }
    let reset = try session.changing(to:selection,source:source,reset:true)
    #expect(reset.pins.isEmpty && reset.selection.alphabet == HandPreset.left.alphabet)
    // Undo is a value copy; reconcile never reopens or recreates removed targets.
    source.windows.removeFirst(); var restored = session
    #expect(restored.map(source).windows.map(\.id) == [b])
    #expect(restored.pool.allocated.contains("h"))
}
@Test func policyChangesFlatAndAppLabelsAndExhaustedTargetsRemainVisible() throws {
    let process = UUID(),app = Target(id:TargetID(process:process),app:"A",title:"A")
    let source = CatalogueSnapshot(windows:(0..<42).map { Target(id:TargetID(process:process,window:UUID()),app:"A",title:"Window \($0)") },apps:[app])
    var session = LabelSession(); let old = session.map(source)
    // The pool alphabet gets a hidden filler letter appended (see AddressBook.extended),
    // giving it 40 codes instead of 36; windows take priority over the app row.
    #expect(old.windows.count == 42 && old.windows.filter { $0.address.isEmpty }.count == 2)
    #expect(old.apps[0].address.isEmpty)
    var selection = session.selection; selection.policy = .pairs
    var next = try session.changing(to:selection,source:source)
    let mapped = next.map(source)
    // The app's Fold/Canopy head letter lives in its own dedicated book, so a flat-pool
    // policy change (which only affects window/app pool addresses) leaves it untouched.
    #expect(mapped.windows.map(\.foldAddress) == old.windows.map(\.foldAddress))
    #expect(mapped.windows.allSatisfy { $0.address.count == 2 })
    #expect(mapped.apps.allSatisfy { $0.address.count == 2 })
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode:mode); state.update(old); state.open(); _ = state.handle(.beginSearch); _ = state.handle(.query("Window 41"))
        #expect(state.handle(.enter) == .selected(source.windows[41].id))
    }
}
@Test func allLettersModeAssignsAppsByNameInitial() throws {
    var selection = SelectionPreferences(); selection.choose(.all); selection.policy = .mnemonic
    #expect(selection.alphabet.utf8.count == 26)
    var session = LabelSession(selection:selection)
    let slack = Target(id:TargetID(process:UUID()),app:"Slack",title:"Slack")
    let safari = Target(id:TargetID(process:UUID()),app:"Safari",title:"Safari")
    let mapped = session.map(CatalogueSnapshot(apps:[slack,safari]))
    #expect(mapped.apps.first { $0.app == "Slack" }?.address == "s")
    #expect(mapped.apps.first { $0.app == "Safari" }?.address == "a")
}
@Test(arguments: [AssignmentPolicy.stable, .mnemonic])
func nameInitialsAreSelectableInEveryLayout(policy: AssignmentPolicy) {
    var selection = SelectionPreferences(); selection.choose(.all); selection.policy = policy
    let apps = ["Obsidian", "Notes", "Mail"].map { Target(id:.init(process:UUID()),app:$0,title:$0) }
    let windows = zip(apps, ["Document", "Project", "Work"]).map { app, title in
        Target(id:.init(process:app.id.process,window:UUID()),app:app.app,title:title)
    }
    let source = CatalogueSnapshot(windows:windows,apps:apps)
    var session = LabelSession(selection:selection)
    let mapped = session.map(source)
    #expect(mapped.windows.map(\.address) == ["o", "n", "m"])
    let codes = (mapped.windows + mapped.apps).map(\.address)
    #expect(Set(codes).count == codes.count)
    for mode in DisplayMode.allCases {
        var state = SelectionState(); state.configure(mode:mode); state.update(mapped)
        for (index, letter) in ["o", "n", "m"].enumerated() {
            state.open()
            #expect(state.handle(.letter(letter)) == .selected(windows[index].id))
        }
    }
    var reordered = source; reordered.apps.reverse(); reordered.windows.reverse()
    reordered.windows[0].title = "Renamed"
    let updated = session.map(reordered)
    for target in mapped.apps + mapped.windows {
        #expect((updated.apps + updated.windows).first { $0.id == target.id }?.address == target.address)
    }
}
@Test(arguments: [AssignmentPolicy.stable, .mnemonic])
func nameBasedLettersFallBackWithoutCollisions(policy: AssignmentPolicy) throws {
    var book = try AddressBook(policy:policy)
    let notes = TargetID(process:UUID())
    #expect(try book.address(for:notes,name:"Notes") == "n")
    #expect(try book.address(for:.init(process:UUID()),name:"Numbers Journal") == "j")
    #expect(try book.address(for:.init(process:UUID()),name:"Notes") == "o")
    #expect(try book.address(for:.init(process:UUID()),name:"XYZ") == "k")
    #expect(try book.address(for:notes,name:"Renamed") == "n")
}
@Test func defaultWindowAndTabLabelsPreferTheirAppBeforeTheirTitle() {
    let window = Target(id:.init(process:UUID(),window:UUID()),app:"Notes",title:"Journal")
    let tab = Target(id:.init(process:UUID(),window:UUID()),app:"Mail",title:"Inbox")
    let apps = [window, tab].map { Target(id:.init(process:$0.id.process),app:$0.app,title:$0.app) }
    var session = LabelSession()
    let mapped = session.map(.init(windows:[window],apps:apps,tabs:[tab]))
    #expect(mapped.windows[0].address == "n")
    #expect(mapped.tabs[0].address == "m")
    for mode in [DisplayMode.shore, .beacons, .lattice, .relay] {
        var state = SelectionState(); state.configure(mode:mode); state.update(mapped); state.open()
        #expect(state.handle(.letter("n")) == .selected(window.id))
        state.open()
        #expect(state.handle(.letter("m")) == .selected(tab.id))
    }
}
@Test func browserProtocolRejectsPrivateDuplicateAndOversizeMessages() throws {
    let tab = BrowserTabRecord(id:"1",window:"2",title:"Same title")
    let valid = BrowserMessage(kind:"snapshot",connection:UUID().uuidString,tabs:[tab],browser:.zen)
    #expect(try valid.validated().tabs?.count == 1)
    var privateMessage = valid; privateMessage.tabs?[0].incognito = true
    #expect(throws:(any Error).self) { try privateMessage.validated() }
    var duplicate = valid; duplicate.tabs = [tab,tab]
    #expect(throws:(any Error).self) { try duplicate.validated() }
    var unknown = valid; unknown.version = 2
    #expect(throws:(any Error).self) { try unknown.validated() }
}
@Test func activeSessionFreezesIdentityButReconcilesLiveness() {
    let a = Target(id:TargetID(process:UUID(),window:UUID()),app:"A",title:"Before",address:"j")
    let b = Target(id:TargetID(process:UUID(),window:UUID()),app:"B",title:"New",address:"k")
    let old = CatalogueSnapshot(windows:[a]); var renamed = a; renamed.title = "After"
    let next = old.reconcilingLive(.init(windows:[renamed,b]))
    #expect(next.windows.map(\.id) == [a.id]); #expect(next.windows[0].title == "After")
    let closed = old.reconcilingLive(.init(windows:[b])); #expect(!closed.windows[0].available)
    var remapped = a; remapped.address = "k"
    #expect(!old.reconcilingLive(.init(windows:[remapped])).windows[0].available)
}

@Test func poolAndFoldResetsPreserveEachOthersPins() throws {
    // Windows and tabs now share one pool namespace; only .pool and .fold remain independently resettable.
    let p = UUID(), window = TargetID(process:p,window:UUID()), tab = TargetID(process:UUID(),window:UUID())
    let source = CatalogueSnapshot(windows:[Target(id:window,app:"A",title:"Window")],apps:[Target(id:TargetID(process:p),app:"A",title:"A")],tabs:[Target(id:tab,app:"Arc",title:"Tab")])
    var labels = LabelSession()
    let tabAddress = labels.map(source).tabs[0].address
    try labels.pin(window,code:"h"); try labels.pin(window,code:"jk",fold:true)
    try labels.pin(tab,code:tabAddress,namespace:.pool)
    let before = labels.map(source)
    var foldReset = labels.resetting(.fold); let after = foldReset.map(source)
    #expect(after.windows[0].address == before.windows[0].address && after.tabs[0].address == tabAddress)
    #expect(foldReset.foldPins.isEmpty && foldReset.pins == labels.pins)
    let poolReset = labels.resetting(.pool)
    #expect(poolReset.pins.isEmpty && poolReset.foldPins == labels.foldPins)
    var changed = labels.selection; changed.alphabet = "asdfgh"
    #expect(throws:(any Error).self) { try labels.changing(to:changed,source:source) }
    var closed = source; closed.tabs = []; _ = labels.map(closed)
    #expect(!labels.pins.keys.contains(tab) && labels.pool.allocated.contains(tabAddress))
}

@Test func flatPinsAnchorToTheAppsFixedLetterAndSurviveAlphabetChanges() throws {
    let process = UUID(), bundleID = "com.acme.A"
    var selection = SelectionPreferences()
    selection.appShortcuts.enabled = true
    // "y" (not "z") is the outside-alphabet example here: "z" is this alphabet's own
    // hidden overflow filler (see AddressBook.extended), so it can't be a fixed app letter.
    selection.appShortcuts.assignments = [AppAssignment(bundleID:bundleID,name:"A",path:"/Applications/A.app",letter:"y")]
    let window = TargetID(process:process,window:UUID()), sibling = TargetID(process:process,window:UUID())
    let source = CatalogueSnapshot(
        windows:[Target(id:window,app:"A",title:"One",bundleID:bundleID),Target(id:sibling,app:"A",title:"Two",bundleID:bundleID)],
        apps:[Target(id:TargetID(process:process),app:"A",title:"A",bundleID:bundleID)])
    var session = LabelSession(selection:selection)
    let head = session.map(source).apps.first?.address ?? ""
    #expect(head == "y")
    // A flat pin for a window whose app has a fixed letter must start with that letter.
    #expect(throws:(any Error).self) { try session.pin(window,code:"k") }
    try session.pin(window,code:head + "k")
    let mapped = session.map(source)
    #expect(mapped.windows.first { $0.id == window }?.address == head + "k")
    // The unpinned sibling still gets an ordinary flat pool address, not anchored to the app letter.
    #expect(mapped.windows.first { $0.id == sibling }?.address.hasPrefix(head) == false)
    // Reassigning the app to a different fixed letter invalidates the now-stale flat pin.
    var reassigned = session.selection
    reassigned.appShortcuts.assignments = [AppAssignment(bundleID:bundleID,name:"A",path:"/Applications/A.app",letter:"x")]
    #expect(throws:(any Error).self) { try session.changing(to:reassigned,source:source) }
    let reset = try session.changing(to:reassigned,source:source,reset:true)
    #expect(reset.pins.isEmpty)
    // An alphabet change that still allows the pin's suffix letter migrates it onto the new app head.
    var realphabetized = session.selection; realphabetized.choose(.both)
    var migrated = try session.changing(to:realphabetized,source:source)
    let migratedHead = migrated.map(source).apps.first?.address ?? ""
    #expect(migratedHead == head)
    #expect(migrated.map(source).windows.first { $0.id == window }?.address == migratedHead + "k")
    // An alphabet change that drops the suffix letter entirely is rejected, same as Fold pins.
    var incompatible = session.selection; incompatible.choose(.left)
    #expect(throws:(any Error).self) { try session.changing(to:incompatible,source:source) }
}

@Test func displayChoiceIsOneSettingForEveryMode() throws {
    var document = SettingsDocument()
    var beacons = Placement.defaults(for: .beacons); beacons.display = .main
    document.positions[DisplayMode.beacons.rawValue] = beacons
    // A document saved before the shared choice existed keeps what each mode stored.
    let legacy = try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(document))
    #expect(legacy.display == nil)
    #expect(legacy.placement(for: .beacons).display == .main)
    #expect(legacy.placement(for: .fold).display == .focused)
    document.display = .pointer
    for mode in DisplayMode.allCases { #expect(document.placement(for: mode).display == .pointer) }
    // Anchor and inset stay per mode.
    #expect(document.placement(for: .beacons).anchor == beacons.anchor)
    let saved = try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(document.validated()))
    #expect(saved.display == .pointer)
}

@Test func cursorMovementPersistsAndOlderSettingsDefaultToOff() throws {
    var settings = SettingsDocument()
    #expect(!settings.moveCursorToSelectedWindow)
    settings.moveCursorToSelectedWindow = true
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: data).validated() == settings)
    var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "moveCursorToSelectedWindow")
    let restored = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: legacy))
    settings.moveCursorToSelectedWindow = false
    #expect(restored == settings)
}

@Test func searchShortcutOptInMigrationAndRoundTrip() throws {
    var settings = SettingsDocument(); settings.mode = .fold; settings.traversalOrder = .recent
    #expect(!settings.searchActivation.enabled)
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
    for bad: Any? in [nil, "invalid", ["enabled": true], ["enabled": "true", "shortcut": [:]]] {
        json["searchActivation"] = bad
        let migrated = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: json)).validated()
        #expect(!migrated.searchActivation.enabled); #expect(migrated.mode == .fold)
    }
    settings.searchActivation.enabled = true; settings.searchActivation.shortcut.side = .right
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(settings)).validated() == settings)
}

@Test func activationConflictIncludesModifierSideOverlap() throws {
    for mainSide in ModifierSide.allCases {
        for searchSide in ModifierSide.allCases {
            var settings = SettingsDocument()
            settings.activation.side = mainSide
            settings.searchActivation.shortcut = settings.activation
            settings.searchActivation.shortcut.side = searchSide
            #expect(throws: Never.self) { try settings.validated() } // Disabled is inert.
            settings.searchActivation.enabled = true
            let overlap = mainSide == .either || searchSide == .either || mainSide == searchSide
            #expect((try? settings.validated()) == (overlap ? nil : settings))
        }
    }
}

@Test func shiftOnlyPrintableChordsRejectedButLegacySettingsRecover() throws {
    for key: UInt16 in [0, 49, 18, 41, 65, 93] {
        var settings = SettingsDocument(); settings.mode = .relay; settings.includeHidden = false
        settings.activation.keyCode = key; settings.activation.modifiers = 1 << 17
        settings.activation.behavior = .hold; settings.activation.side = .right
        #expect(throws: (any Error).self) { try settings.validated() }
        let migrated = try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(settings)).validated()
        #expect(migrated.activation.keyCode == 49 && migrated.activation.modifiers == ActivationPreferences().modifiers)
        #expect(migrated.activation.behavior == .hold && migrated.activation.side == .right)
        #expect(migrated.mode == .relay && !migrated.includeHidden && !migrated.searchActivation.enabled)
        settings = .init(); settings.searchActivation.shortcut.keyCode = key; settings.searchActivation.shortcut.modifiers = 1 << 17
        #expect(throws: (any Error).self) { try settings.validated() }
    }
    var function = ActivationPreferences(); function.modifiers = 1 << 17; function.keyCode = 90
    #expect(function.valid)
}

@Test func simultaneousDisplaysAreOptInAndPreserveLegacyPlacement() throws {
    var settings = SettingsDocument(); settings.display = .pointer
    settings.positions["fold"] = .defaults(for: .fold)
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
    for malformed in [NSNull(), "true", 1] as [Any] {
        object["allDisplays"] = malformed
        let decoded = try JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: object)).validated()
        #expect(!decoded.allDisplays && decoded.placement(for: .fold).display == .pointer)
    }
    object.removeValue(forKey: "allDisplays")
    #expect(try !JSONDecoder().decode(SettingsDocument.self, from: JSONSerialization.data(withJSONObject: object)).allDisplays)
    settings.allDisplays = true
    #expect(try JSONDecoder().decode(SettingsDocument.self, from: JSONEncoder().encode(settings)).validated() == settings)
    #expect(settings.placement(for: .fold).anchor == .center)
}
