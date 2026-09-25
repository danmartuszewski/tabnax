import AppKit
import SwiftUI
import Combine
import ServiceManagement
import UniformTypeIdentifiers
@preconcurrency import ApplicationServices
import TabnaxCore

enum SettingsPane: Int, CaseIterable, Identifiable {
    // Keep existing render/test IDs stable while placing Apps beside Letters.
    case general = 0, letters = 1, apps = 5, exclusions = 6, position = 2, appearance = 3, browsers = 4
    var id: Int { rawValue }
    var title: String {
        switch self { case .general: String(localized:"General"); case .letters: String(localized:"Letters"); case .apps: String(localized:"Apps"); case .exclusions: String(localized:"Exclusions"); case .position: String(localized:"Position"); case .appearance: String(localized:"Appearance"); case .browsers: String(localized:"Browser tabs") }
    }
    var symbol: String {
        switch self { case .general: "gearshape"; case .letters: "keyboard"; case .apps: "square.grid.2x2"; case .exclusions: "line.3.horizontal.decrease.circle"; case .position: "rectangle.inset.filled"; case .appearance: "paintpalette"; case .browsers: "globe" }
    }
    var detail: String {
        switch self {
        case .general: String(localized:"Choose how to open the switcher and which windows to include.")
        case .letters: String(localized:"Choose the keys used to select windows, tabs and apps.")
        case .apps: String(localized:"Keep familiar app letters and optionally use them to launch apps.")
        case .exclusions: String(localized:"Hide selected apps or titles, and let chosen foreground apps keep their shortcuts.")
        case .position: String(localized:"Choose a layout, then place it on your screen.")
        case .appearance: String(localized:"Personalize the switcher’s theme, colors and label size.")
        case .browsers: String(localized:"Bring browser tabs into the switcher alongside your windows.")
        }
    }
}

/// Reference-identity comparison for icon caches: `IconCache`/`ApplicationShortcuts.icons`
/// return the same NSImage instance for an unchanged source, so this is cheaper and safer
/// than requiring NSImage: Equatable, and avoids republishing `icons` when nothing changed.
private func iconsEqual(_ lhs: [UUID:NSImage], _ rhs: [UUID:NSImage]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key,value) in lhs { guard let other = rhs[key], other === value else { return false } }
    return true
}

@MainActor final class SettingsModel: ObservableObject {
    let preferences: Preferences
    @Published private(set) var pane = SettingsPane.general
    @Published var draft: SelectionPreferences
    @Published private(set) var resetNamespace: LabelNamespace?
    @Published var labelError = ""
    @Published var appError = ""
    @Published var status = ""
    @Published var previewState = SelectionState()
    @Published var previewMessage = String(localized:"Sample windows, tabs and apps")
    @Published var raw = CatalogueSnapshot()
    @Published var icons: [UUID:NSImage] = [:]
    @Published var sourceIsSample = true
    @Published var pinTarget: TargetID?
    @Published var pinCode = ""
    @Published var colorToneDark = false
    enum RecordingTarget { case main, search }
    @Published private(set) var recordingTarget: RecordingTarget?
    @Published var recording = false
    private(set) var recordingSession: UUID?
    @Published var loginStatus = ""
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginError = ""
    private let loginService: LoginItemService
    @Published var browserStatus: [BrowserID: String] = [:]
    @Published var isFirstRun = false
    /// Document fields whose change actually affects `refreshPreview()`'s target list
    /// (which windows/tabs/apps are shown) — as opposed to purely cosmetic fields like
    /// theme color or position, which never need to rerun the preview pipeline.
    static let previewRelevantKeyPaths: Set<AnyKeyPath> = [
        \SettingsDocument.mode,
        \SettingsDocument.traversalOrder,
        \SettingsDocument.includeMinimized,
        \SettingsDocument.includeHidden,
        \SettingsDocument.browsers.enabled,
        \SettingsDocument.browsers.range,
        \SettingsDocument.browsers.automatic,
    ]
    var liveSession = LabelSession()
    var candidate = LabelSession()
    var onApply: ((LabelSession) -> Void)?
    var onRetry: (() -> Void)?
    var onRestart: (() -> Void)?
    var onConnect: ((BrowserID) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private var recorder: Any?
    private var hasPinDraft = false
    init(preferences: Preferences, loginService: LoginItemService = LoginItemService()) {
        self.loginService = loginService
        self.preferences = preferences; draft = preferences.document.selection
        colorToneDark = preferences.document.appearance.source == .dark || (preferences.document.appearance.source == .system && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua)
        raw = Self.samples(); icons = Self.sampleIcons(); liveSession = LabelSession(selection:draft); candidate = liveSession
        refreshPreview(); refreshLogin(); updateChangedLabelsCount()
    }
    /// Cached result of the label-diff below, recomputed only at the specific points
    /// where `liveSession`/`candidate`/`raw` actually change — not on every SwiftUI render.
    @Published private(set) var changedLabelsCount = 0
    var changedLabels: Int { changedLabelsCount }
    private func updateChangedLabelsCount() {
        // The count is only shown for a draft; skip two full label mappings on every
        // catalogue update while Settings is open without one.
        guard dirty else { if changedLabelsCount != 0 { changedLabelsCount = 0 }; return }
        var old = liveSession, next = candidate
        let before = old.map(ApplicationShortcuts.includingClosedApps(raw,preferences:old.selection.appShortcuts))
        let after = next.map(ApplicationShortcuts.includingClosedApps(raw,preferences:next.selection.appShortcuts))
        let entries = Dictionary((before.windows + before.tabs + before.apps).map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        changedLabelsCount = (after.windows + after.tabs + after.apps).reduce(0) { count,t in
            let code = labelNamespace == .fold ? t.foldAddress : t.address
            guard let previous = entries[t.id] else { return count + (code.isEmpty ? 0 : 1) }
            let previousCode = labelNamespace == .fold ? previous.foldAddress : previous.address
            return count + (previousCode != code ? 1 : 0)
        }
    }
    var resetAssignments: Bool { resetNamespace != nil }
    var dirty: Bool { draft != preferences.document.selection || resetAssignments || hasPinDraft }
    var labelNamespace: LabelNamespace { [.fold, .canopy].contains(preferences.document.mode) ? .fold : .pool }
    var labelSetTitle: String { labelNamespace == .fold ? String(localized:"Fold & Canopy") : String(localized:"windows, tabs & apps") }
    /// The app letter a pin for the current target must start with, when its app has one
    /// assigned in Apps → App letters (Fold and flat pins both anchor to it).
    var pinPrefix: String? {
        guard let id = pinTarget else { return nil }
        let owner = (raw.windows + raw.tabs + raw.apps).first(where:{$0.id == id})?.groupOwner ?? id.process
        guard let app = raw.apps.first(where:{$0.id.process == owner}) else { return nil }
        return draft.appShortcuts.assignment(for:app)?.letter
    }
    private func stagedSession() throws -> LabelSession {
        var base = hasPinDraft ? candidate : liveSession
        if let resetNamespace, !hasPinDraft { base = base.resetting(resetNamespace) }
        let source = ApplicationShortcuts.includingClosedApps(sourceIsSample ? Self.samples() : raw,preferences:draft.appShortcuts).resolvingTabOwners()
        return try base.changing(to:draft,source:source)
    }
    func selectPane(_ value: SettingsPane) {
        stopRecorder(); pane = value
    }
    var availableAppLetters: [String] {
        let used = Set(draft.appShortcuts.assignments.map(\.letter))
        var seen = Set<String>()
        return (draft.alphabet + "abcdefghijklmnopqrstuvwxyz").map(String.init).filter {
            "abcdefghijklmnopqrstuvwxyz".contains($0) && seen.insert($0).inserted && !used.contains($0)
                && !AppShortcutPreferences.reservesPoolAddress($0,alphabet:draft.alphabet,policy:draft.policy)
        }
    }
    func stageApps() {
        appError = ""
        stage()
    }
    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = String(localized:"Assign an application letter")
        panel.message = String(localized:"Choose an app to keep under a familiar letter.")
        panel.prompt = String(localized:"Add application")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:"/Applications",isDirectory:true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addApplication(at:url)
        }
    }
    func addAppRule(bundleID: String, name: String = "", exception: Bool) {
        let rule = AppRule(bundleID: bundleID, name: name)
        guard AppRule.validBundleID(bundleID) else { appError = "Enter a valid bundle ID."; return }
        let rules = exception ? preferences.document.exclusions.shortcutExceptions : preferences.document.exclusions.apps
        guard !rules.contains(where: { $0.bundleID == bundleID }) else { appError = "That bundle ID is already in this list."; return }
        appError = ""
        change {
            if exception { $0.exclusions.shortcutExceptions.append(rule) }
            else { $0.exclusions.apps.append(rule) }
        }
    }
    func chooseRuleApplication(exception: Bool) {
        let panel = NSOpenPanel()
        panel.title = exception ? "Let an app keep activation shortcuts" : "Exclude an application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let identity = try ApplicationShortcuts.identity(at: url)
                self?.addAppRule(bundleID: identity.bundleID, name: identity.name, exception: exception)
            } catch { self?.appError = error.localizedDescription }
        }
    }
    func addApplication(at url: URL) {
        do {
            let identity = try ApplicationShortcuts.identity(at:url)
            guard !draft.appShortcuts.assignments.contains(where:{$0.bundleID == identity.bundleID}) else {
                throw SettingsError.invalid(String(localized:"\(identity.name) already has a letter. Edit its existing assignment."))
            }
            let candidates = availableAppLetters
            // Prefer a letter that actually connects to the app's name — its word initials
            // first, then any other letter it contains — before falling back to comfort order,
            // so a fixed app letter reads the same as the mnemonic addresses everywhere else.
            let lowered = identity.name.lowercased()
            let initials = lowered.split(whereSeparator: { !$0.isLetter }).compactMap { $0.first.map(String.init) }
            guard let letter = initials.first(where:candidates.contains)
                ?? lowered.compactMap({ $0.isLetter ? String($0) : nil }).first(where:candidates.contains)
                ?? candidates.first else {
                throw SettingsError.invalid(String(localized:"Every available app letter is assigned. Remove an assignment first."))
            }
            let app = AppAssignment(bundleID:identity.bundleID,name:identity.name,path:identity.path,letter:letter)
            AppAssignmentCache.invalidate(identity.bundleID)
            draft.appShortcuts.assignments.append(app); stageApps()
        } catch { appError = error.localizedDescription }
    }
    var previewDocument: SettingsDocument { var d = preferences.document; d.selection = labelError.isEmpty ? draft : candidate.selection; if pane == .appearance { d.appearance.source = colorToneDark ? .dark : .light }; return d }
    /// - Parameter preview: Whether this mutation can change `refreshPreview()`'s target
    ///   list (mode, included apps/browsers, search scope) as opposed to a cosmetic-only
    ///   field (theme color, position/inset, etc). Slider/color bindings fire continuously
    ///   while dragging, so skipping the preview rerun for cosmetic fields avoids rerunning
    ///   the full target pipeline dozens of times a second for changes that can't affect it.
    func change(preview: Bool = true, _ body: (inout SettingsDocument) -> Void) {
        var d = preferences.document; body(&d)
        let oldSource = preferences.document.appearance.source
        if preferences.commit(d) {
            if d.appearance.source != oldSource { colorToneDark = d.appearance.source == .dark || (d.appearance.source == .system && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua) }
            if preview { refreshPreview() }
        }
    }
    func stage() {
        do {
            candidate = try stagedSession()
            labelError = ""; refreshPreview(usingCandidate:true); updateChangedLabelsCount()
        } catch {
            labelError = error as? AlphabetError == .invalid
                ? String(localized:"Use 6–26 different letters A–Z, without duplicates.")
                : error.localizedDescription
            refreshPreview(usingCandidate:true); updateChangedLabelsCount()
            previewMessage = String(localized:"Last valid letters · fix the draft to apply")
        }
    }
    func discard() {
        draft = preferences.document.selection; resetNamespace = nil; hasPinDraft = false; labelError = ""; appError = ""; candidate = liveSession
        let source = preferences.document.appearance.source
        colorToneDark = source == .dark || (source == .system && NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua)
        refreshPreview(); updateChangedLabelsCount()
    }
    func resetLabels() { hasPinDraft = false; resetNamespace = labelNamespace; stage() }
    func apply() {
        guard labelError.isEmpty else { return }
        do {
            // Revalidate against the newest observed identities before publication.
            var plan = try stagedSession()
            if sourceIsSample { plan = try LabelSession(selection:draft).changing(to:draft,source:.init()) }
            _ = plan.map(sourceIsSample ? .init() : raw)
            var d = preferences.document; d.selection = draft
            guard preferences.commit(d,message:String(localized:"Letters applied. Undo is available."),forceCheckpoint:true) else { return }
            onApply?(plan); liveSession = plan; discard()
        } catch { labelError = error.localizedDescription }
    }
    func pin() {
        guard let id = pinTarget, (raw.windows + raw.tabs + raw.apps).contains(where:{$0.id == id}) else { labelError = String(localized:"Choose a current target to pin."); return }
        do {
            var plan = candidate
            try plan.pin(id,code:SelectionPreferences.normalize(pinCode),namespace:labelNamespace)
            candidate = plan; hasPinDraft = true; labelError = ""; refreshPreview(usingCandidate:true); updateChangedLabelsCount()
        } catch { labelError = error.localizedDescription }
    }
    func receive(_ snapshot: CatalogueSnapshot, session: LabelSession, icons: [UUID:NSImage] = [:]) {
        // Compare with the previous session: preferences may already contain an external
        // edit or Undo when its updated runtime session arrives here.
        let hadDraft = draft != liveSession.selection || resetAssignments || hasPinDraft
        liveSession = session
        if !snapshot.windows.isEmpty || !snapshot.tabs.isEmpty || !snapshot.apps.isEmpty { raw = snapshot.resolvingTabOwners(); sourceIsSample = false }
        else if !sourceIsSample { raw = snapshot.resolvingTabOwners() }
        self.icons = sourceIsSample ? Self.sampleIcons() : icons
        if hadDraft {
            // Keep edits and pins, but validate them against windows that opened or
            // closed while the user was editing. The preview must follow that source.
            stage()
        } else {
            draft = preferences.document.selection; labelError = ""; refreshPreview(); updateChangedLabelsCount()
        }
    }
    func refreshPreview(usingCandidate: Bool = false) {
        if !dirty && !usingCandidate { candidate = liveSession }
        var session = usingCandidate || dirty ? candidate : liveSession
        let source = ApplicationShortcuts.includingClosedApps(sourceIsSample ? Self.samples() : raw,preferences:session.selection.appShortcuts).resolvingTabOwners()
        var newIcons = icons
        newIcons.merge(ApplicationShortcuts.icons(session.selection.appShortcuts.assignments,source:source)) { _,new in new }
        var mapped = session.map(source)
        let doc = preferences.document
        mapped = doc.exclusions.applying(to: mapped)
        mapped.windows = mapped.windows.filter { (doc.includeMinimized || !$0.minimized) && (doc.includeHidden || !$0.hidden) }
        mapped.apps = mapped.apps.filter { doc.includeHidden || !$0.hidden || session.selection.appShortcuts.assignment(for:$0) != nil }
        mapped.tabs = mapped.tabs.filter { doc.browsers.enabled && !$0.excluded }
        if sourceIsSample {
            mapped.tabs = mapped.tabs.filter { tab in
                guard let browser = BrowserID.allCases.first(where:{$0.title == tab.app}),doc.browsers.includes(browser) else { return false }
                return doc.browsers.range == .all || browser == .arc
            }
        }
        var newPreviewState = previewState
        newPreviewState.cancel()
        newPreviewState.configure(mode:doc.mode); newPreviewState.configure(ordering:doc.traversalOrder); newPreviewState.update(mapped); newPreviewState.open()
        let newMessage = sourceIsSample ? String(localized:"Sample windows, tabs and apps") : String(localized:"Your current windows, tabs and apps")
        // Compute all three outputs above before touching any @Published storage, then
        // assign consecutively (and skip icons entirely when unchanged) so this reruns
        // as few SwiftUI update passes as possible instead of one per field.
        if !iconsEqual(icons,newIcons) { icons = newIcons }
        previewState = newPreviewState
        previewMessage = newMessage
    }
    func previewKey(_ key: SelectionKey) {
        let effect = previewState.handle(key)
        if case .selected(let id) = effect {
            let title = previewState.targets.first { $0.id == id }?.title ?? String(localized:"target")
            previewMessage = String(localized:"Preview selected “\(title)”"); previewState.open()
        } else if effect == .cancelled { previewState.open() }
    }
    func previewChoose(_ id: TargetID) {
        _ = previewState.select(id); previewMessage = String(localized:"Preview selection accepted"); previewState.open()
    }
    func restoreDefaults() {
        if preferences.commit(SettingsDocument(),message:String(localized:"Defaults restored. OS permissions are unchanged."),forceCheckpoint:true) {
            let session = LabelSession(); onApply?(session); liveSession = session; discard()
        }
    }
    func refreshLogin() {
        let state = loginService.status()
        loginEnabled = state == .enabled || state == .requiresApproval
        loginStatus = switch state { case .enabled: String(localized:"Registered and enabled"); case .requiresApproval: String(localized:"Approval required in Login Items"); case .notRegistered: String(localized:"Not registered"); case .notFound: String(localized:"macOS cannot find this app’s login registration. Turn on Launch at login to retry."); @unknown default: String(localized:"Status unavailable") }
    }
    func login(_ enabled: Bool) {
        guard !preferences.readOnly else { return }
        loginError = ""
        defer { refreshLogin() }
        do {
            // Always apply an explicit request, even when the saved preference
            // already matches it (Login Items may have changed outside Tabnax).
            try loginService.setEnabled(enabled)
            var document = preferences.document; document.launchAtLogin = enabled
            if !preferences.commit(document) { loginError = preferences.message }
        } catch {
            loginError = error.localizedDescription; preferences.report(loginError)
        }
    }
    func recordShortcut(_ target: RecordingTarget = .main) {
        if recordingTarget == target { stopRecorder(); return }
        stopRecorder(); recordingTarget = target
        let session = UUID(); recordingSession = session
        recording = true; onRecordingChange?(true)
        preferences.report(String(localized:"Press a shortcut with Control, Option or Command. Escape cancels. Shift alone requires a function key."))
        recorder = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            MainActor.assumeIsolated { [weak self] () -> EventRoute in
                guard let self else { return EventRoute(event:event) }
                if event.isARepeat { return EventRoute(event:nil) }
                acceptRecordedShortcut(Shortcut(keyCode:event.keyCode,modifiers:CGEventFlags(rawValue:UInt64(event.modifierFlags.rawValue)).intersection(Shortcut.relevant)),session:session)
                return EventRoute(event:nil)
            }.event
        }
    }
    func acceptRecordedShortcut(_ shortcut: Shortcut, session: UUID) {
        // A queued event from a cancelled or previous recording cannot overwrite
        // a later selection, including the direct Command–Tab option.
        guard recording, recordingSession == session else { return }
        if shortcut.keyCode == 53 { stopRecorder(); preferences.report(String(localized:"Shortcut recording cancelled.")); return }
        var d = preferences.document
        var activation = recordingTarget == .search ? d.searchActivation.shortcut : d.activation
        activation.keyCode = shortcut.keyCode; activation.modifiers = shortcut.modifiers.rawValue
        if recordingTarget == .search { d.searchActivation.shortcut = activation } else { d.activation = activation }
        if preferences.commit(d,message:String(localized:"Shortcut saved: \(shortcutTitle(activation))")) { refreshPreview(); stopRecorder() }
    }
    func stopRecorder() {
        // A no-op guard matters here: callers like windowDidResignKey fire on every
        // key-focus change, including the switcher panel taking key focus while
        // Settings is the main window, and must not cancel an unrelated active session.
        guard recording else { return }
        if let recorder { NSEvent.removeMonitor(recorder) }; recorder = nil; recordingSession = nil; recordingTarget = nil; recording = false; onRecordingChange?(false)
    }
    func openAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    static func sampleIcons() -> [UUID:NSImage] {
        let sample = samples()
        let bundles = ["Xcode":"com.apple.dt.Xcode","Safari":"com.apple.Safari","Finder":"com.apple.finder","Notes":"com.apple.Notes","Arc":"company.thebrowser.Browser","Zen":"app.zen-browser.zen"]
        var icons: [UUID:NSImage] = [:]
        for t in sample.apps + sample.tabs { if let bundle = bundles[t.app],let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) { icons[t.id.process] = IconCache.icon(forFile:url.path) } }
        return icons
    }
    static func samples() -> CatalogueSnapshot {
        let names = ["Xcode","Safari","Finder","Notes"]
        let processes = (1...4).map { UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",$0))! }
        let bundles = ["com.apple.dt.Xcode","com.apple.Safari","com.apple.finder","com.apple.Notes"]
        let apps = names.enumerated().map { i,name in Target(id:TargetID(process:processes[i]),app:name,title:name,bundleID:bundles[i]) }
        let titles = ["Tabnax · Settings","Tabnax · Keyboard guide","Assets","Ideas & notes","Review changes","Tabnax · Layout preview","Exports","Weekend walks","InputRouter.swift","Release checklist"]
        let windows = titles.enumerated().map { i,title in Target(id:TargetID(process:processes[i%4],window:UUID(uuidString:String(format:"10000000-0000-0000-0000-%012d",i+1))!),app:names[i%4],title:title,minimized:i==7,hidden:i==8) }
        let tabProcesses = (1...2).map { UUID(uuidString:String(format:"30000000-0000-0000-0000-%012d",$0))! }
        let browserApps = [BrowserID.arc, .zen].enumerated().map { i, browser in
            Target(id:TargetID(process:tabProcesses[i]),app:browser.title,title:browser.title,bundleID:browser.bundleID)
        }
        let tabs: [Target] = (0..<14).map { i in
            let token = UUID(uuidString:String(format:"20000000-0000-0000-0000-%012d",i+1))!
            let id = TargetID(process:tabProcesses[i%2],window:token)
            let browser = i%2 == 0 ? "Arc" : "Zen"
            let group = i%2 == 0 ? "Arc · Work" : "Zen · Personal"
            return Target(id:id,app:browser,title:titles[i%titles.count],group:group,bundleID:browserApps[i%2].bundleID,owner:tabProcesses[i%2])
        }
        var history = FocusHistory(); history.observe(windows[1].id); history.observe(windows[0].id)
        return .init(windows:windows,apps:apps + browserApps,tabs:tabs,history:history)
    }
}

@MainActor final class SettingsController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    private var appearanceSubscription: AnyCancellable?
    var onRetry: (() -> Void)? { get { model.onRetry } set { model.onRetry = newValue } }
    var onRestart: (() -> Void)? { get { model.onRestart } set { model.onRestart = newValue } }
    /// Called once the window is actually off screen, so the catalogue can stop listing it.
    var onClose: (() -> Void)?
    var onApply: ((LabelSession) -> Void)? { get { model.onApply } set { model.onApply = newValue } }
    var onConnect: ((BrowserID) -> Void)? { get { model.onConnect } set { model.onConnect = newValue } }
    init(preferences: Preferences) {
        model = SettingsModel(preferences:preferences)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = String(localized:"Tabnax Settings"); window.identifier = .init("settings"); window.isReleasedWhenClosed = false
        window.minSize = NSSize(width:820,height:650)
        super.init(window:window)
        window.contentView = NSHostingView(rootView:SettingsView(model:model,preferences:preferences))
        appearanceSubscription = preferences.$document.map(\.appearance.source).removeDuplicates().sink { [weak window] source in
            window?.appearance = source == .system ? nil : NSAppearance(named:source == .dark ? .darkAqua : .aqua)
        }
        window.delegate = self; window.center()
        if !CommandLine.arguments.contains("--test-domain") && !CommandLine.arguments.contains("--render-settings") { window.setFrameAutosaveName("TabnaxSettingsWindow") }
    }
    required init?(coder:NSCoder) { fatalError("Programmatic settings") }
    func update(status:String) { model.status = status; model.refreshLogin() }
    func show() { model.refreshLogin(); showWindow(nil); NSApp.activate(); window?.makeKeyAndOrderFront(nil); window?.orderFrontRegardless() }
    func windowWillClose(_ notification:Notification) { model.stopRecorder(); DispatchQueue.main.async { [weak self] in self?.onClose?() } }
    func windowDidResignKey(_ notification:Notification) { model.stopRecorder() }
    func savePreview(to path:String) throws {
        guard let view = window?.contentView else { return }; view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { return }
        withThemeSnapshotFallback(in:view) { view.cacheDisplay(in:view.bounds,to:bitmap) }
        if let png = bitmap.representation(using:.png,properties:[:]) { try png.write(to:URL(fileURLWithPath:path)) }
    }
}

/// Per-bundle-ID cache for the two lookups `appAssignmentRow` otherwise repeats on every
/// SwiftUI render (once per assigned app). Both lookups expire so installing, moving or
/// removing an app while Settings is open does not leave its availability stuck.
@MainActor private enum AppAssignmentCache {
    private static var resolved: [String: (path: String, value: URL?, stamp: TimeInterval)] = [:]
    private static var running: [String: (value: Bool, stamp: TimeInterval)] = [:]
    private static let lifetime: TimeInterval = 1
    static func invalidate(_ bundleID: String) { resolved[bundleID] = nil; running[bundleID] = nil }
    static func url(for app: AppAssignment) -> URL? {
        let now = Date().timeIntervalSinceReferenceDate
        if let cached = resolved[app.bundleID], cached.path == app.path, now - cached.stamp < lifetime { return cached.value }
        let value = ApplicationShortcuts.resolve(app)
        resolved[app.bundleID] = (app.path,value,now)
        return value
    }
    static func isRunning(_ bundleID: String) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        if let cached = running[bundleID], now - cached.stamp < lifetime { return cached.value }
        let value = !NSRunningApplication.runningApplications(withBundleIdentifier:bundleID).isEmpty
        running[bundleID] = (value,now)
        return value
    }
}
private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var preferences: Preferences
    @State private var confirmRestore = false
    @State private var confirmLabels = false
    @State private var letterIndex = 0
    @State private var spotlightReplay = 0
    @Environment(\.colorScheme) private var scheme
    private var doc: SettingsDocument { preferences.document }
    private func binding<T>(_ key: WritableKeyPath<SettingsDocument,T>) -> Binding<T> {
        let preview = SettingsModel.previewRelevantKeyPaths.contains(key as AnyKeyPath)
        return Binding(get:{ preferences.document[keyPath:key] },set:{ value in model.change(preview:preview) { $0[keyPath:key] = value } })
    }
    private func selection<T>(_ key: WritableKeyPath<SelectionPreferences,T>) -> Binding<T> {
        Binding(get:{ model.draft[keyPath:key] },set:{ value in model.draft[keyPath:key] = value; model.stage() })
    }
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                ForEach(SettingsPane.allCases) { pane in
                    Button { model.selectPane(pane) } label: {
                        VStack(spacing:5) { Image(systemName:pane.symbol).font(.system(size:24)); Text(pane.title).font(.system(size:11,weight:.medium)) }
                            .frame(width:88,height:58).background(model.pane == pane ? Color.primary.opacity(0.055) : .clear,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(model.pane == pane ? Color.accentColor : .secondary)
                        .accessibilityValue(model.pane == pane ? String(localized:"Selected") : "").accessibilityAddTraits(model.pane == pane ? .isSelected : [])
                        .accessibilityIdentifier("settings-pane-\(pane.rawValue)")
                }
            }.frame(maxWidth:.infinity).padding(.top,4).padding(.bottom,12).background(.bar)
            Divider()
            if preferences.readOnly {
                HStack(alignment:.top,spacing:10) {
                    Image(systemName:"lock.fill").foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:4) {
                        Text("Settings are read-only").font(.system(size:12,weight:.semibold))
                        Text(preferences.message).font(.system(size:11)).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:0)
                }.padding(14).background(Color.orange.opacity(0.08)).accessibilityIdentifier("settings-read-only")
                Divider()
            }
            GeometryReader { geometry in
            let previewWidth: CGFloat = geometry.size.width < 900 ? 306 : 330
            HStack(alignment:.top,spacing:0) {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        VStack(alignment:.leading,spacing:6) {
                            Text(model.pane.title).font(.system(size:21,weight:.semibold)).tracking(-0.5).accessibilityAddTraits(.isHeader)
                            help(model.pane.detail)
                            Text(preferences.readOnly ? "Saved settings are preserved. Editing is unavailable." : model.pane == .letters || model.pane == .apps ? "Letters and Apps share a draft. Apply letters to save." : "Changes save automatically.")
                                .font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                        }
                        Group { switch model.pane { case .general: general; case .letters: selectionPane; case .apps: appsPane; case .exclusions: exclusionsPane; case .position: position; case .appearance: appearance; case .browsers: browsers } }
                    }.padding(.horizontal,24).padding(.vertical,24).frame(maxWidth:.infinity,alignment:.leading)
                }.id(model.pane).frame(minWidth:380,maxWidth:.infinity)
                Divider()
                ScrollView { preview(width:previewWidth,height:max(260,min(420,geometry.size.height-250))) }.frame(width:previewWidth).padding(20).background(Color(nsColor:.controlBackgroundColor).opacity(0.35))
            }
            }
            if model.dirty || !model.labelError.isEmpty {
                Divider()
                HStack(spacing:10) {
                    VStack(alignment:.leading,spacing:3) {
                        Text(model.labelError.isEmpty ? (model.dirty ? String(localized:"Previewing your new letters") : String(localized:"Your letters are up to date")) : model.labelError)
                            .font(.system(size:12,weight:.medium)).foregroundStyle(model.labelError.isEmpty ? Color.primary : .red)
                            .accessibilityIdentifier("selection-error")
                        if model.dirty && model.labelError.isEmpty {
                            Text(model.changedLabels == 0 ? String(localized:"Displayed letters stay the same. Your other letter settings will be saved.") : model.changedLabels == 1 ? String(localized:"1 target has new letters in this layout.") : String(localized:"\(model.changedLabels) targets have new letters in this layout."))
                                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                    Spacer()
                    Button(String(localized:"Discard")) { model.discard() }.disabled(!model.dirty && model.labelError.isEmpty)
                    Button(String(localized:"Apply letters")) { model.apply() }.buttonStyle(.borderedProminent)
                        .disabled(!model.dirty || !model.labelError.isEmpty || preferences.readOnly).accessibilityIdentifier("apply-labels")
                }.padding(.horizontal,24).padding(.vertical,12).background(.bar)
            }
            Divider()
            HStack {
                Button(String(localized:"Restore defaults…")) { confirmRestore = true }.disabled(preferences.readOnly)
                Text(preferences.message).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth:.infinity,alignment:.trailing).accessibilityIdentifier("settings-status")
                Button(String(localized:"Undo")) { preferences.undo(); model.discard() }.disabled(!preferences.canUndo || model.dirty).keyboardShortcut("z",modifiers:.command)
                    .help(model.dirty ? "Apply or discard your letter draft before undoing saved changes." : "Undo the last saved settings change.")
            }.padding(14).background(.bar)
        }
        .background(scheme == .dark ? Color(red:0.153,green:0.161,blue:0.176) : Color(red:0.965,green:0.961,blue:0.957))
        .onChange(of:model.draft.alphabet) { _,value in letterIndex = min(letterIndex,max(0,value.count-1)) }
        .onChange(of:preferences.document.launchAtLogin) { _,_ in model.refreshLogin() }
        .alert(String(localized:"Restore Tabnax defaults?"),isPresented:$confirmRestore) {
            Button(String(localized:"Restore defaults"),role:.destructive) { model.restoreDefaults() }; Button(String(localized:"Cancel"),role:.cancel) {}
        } message: { Text("Resets all preferences, fixed app letters, custom colors, positions and session letters. Any unapplied letter draft is discarded. Launch at login is turned off; Accessibility and browser permissions are preserved. Undo is available for saved settings. To reset only automatic letters, use Reset letter assignments in Letters.") }
        .alert(String(localized:"Reset \(model.labelSetTitle) assignments?"),isPresented:$confirmLabels) {
            Button(String(localized:"Preview reset")) { model.resetLabels() }; Button(String(localized:"Cancel"),role:.cancel) {}
        } message: { Text("Reassigns automatic letters and clears session pins for \(model.labelSetTitle). Fixed app letters are preserved. Review the preview, then Apply letters. Other letter sets stay unchanged.") }
    }
    private func help(_ text:String) -> some View { Text(text).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
    private func group<Content:View>(_ title:String,@ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.system(size:12,weight:.semibold)).accessibilityAddTraits(.isHeader)
            content()
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
            .background(Color(nsColor:.controlBackgroundColor).opacity(0.55),in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(Color.primary.opacity(0.09),lineWidth:0.5))
    }
    private var exclusionsPane: some View { ExclusionsSettingsView(model: model, preferences: preferences) }
    private var general: some View {
        let trusted = AXIsProcessTrusted()
        return VStack(alignment:.leading,spacing:16) {
            if model.isFirstRun {
                VStack(alignment:.leading,spacing:8) {
                    Label("Welcome to Tabnax",systemImage:"hand.wave").font(.system(size:13,weight:.semibold))
                    Text("Switch windows, apps and browser tabs by typing their displayed letters. Start with the shortcut below.")
                        .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Button("Got it") { model.isFirstRun = false }.buttonStyle(.bordered)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Color.accentColor.opacity(0.09),in:RoundedRectangle(cornerRadius:8))
                    .accessibilityIdentifier("welcome-banner")
            }
            if !trusted {
                HStack(spacing:10) {
                    Label("Allow Accessibility to use the shortcut",systemImage:"exclamationmark.circle")
                        .font(.system(size:12,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                    Button("Allow access…") { model.openAccessibility() }
                        .accessibilityIdentifier("accessibility-setup")
                }.padding(12).background(Color.orange.opacity(0.09),in:RoundedRectangle(cornerRadius:8))
            }
            group(String(localized:"Open switcher")) {
                HStack(spacing:12) {
                    Text(shortcutTitle(doc.activation)).font(.system(.body,design:.monospaced))
                        .padding(.horizontal,12).padding(.vertical,8)
                        .background(Color.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:6))
                        .accessibilityIdentifier("activation-shortcut")
                    Spacer(minLength:0)
                    Button(model.recordingTarget == .main ? String(localized:"Cancel recording") : String(localized:"Record shortcut…")) { model.recordShortcut() }
                        .accessibilityIdentifier("record-shortcut")
                }
                if model.recordingTarget == .main {
                    Label("Press a key with a modifier. Escape cancels.",systemImage:"record.circle")
                        .font(.system(size:12,weight:.medium)).foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("shortcut-recording-hint")
                }
                HStack {
                    Button("Use ⌘ Tab") { model.stopRecorder(); model.change(preview:false) { $0.activation.useCommandTab() } }.disabled(doc.activation.isCommandTab)
                    Button("Use suggested shortcut") { model.stopRecorder(); model.change(preview:false) { $0.activation.restoreChord() } }.disabled(doc.activation.keyCode == 49 && doc.activation.modifiers == ActivationPreferences().modifiers)
                }
                if doc.activation.isCommandTab { help(String(localized:"Command–Tab replaces the macOS app switcher while Tabnax has keyboard access. It may be unavailable during Secure Input, such as in a password field.")) }
                Picker("Behavior",selection:binding(\.activation.behavior)) { Text("Press to open").tag(ActivationBehavior.latch); Text("Hold to show").tag(ActivationBehavior.hold) }.accessibilityIdentifier("activation-behavior")
                help(doc.activation.behavior == .hold ? String(localized:"Keep the shortcut’s modifier keys down. Use Tab or arrows to highlight an item, then release to switch.") : String(localized:"Press once, release the shortcut, then type a displayed letter. Escape goes back or closes."))
                DisclosureGroup("Keyboard details") {
                    VStack(alignment:.leading,spacing:8) {
                        help(doc.activation.behavior == .hold ? String(localized:"A quick press and release returns to the previous window, when one is available. You can release the shortcut’s main key while keeping its modifiers down. Typing after cycling cancels selection on release.") : String(localized:"Tab and the arrow keys move the highlight. Cycling while the opening modifiers are still held selects on release, unless you type afterward. Pressing the shortcut again after releasing closes the switcher, except Command–Tab, which keeps cycling."))
                        help(String(localized:"Type a complete letter address to switch immediately. Enter selects the highlight; in Relay’s main view, Enter returns to the previous window. Press / to search. Escape goes back; clicking outside closes the switcher."))
                    }.padding(.top,4)
                }.font(.system(size:12))
                if doc.activation.behavior == .hold {
                    Toggle("Swap instantly on tap",isOn:Binding(get:{doc.activation.quietReturnEnabled},set:{value in model.change(preview:false) { $0.activation.quietReturn = value }})).accessibilityIdentifier("activation-quiet-return")
                    help(String(localized:"Return to the previous window without showing the switcher. To show it and choose another item, keep the modifiers down and press the shortcut’s main key again, Tab or an arrow key."))
                }
                Picker("Modifier side",selection:binding(\.activation.side)) { Text("Either side").tag(ModifierSide.either); Text("Left only").tag(ModifierSide.left); Text("Right only").tag(ModifierSide.right) }.accessibilityIdentifier("activation-side")
                if doc.activation.side != .either {
                    help(String(localized:"Every modifier in the shortcut must use this side. Side-specific shortcuts may be unavailable during Secure Input. Choose Either side if your keyboard cannot distinguish left and right modifiers."))
                }
            }.disabled(preferences.readOnly)
            group(String(localized:"Open in search")) {
                Toggle("Enable search shortcut", isOn: Binding(get: { doc.searchActivation.enabled }, set: { value in
                    model.stopRecorder(); model.change(preview:false) { $0.searchActivation.enabled = value }
                })).accessibilityIdentifier("search-shortcut-enabled")
                HStack {
                    Text(shortcutTitle(doc.searchActivation.shortcut)).font(.system(.body,design:.monospaced))
                        .accessibilityIdentifier("search-activation-shortcut")
                    Spacer()
                    Button(model.recordingTarget == .search ? "Cancel recording" : "Record search shortcut…") { model.recordShortcut(.search) }
                        .accessibilityIdentifier("record-search-shortcut")
                }
                if model.recordingTarget == .search {
                    Text("Press a shortcut with Control, Option or Command. Escape cancels.")
                        .accessibilityIdentifier("search-shortcut-recording-hint")
                }
                Button("Reset search shortcut") { model.stopRecorder(); model.change(preview:false) { $0.searchActivation.shortcut = SearchActivationPreferences.suggestedShortcut } }
                    .accessibilityIdentifier("reset-search-shortcut")
                Picker("Search modifier side", selection: binding(\.searchActivation.shortcut.side)) {
                    Text("Either side").tag(ModifierSide.either); Text("Left only").tag(ModifierSide.left); Text("Right only").tag(ModifierSide.right)
                }.accessibilityIdentifier("search-activation-side")
                help(String(localized:"Off by default. Opens ready for typing and stays open when modifiers are released, even with Hold to show or Swap instantly on tap. Repeating keeps your query and selection; from an open switcher it enters search. Enter selects; Escape exits search, then closes. Reset changes only this chord; Restore defaults turns it off."))
                help(String(localized:"Both shortcuts respect foreground exceptions. Command–Tab and side-specific chords require the event tap and may be unavailable during Secure Input. Shift-only printable chords are rejected because they intercept typing."))
            }.disabled(preferences.readOnly)
            group(String(localized:"Mouse & trackpad")) {
                Picker("Mouse control",selection:binding(\.mouse)) { Text("Off").tag(MouseControl.off); Text("Click to select").tag(MouseControl.click); Text("Click + wheel selection").tag(MouseControl.clickAndWheel) }.accessibilityIdentifier("mouse-control")
                help(doc.mouse == .off ? String(localized:"Clicks on switcher items and scrolling are ignored. Keyboard, search editing and accessibility actions remain available.") : doc.mouse == .click ? String(localized:"Click an item to switch. Scroll normally through long lists.") : String(localized:"Scroll over the switcher to move the highlight. Click or press Enter to select; in Relay’s main view, Enter returns to the previous window. Scrolling and hovering never select an item."))
                Toggle("Move cursor to selected window",isOn:binding(\.moveCursorToSelectedWindow)).accessibilityIdentifier("move-cursor-to-selected-window")
                help(String(localized:"Place the cursor at the center of the window after switching to it. Applies to window selections, including keyboard shortcuts."))
            }.disabled(preferences.readOnly)
            group(String(localized:"Search")) {
                help(String(localized:"Match app names, titles and context with words, initials or letters in order. Stronger matches appear first."))
                Toggle("Remember search choices", isOn: binding(\.rememberSearchChoices)).accessibilityIdentifier("remember-search-choices")
                help(String(localized:"Off by default. When enabled, saves up to 128 choices on this Mac to improve ranking. Saves salted fingerprints instead of readable queries or titles. Turning this off deletes the saved choices."))
                Button("Clear remembered choices") { preferences.clearSearchChoices() }
                    .accessibilityIdentifier("clear-search-choices")
                    .disabled(!doc.rememberSearchChoices)
            }.disabled(preferences.readOnly)
            group(String(localized:"Windows")) {
                Picker("Traversal order", selection: binding(\.traversalOrder)) {
                    ForEach(TraversalOrder.allCases, id: \.self) { order in Text(order.title).tag(order) }
                }.accessibilityIdentifier("traversal-order")
                help(doc.traversalOrder.explanation)
                help(String(localized:"Order is fixed while the switcher is open. App groups stay together; their first ordered child sets the group position. Direct letters stay unchanged. Stronger search matches still come first."))
                Toggle("Show window actions menu",isOn:binding(\.windowActionsEnabled)).accessibilityIdentifier("window-actions-enabled")
                help(String(localized:"Use the ellipsis button or Command–Period for window actions and their shortcuts: Command-W to close, Command-M to minimize, Command-R to restore, Command-H to hide or unhide, Control-Command-Z to zoom and Control-Command-F for full screen. Actions keep the switcher open after modifier release; close dismisses it. App and browser-tab rows only offer applicable actions. Command-Q and Option restore remain available when this setting is off."))
                Toggle("Include minimized windows",isOn:binding(\.includeMinimized))
                Toggle("Include windows of hidden apps",isOn:binding(\.includeHidden))
                help(String(localized:"Selecting a minimized window restores it. Selecting a window of a hidden app reveals the app."))
            }.disabled(preferences.readOnly)
            group(String(localized:"Startup")) {
                Toggle("Launch at login",isOn:Binding(get:{model.loginEnabled},set:{model.login($0)})).disabled(preferences.readOnly).accessibilityIdentifier("launch-at-login")
                help(model.loginStatus)
                if !model.loginError.isEmpty { Text(model.loginError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    Button("Refresh status") { model.refreshLogin() }
                }
            }
            group(String(localized:"Accessibility")) {
                Label(trusted ? "Accessibility allowed" : "Accessibility required",systemImage:trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size:12,weight:.medium)).foregroundStyle(trusted ? Color.green : Color.orange)
                    .accessibilityIdentifier("accessibility-status")
                if !trusted {
                    help(String(localized:"In System Settings → Privacy & Security → Accessibility, enable this copy of Tabnax, then choose Retry. This allows window discovery, switching and keyboard shortcuts."))
                    HStack { Button("Open System Settings") { model.openAccessibility() }; Button("Retry") { model.onRetry?() } }
                } else if !model.status.isEmpty && model.status != "Ready" { help(model.status) }
                DisclosureGroup("Troubleshooting") {
                    VStack(alignment:.leading,spacing:8) {
                        Button("Restart Tabnax") { model.onRestart?() }.accessibilityIdentifier("restart-tabnax")
                        Button("Open System Settings") { model.openAccessibility() }
                        Button("Retry") { model.onRetry?() }
                        help(String(localized:"If access stops working after an update, remove and re-add Tabnax in Accessibility, then restart it. Browser permissions are managed separately in Browser tabs."))
                    }.padding(.top,4)
                }.font(.system(size:12))
            }
        }
    }
    private var selectionPane: some View {
        VStack(alignment:.leading,spacing:16) {
            group(String(localized:"Letter order")) {
                Picker("Keyboard preset",selection:Binding(get:{model.draft.hand},set:{model.draft.choose($0); model.stage()})) { Text("Right hand").tag(HandPreset.right); Text("Left hand").tag(HandPreset.left); Text("Both hands").tag(HandPreset.both); Text("All letters").tag(HandPreset.all); Text("Custom order").tag(HandPreset.custom) }.accessibilityIdentifier("selection-hand")
                help(String(localized:"Start with the keys you find easiest to reach. Earlier letters are used first when a name-based letter is unavailable."))
                HStack(alignment:.firstTextBaseline) { Text("Letters, in preferred order").font(.system(size:12,weight:.medium)); Spacer(); Text("\(model.draft.alphabet.count) / 26").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).accessibilityLabel("\(model.draft.alphabet.count) letters entered") }
                TextField("Enter 6–26 letters",text:Binding(get:{model.draft.alphabet.uppercased()},set:{model.draft.alphabet = SelectionPreferences.normalize($0); model.draft.hand = .custom; model.stage()})).font(.system(size:16,weight:.medium,design:.monospaced)).tracking(1).textFieldStyle(.roundedBorder).accessibilityLabel("Letters in preferred order").accessibilityIdentifier("selection-alphabet")
                LazyVGrid(columns:[GridItem(.adaptive(minimum:28,maximum:34),spacing:4)],alignment:.leading,spacing:4) {
                    ForEach(Array(model.draft.alphabet.enumerated()),id:\.offset) { index,letter in
                        let reservedBy = model.draft.appShortcuts.enabled ? model.draft.appShortcuts.assignments.first(where:{$0.letter == String(letter)}) : nil
                        Button { letterIndex = index } label: {
                            ZStack(alignment:.topTrailing) {
                                Text(String(letter).uppercased()).font(.system(size:12,weight:.medium,design:.monospaced)).frame(maxWidth:.infinity,minHeight:29)
                                    .foregroundStyle(reservedBy != nil ? .secondary : .primary)
                                    .background(Color(nsColor:.controlBackgroundColor).opacity(reservedBy != nil ? 0.5 : 1),in:RoundedRectangle(cornerRadius:4))
                                    .overlay(RoundedRectangle(cornerRadius:4).stroke(letterIndex == index ? Color.accentColor : Color.primary.opacity(0.18),lineWidth:letterIndex == index ? 1.5 : 0.5))
                                if reservedBy != nil { Image(systemName:"lock.fill").font(.system(size:7)).foregroundStyle(.secondary).padding(3) }
                            }
                        }.buttonStyle(.plain)
                            .accessibilityLabel(reservedBy.map { "\(String(letter).uppercased()), position \(index+1), reserved for \($0.name)'s app letter" } ?? "\(String(letter).uppercased()), position \(index+1)")
                            .accessibilityValue(letterIndex == index ? "Selected" : "")
                            .accessibilityAddTraits(letterIndex == index ? .isSelected : [])
                            .help(reservedBy.map { String(localized:"\($0.name) uses this app letter. You can still move it in the order; change its assignment in Apps.") } ?? String(localized:"Select this letter, then use the arrows below to move it."))
                    }
                }
                if model.draft.appShortcuts.enabled && model.draft.appShortcuts.assignments.contains(where:{ model.draft.alphabet.contains($0.letter) }) {
                    Label("Marked letters belong to apps. Change those assignments in Apps.",systemImage:"lock.fill").font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                help(String(localized:"Use 6–26 different letters A–Z. Select a letter to move it with the arrows."))
                HStack { Text(Array(model.draft.alphabet).indices.contains(letterIndex) ? String(localized:"\(String(Array(model.draft.alphabet)[letterIndex]).uppercased()) selected") : String(localized:"Choose a letter")).font(.system(size:11)).foregroundStyle(.secondary); Spacer()
                    Button { moveLetter(-1) } label:{ Image(systemName:"arrow.left") }.accessibilityLabel("Move selected letter earlier").help("Move selected letter earlier").disabled(letterIndex <= 0 || !Array(model.draft.alphabet).indices.contains(letterIndex))
                    Button { moveLetter(1) } label:{ Image(systemName:"arrow.right") }.accessibilityLabel("Move selected letter later").help("Move selected letter later").disabled(letterIndex >= model.draft.alphabet.count-1)
                }
                HStack {
                    Button("Restore preset order") { model.draft.restoreOrder(); model.stage() }.disabled(model.draft.alphabet == model.draft.baseHand.alphabet && model.draft.hand == model.draft.baseHand).accessibilityIdentifier("selection-restore-order")
                    Spacer()
                    Button("Remove I and O") { model.draft.alphabet.removeAll { "io".contains($0) }; model.draft.hand = .custom; model.stage() }
                        .disabled(!model.draft.alphabet.contains(where:{ "io".contains($0) }) || Set(model.draft.alphabet.filter { !"io".contains($0) }).count < 6)
                        .help("Remove letters that resemble 1 and 0. At least six letters must remain.")
                }
            }
            group(String(localized:"Automatic assignments")) {
                Picker("Policy",selection:Binding(get:{model.draft.policy == .pairs ? AssignmentPolicy.pairs : .stable},set:{model.draft.policy = $0; model.stage()})) { Text("Name initials first (stable)").tag(AssignmentPolicy.stable); Text("Always two letters").tag(AssignmentPolicy.pairs) }
                help(model.draft.policy == .pairs ? String(localized:"Uses two-letter combinations for automatic window and tab labels. Fixed app letters must be outside this alphabet.") : String(localized:"Prefers the app’s first letter, then other initials and letters from the app or window name, then your preferred order. Existing assignments stay stable."))
                if [.fold,.canopy].contains(doc.mode) { help(String(localized:"Fold and Canopy use name-based app and window letters. This policy applies to the other layouts.")) }
            }
            group(String(localized:"Keyboard interpretation")) {
                Picker("Interpret keys",selection:selection(\.interpretation)) { Text("Physical positions (US base)").tag(KeyInterpretation.physical); Text("Typed characters").tag(KeyInterpretation.characters) }
                help(model.draft.interpretation == .physical ? String(localized:"Uses the key positions of a US keyboard, even if your keyboard language changes. A printed key may differ from its Tabnax letter.") : String(localized:"Matches the characters produced by your current keyboard language. Your layout must be able to type the A–Z letters you selected."))
            }
            VStack(alignment:.leading,spacing:8) {
                Button("Reset letter assignments…") { confirmLabels = true }
                help(String(localized:"Resets held letters and pins for \(model.labelSetTitle). Your letter order and fixed app letters stay saved."))
            }
        }.disabled(preferences.readOnly)
    }
    private var appsPane: some View {
        VStack(alignment:.leading,spacing:16) {
            appShortcuts
            group(String(localized:"Launching")) {
                Toggle("Launch assigned apps when they aren’t running",isOn:Binding(get:{model.draft.appShortcuts.launchClosedApps},set:{model.draft.appShortcuts.launchClosedApps = $0; model.stageApps()}))
                    .disabled(!model.draft.appShortcuts.enabled).accessibilityIdentifier("launch-closed-apps")
                help(model.draft.appShortcuts.enabled ? String(localized:"Press the app’s letter in the switcher to open it after it quits. Closed apps stay hidden from the window list.") : String(localized:"Turn on fixed app letters above to enable launching. Your previous choice is kept while app letters are off."))
            }
        }.disabled(preferences.readOnly)
    }
    private var appShortcuts: some View {
        group(String(localized:"App letters")) {
            Toggle("Use fixed app letters",isOn:Binding(get:{model.draft.appShortcuts.enabled},set:{model.draft.appShortcuts.enabled = $0; model.stageApps()}))
                .accessibilityIdentifier("app-shortcuts-enabled")
            help(String(localized:"Give each app a familiar letter that stays the same across restarts. In Fold and Canopy, that letter opens the app’s windows and tabs."))
            if !model.draft.appShortcuts.enabled {
                Label(model.draft.appShortcuts.assignments.isEmpty ? "Turn on fixed app letters to add an application." : "App letters are off. Your saved assignments are kept.",systemImage:"info.circle")
                    .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            VStack(spacing:0) {
                if model.draft.appShortcuts.assignments.isEmpty {
                    VStack(spacing:6) {
                        Image(systemName:"app.badge").font(.system(size:23)).foregroundStyle(.secondary)
                        Text("No app letters yet").font(.system(size:12,weight:.medium))
                        Text("Assign one letter to each of your most-used apps.").font(.system(size:11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth:.infinity).padding(18)
                }
                ForEach(model.draft.appShortcuts.assignments) { app in
                    appAssignmentRow(app)
                    Divider()
                }
                HStack {
                    Button { model.chooseApplication() } label:{ Label("Add application…",systemImage:"plus") }
                        .buttonStyle(.plain).foregroundStyle(.tint).accessibilityIdentifier("add-app-assignment")
                        .disabled(model.availableAppLetters.isEmpty)
                    Spacer()
                }.padding(12)
            }.background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).stroke(Color.primary.opacity(0.12),lineWidth:0.5))
                .disabled(!model.draft.appShortcuts.enabled)
            if !model.appError.isEmpty {
                HStack(alignment:.top,spacing:8) {
                    Label(model.appError,systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("app-assignment-error")
                    Spacer(minLength:0)
                    Button { model.appError = "" } label:{ Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss application error")
                }
            }
            if model.draft.policy == .pairs {
                help(model.draft.alphabet.count == 26 ? String(localized:"All 26 letters are used by two-letter labels, so no app letters are available. In Letters, use a smaller alphabet or choose a different assignment policy.") : String(localized:"With “Always two letters,” app letters must be outside the alphabet in Letters. Unavailable choices are marked in each letter menu."))
            } else if let overflow = AddressBook.overflowLetter(alphabet:model.draft.alphabet,policy:model.draft.policy) {
                help(String(localized:"\(overflow.uppercased()) starts longer labels when single letters run out, so it cannot be assigned to an app."))
            }
            if model.draft.appShortcuts.enabled && !model.draft.appShortcuts.assignments.isEmpty && model.availableAppLetters.isEmpty && !(model.draft.policy == .pairs && model.draft.alphabet.count == 26) {
                help(String(localized:"All available app letters are assigned. Remove an assignment to add another app."))
            }
        }
    }
    private func appAssignmentRow(_ app: AppAssignment) -> some View {
        let url = AppAssignmentCache.url(for:app)
        let running = AppAssignmentCache.isRunning(app.bundleID)
        let conflicts = AppShortcutPreferences.reservesPoolAddress(app.letter,alphabet:model.draft.alphabet,policy:model.draft.policy)
        return HStack(spacing:10) {
            Image(nsImage:url.map { IconCache.icon(forFile:$0.path) } ?? NSImage(systemSymbolName:"app",accessibilityDescription:nil)!)
                .resizable().frame(width:32,height:32).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3) {
                Text(app.name).font(.system(size:12,weight:.medium)).lineLimit(1).help(app.name)
                Text(conflicts ? "Letter conflicts with your alphabet · choose another" : url == nil ? "App unavailable · remove and add again" : running ? "Running" : model.draft.appShortcuts.launchClosedApps ? "Launch with \(app.letter.uppercased())" : "Available when running")
                    .font(.system(size:11)).foregroundStyle(conflicts || url == nil ? Color.orange : Color.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:2)
            Menu {
                ForEach(Array("abcdefghijklmnopqrstuvwxyz").map(String.init),id:\.self) { letter in
                    let owner = model.draft.appShortcuts.assignments.first(where:{$0.id != app.id && $0.letter == letter})
                    let reserved = AppShortcutPreferences.reservesPoolAddress(letter,alphabet:model.draft.alphabet,policy:model.draft.policy)
                    Button(owner.map { "\(letter.uppercased()) — \($0.name)" } ?? (reserved ? String(localized:"\(letter.uppercased()) — reserved by Letters") : letter.uppercased())) {
                        if let i = model.draft.appShortcuts.assignments.firstIndex(where:{$0.id == app.id}) {
                            model.draft.appShortcuts.assignments[i].letter = letter; model.stageApps()
                        }
                    }.disabled(reserved || owner != nil)
                }
            } label: {
                Text(app.letter.uppercased()).font(.system(size:15,weight:.semibold,design:.monospaced)).foregroundStyle(conflicts ? Color.orange : Color.primary).frame(width:32,height:30)
                    .background(Color.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:5))
            }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Letter for \(app.name)").accessibilityValue(app.letter.uppercased()).accessibilityIdentifier("app-letter-\(app.bundleID)")
            Button {
                model.draft.appShortcuts.assignments.removeAll { $0.id == app.id }; model.stageApps()
            } label:{ Image(systemName:"minus.circle").foregroundStyle(.secondary) }
                .buttonStyle(.plain).padding(4).help("Remove \(app.name) assignment").accessibilityLabel("Remove \(app.name) assignment").accessibilityIdentifier("remove-app-\(app.bundleID)")
        }.padding(10)
    }
    private func moveLetter(_ delta:Int) {
        var a = Array(model.draft.alphabet); let to = letterIndex+delta
        guard a.indices.contains(letterIndex),a.indices.contains(to) else { return }
        a.swapAt(letterIndex,to); letterIndex = to; model.draft.alphabet = String(a); model.draft.hand = .custom; model.stage()
    }
    private var position: some View {
        let p = doc.placement(for:doc.mode)
        return VStack(alignment:.leading,spacing:18) {
            modePicker
            group(String(localized:"Display")) {
                Picker("Show on",selection:Binding(get:{p.display},set:{v in model.change(preview:false) { $0.display = v }})) { Text("Display with active window").tag(DisplayChoice.focused); Text("Display with pointer").tag(DisplayChoice.pointer); Text("Main display").tag(DisplayChoice.main) }.accessibilityIdentifier("position-display")
                Toggle("Show simultaneously on every display", isOn: binding(\.allDisplays)).accessibilityIdentifier("position-all-displays")
                help(String(localized:"Every copy shares the layout, letters, search and selection. Show on chooses the initial keyboard display; click another copy to move input there. Beacons keeps a full target bank on each display and shows each spatial plaque once. Position and spacing stay shared. Display changes close the session; reopen to use the current screens."))
            }
            group(String(localized:"Position for \(doc.mode.title)")) {
                AnchorPicker(selected:p.anchor) { anchor in model.change(preview:false) { var x = $0.placement(for:$0.mode); x.anchor = anchor; $0.positions[$0.mode.rawValue] = x } }
                Text(p.anchor.title).font(.system(size:12,weight:.semibold)).accessibilityIdentifier("position-anchor-name")
                help(String(localized:"Each layout remembers its own position and edge spacing."))
            }
            group(String(localized:"Space from screen edges")) {
                HStack { Slider(value:Binding(get:{p.inset},set:{v in model.change(preview:false) { var x = $0.placement(for:$0.mode); x.inset = v; $0.positions[$0.mode.rawValue] = x }}),in:12...64,step:4).accessibilityLabel("Space from screen edges").accessibilityValue("\(Int(p.inset)) points").accessibilityIdentifier("position-inset"); Text("\(Int(p.inset)) pt").font(.system(size:12)).monospacedDigit().frame(width:42).accessibilityHidden(true) }
                help(p.anchor == .center ? String(localized:"The switcher stays centered. Spacing only limits its size when the display is small.") : String(localized:"Adds space inside the area available above the Dock and below the menu bar. Centered directions stay centered."))
            }
            if doc.mode == .beacons { help(String(localized:"This positions the window list. Labels beside visible windows stay with those windows.")) }
            Button("Reset \(doc.mode.title) position") {
                model.change(preview:false) {
                    // Older documents keep their display choice in the mode placement.
                    // Reset only the anchor and inset, preserving that display too.
                    if $0.display == nil {
                        var value = Placement.defaults(for:$0.mode); value.display = p.display
                        $0.positions[$0.mode.rawValue] = value
                    } else { $0.positions[$0.mode.rawValue] = nil }
                }
            }.disabled(p.anchor == Placement.defaults(for:doc.mode).anchor && p.inset == Placement.defaults(for:doc.mode).inset)
                .help("Resets this layout’s position and spacing. Your display choice stays the same.")
                .accessibilityIdentifier("position-reset")
        }.disabled(preferences.readOnly)
    }
    private var modePicker: some View {
        group(String(localized:"Switcher layout")) {
            Picker("Layout",selection:binding(\.mode)) { ForEach(DisplayMode.allCases,id:\.self) { Text($0.title).tag($0) } }.disabled(model.dirty || preferences.readOnly).accessibilityIdentifier("display-mode")
            if model.dirty {
                help(String(localized:"Apply or discard your letter and app changes before changing layouts."))
            } else {
                help(doc.mode.explanation)
            }
        }
    }
    private var appearance: some View {
        VStack(alignment:.leading,spacing:16) {
            modePicker
            group(String(localized:"Desktop spotlight")) {
                Toggle("Enable desktop spotlight",isOn:binding(\.appearance.desktopSpotlight.enabled))
                    .accessibilityIdentifier("desktop-spotlight-enabled")
                Picker("Focus",selection:binding(\.appearance.desktopSpotlight.mode)) {
                    Text("Selected window").tag(DesktopSpotlightMode.selectedWindow)
                    Text("Switcher only").tag(DesktopSpotlightMode.switcherOnly)
                }.pickerStyle(.segmented).accessibilityIdentifier("desktop-spotlight-mode")
                    .disabled(!doc.appearance.desktopSpotlight.enabled)
                HStack {
                    Text("Dimming opacity").font(.system(size:12))
                    Slider(value:doc.appearance.desktopSpotlight.mode == .switcherOnly ? binding(\.appearance.desktopSpotlight.switcherDimmingOpacity) : binding(\.appearance.desktopSpotlight.dimmingOpacity),in:0...1,step:0.05)
                        .accessibilityLabel("Desktop dimming opacity")
                        .accessibilityValue("\(Int((doc.appearance.desktopSpotlight.activeOpacity*100).rounded())) percent")
                        .accessibilityIdentifier("desktop-spotlight-opacity")
                    Text("\(Int((doc.appearance.desktopSpotlight.activeOpacity*100).rounded()))%")
                        .monospacedDigit().font(.system(size:12)).frame(width:38,alignment:.trailing)
                        .accessibilityIdentifier("desktop-spotlight-opacity-value")
                }.disabled(!doc.appearance.desktopSpotlight.enabled)
                if doc.appearance.desktopSpotlight.mode == .selectedWindow {
                Toggle("Animate window transitions",isOn:binding(\.appearance.desktopSpotlight.animationEnabled))
                    .accessibilityIdentifier("desktop-spotlight-animation")
                    .disabled(!doc.appearance.desktopSpotlight.enabled)
                HStack {
                    Text("Slow").font(.system(size:12))
                    Slider(value:Binding(get:{ 0.58-doc.appearance.desktopSpotlight.resolvedAnimationDuration },
                                         set:{ binding(\.appearance.desktopSpotlight.animationDuration).wrappedValue = 0.58-$0 }),in:0.08...0.5)
                        .accessibilityLabel("Window transition speed")
                        .accessibilityIdentifier("desktop-spotlight-animation-speed")
                    Text("Fast").font(.system(size:12))
                    Button("Try animation") { spotlightReplay += 1 }
                        .accessibilityIdentifier("desktop-spotlight-animation-replay")
                }.disabled(!doc.appearance.desktopSpotlight.enabled || !doc.appearance.desktopSpotlight.animationEnabled)
                help(String(localized:"Softly reveals each window while keeping the desktop dimmed. Follows Reduce Motion in macOS."))
                }
                DesktopSpotlightPreview(preferences:doc.appearance.desktopSpotlight,accent:NSColor(ThemeTokens.resolve(doc.appearance,dark:model.colorToneDark).selection),replayToken:spotlightReplay)
                    .frame(height:110).clipShape(RoundedRectangle(cornerRadius:8))
                    .accessibilityLabel("Desktop spotlight example")
                    .accessibilityIdentifier("desktop-spotlight-preview")
                if doc.appearance.desktopSpotlight.mode == .switcherOnly {
                    help(String(localized:"Dims the entire desktop so you can focus on the switcher. Windows stay in place while you browse; the chosen window comes forward only when you confirm. This mode remembers its own dimming opacity."))
                } else {
                    help(String(localized:"Brings the highlighted window in front of overlapping windows and dims the surrounding desktop while switching. At 0%, only the outline remains. Minimized, hidden, and off-Space windows are brought forward when you select them."))
                }
            }.disabled(preferences.readOnly)
            group(String(localized:"Appearance")) {
                Picker("Appearance",selection:binding(\.appearance.source)) { Text("System").tag(AppearanceSource.system); Text("Light").tag(AppearanceSource.light); Text("Dark").tag(AppearanceSource.dark) }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("appearance-source")
                help(String(localized:"Applies to Settings and the switcher. System follows your Mac’s appearance."))
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:80),spacing:8),count:3),spacing:8) {
                    ForEach(ThemePreset.allCases,id:\.self) { preset in
                        ThemeTile(preset:preset,appearance:doc.appearance,dark:model.colorToneDark) { model.change(preview:false) { $0.appearance.preset = preset } }
                    }
                }.accessibilityElement(children:.contain).accessibilityLabel("Themes")
                help(doc.appearance.preset.detail)
            }.disabled(preferences.readOnly)
            group(String(localized:"\(doc.appearance.preset.title) colors")) {
                Picker("Preview & edit",selection:$model.colorToneDark) { Text("Light colors").tag(false); Text("Dark colors").tag(true) }.pickerStyle(.segmented).accessibilityIdentifier("appearance-color-tone")
                help(String(localized:"Previews and edits this theme’s colors. The switcher still uses the appearance chosen above."))
                colorRow(String(localized:"Key background"),token:"keyBg")
                colorRow(String(localized:"Selection accent"),token:"selection")
                let tokens = ThemeTokens.resolve(doc.appearance,dark:model.colorToneDark)
                if tokens.adjustedSelection { help(String(localized:"The selection accent is adjusted in the switcher to remain visible against the background. Your chosen color is saved.")) }
                Button("Reset light & dark colors") { model.change(preview:false) { $0.appearance.overrides[$0.appearance.preset.rawValue] = nil } }
                    .disabled(preferences.readOnly || doc.appearance.overrides[doc.appearance.preset.rawValue] == nil)
                    .help("Resets both color sets for the selected theme.").accessibilityIdentifier("appearance-reset-theme")
            }
            group(String(localized:"Legibility")) {
                Picker("Label size",selection:binding(\.appearance.scale)) { Text("Standard").tag(LabelScale.standard); Text("Large").tag(LabelScale.large); Text("Extra large").tag(LabelScale.extraLarge) }.accessibilityIdentifier("label-size")
                Toggle("Stronger outlines",isOn:binding(\.appearance.strongOutlines)).accessibilityIdentifier("appearance-strong-outlines")
                help(String(localized:"Larger labels apply to the switcher. Reduce Transparency or Increase Contrast in macOS replaces glass with solid surfaces."))
            }.disabled(preferences.readOnly)
        }
    }
    private func colorRow(_ title:String,token:String) -> some View {
        let t = ThemeTokens.resolve(doc.appearance,dark:model.colorToneDark)
        let fallback = token == "keyBg" ? t.key : t.selection
        let hex = doc.appearance.overrides[doc.appearance.preset.rawValue]?[model.colorToneDark ? "dark" : "light"]?[token]
        return HStack(spacing:8) {
            Text(title).font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading)
            ColorPicker(title,selection:Binding(get:{ Color(nsColor:NSColor(RGB(hex:hex ?? fallback.hex) ?? fallback)) },set:{c in model.change(preview:false) { $0.appearance.setColor(NSColor(c).rgb.hex,token:token,dark:model.colorToneDark) }}),supportsOpacity:false).labelsHidden()
                .disabled(preferences.readOnly).accessibilityLabel("\(title), \(model.colorToneDark ? "dark" : "light") colors")
                .accessibilityIdentifier("appearance-color-\(token)")
            Button("Reset") { model.change(preview:false) { $0.appearance.resetColor(token,dark:model.colorToneDark) } }.disabled(hex == nil || preferences.readOnly)
                .help("Restores this color for the selected light or dark color set.")
                .accessibilityLabel("Reset \(title), \(model.colorToneDark ? "dark" : "light") appearance").accessibilityIdentifier("appearance-reset-\(token)")
        }
    }
    private var browsers: some View {
        VStack(alignment:.leading,spacing:16) {
            group(String(localized:"Tab inclusion")) {
                Toggle("Include browser tabs",isOn:binding(\.browsers.enabled)).disabled(preferences.readOnly)
                Picker("Tab range",selection:binding(\.browsers.range)) { Text("All included browsers").tag(BrowserRange.all); Text("Active browser").tag(BrowserRange.activeBrowser); Text("Active browser window").tag(BrowserRange.activeWindow) }.disabled(!doc.browsers.enabled || preferences.readOnly).accessibilityIdentifier("browser-range")
                Picker("Use tabs from",selection:binding(\.browsers.automatic)) { Text("All available browsers").tag(true); Text("Choose browsers…").tag(false) }.disabled(!doc.browsers.enabled || preferences.readOnly).accessibilityIdentifier("browser-source")
                if !doc.browsers.enabled {
                    help(String(localized:"Browser tabs are hidden. Window and app switching remains available, and your browser choices are kept."))
                } else if doc.browsers.range == .all {
                    help(String(localized:"Show tabs from all included browsers with a working connection."))
                } else {
                    help(doc.browsers.range == .activeWindow ? String(localized:"Show tabs from the active window of the browser you are using when you open Tabnax. If you are using another app, no browser tabs appear.") : String(localized:"Show tabs from the browser you are using when you open Tabnax. If you are using another app, no browser tabs appear."))
                }
                if doc.browsers.enabled && !doc.browsers.automatic && doc.browsers.selected.isEmpty {
                    Label("No browsers selected. Choose at least one below to show tabs.",systemImage:"exclamationmark.circle")
                        .font(.system(size:12)).foregroundStyle(Color.orange).fixedSize(horizontal:false,vertical:true)
                        .accessibilityIdentifier("browser-selection-empty")
                }
            }
            group(String(localized:"Connections")) {
                help(doc.browsers.automatic ? String(localized:"All browsers below are included when connected. Use “Choose browsers…” above to edit the list. A checkmark does not grant browser access.") : String(localized:"Check the browsers you want to include. Connection status shows whether Tabnax can access their tabs."))
                ForEach(BrowserID.allCases,id:\.self) { browser in
                    HStack(alignment:.center,spacing:10) {
                        Toggle(browser.title,isOn:Binding(get:{doc.browsers.automatic || doc.browsers.selected.contains(browser)},set:{v in model.change { if v { $0.browsers.selected.insert(browser) } else { $0.browsers.selected.remove(browser) } }}))
                            .labelsHidden().disabled(doc.browsers.automatic || !doc.browsers.enabled || preferences.readOnly)
                            .accessibilityLabel("Include \(browser.title) tabs").accessibilityIdentifier("browser-\(browser.rawValue)")
                        BrowserSettingsIcon(browser:browser)
                        VStack(alignment:.leading,spacing:4) {
                            HStack(spacing:6) {
                                Text(browser.title).font(.system(size:13,weight:.medium))
                                Text(BrowserCatalogue.builtIn.contains(browser) ? "Automation" : "Extension")
                                    .font(.system(size:10)).foregroundStyle(.secondary)
                                    .padding(.horizontal,5).padding(.vertical,2)
                                    .background(Color.primary.opacity(0.04),in:Capsule())
                            }
                            Text(model.browserStatus[browser] ?? String(localized:"Checking availability…"))
                                .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                .accessibilityIdentifier("browser-status-\(browser.rawValue)")
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        Button("Set up…") { model.onConnect?(browser) }
                            .accessibilityLabel("Set up \(browser.title)").accessibilityIdentifier("browser-setup-\(browser.rawValue)")
                            .help(BrowserCatalogue.builtIn.contains(browser) ? "Open this browser, then approve Automation access." : browser == .safari ? "Enable the included companion in Safari’s extension settings." : "Open the companion extension installation guide.")
                    }.padding(.vertical,3)
                    if browser != BrowserID.allCases.last { Divider() }
                }
                help(String(localized:"Private tabs are excluded. Tabnax uses tab titles and window information to list and select tabs; it does not read page contents."))
                DisclosureGroup("Browser setup requirements") {
                    VStack(alignment:.leading,spacing:8) {
                        help(String(localized:"Arc, Chrome, Edge and Brave: open the browser, then choose Set up to request macOS Automation approval."))
                        help(String(localized:"Safari: enable the included Tabnax companion in Safari Settings → Extensions. Development builds may require Safari’s unsigned-extension setting."))
                        help(String(localized:"Firefox and Zen: install the companion add-on using the setup guide. This development build supports temporary installation; permanent installation requires a signed add-on."))
                    }.padding(.top,4)
                }.font(.system(size:12))
            }
        }
    }
    private func preview(width:CGFloat,height:CGFloat) -> some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Preview").font(.system(size:12,weight:.semibold)); Spacer(); if model.dirty { Text("Unsaved letters").font(.system(size:10)).foregroundStyle(.orange) } }
            if model.pane == .appearance {
                Label(model.colorToneDark ? "Dark colors" : "Light colors",systemImage:model.colorToneDark ? "moon" : "sun.max")
                    .font(.system(size:11)).foregroundStyle(.secondary).accessibilityIdentifier("preview-color-tone")
            }
            if model.pane == .position {
                PositionPreview(placement:doc.placement(for:doc.mode),mode:doc.mode,appearance:doc.appearance,targets:model.previewState.targets,compact:height < 340)
            } else {
                NativePreview(model:model,width:width-24,height:height).frame(width:width-24,height:height)
                    .clipShape(RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(Color.primary.opacity(0.18),lineWidth:0.5))
                    .shadow(color:.black.opacity(0.10),radius:10,y:5).padding(12)
                    .background { PreviewWallpaper().clipShape(RoundedRectangle(cornerRadius:10)) }.accessibilityIdentifier("native-live-preview")
                HStack(spacing:6) { Button("↑") { model.previewKey(.previous) }.accessibilityLabel("Previous preview item"); Button("↓") { model.previewKey(.next) }.accessibilityLabel("Next preview item"); Button("Enter") { model.previewKey(.enter) }.help(doc.mode == .relay && model.previewState.query == nil ? "Return to the previous window in this preview." : "Select the highlighted preview item."); Button("Back") { model.previewKey(.escape) }.help("Clear the current search or letter prefix."); Spacer(); Button("Search") { model.previewKey(.beginSearch) } }.controlSize(.small)
                Text(model.previewMessage).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                help(String(localized:"Preview actions stay here. Use your shortcut to switch real windows."))
            }
            Spacer(minLength:0)
        }.padding(.top,6)
    }

}
private struct NativePreview: NSViewRepresentable {
    @ObservedObject var model: SettingsModel
    var width: CGFloat
    var height: CGFloat
    @MainActor final class Coordinator {
        let presenter = SwitcherPresenter()
        // Last inputs actually handed to `present(...)`, so `updateNSView` can skip the
        // expensive native render when SwiftUI reruns it for an unrelated model change
        // (e.g. an async loginStatus/browserStatus update on this same ObservableObject).
        var lastState: SelectionState?
        var lastDocument: SettingsDocument?
        var lastIcons: [UUID:NSImage] = [:]
        var lastStatus: String?
        var lastSize: CGSize?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context:Context) -> NSView {
        let p = context.coordinator.presenter; p.previewOnly = true; p.embedded = true; p.previewSize = CGSize(width:width,height:height)
        p.onChoose = { id,_ in model.previewChoose(id) }; p.onKey = { key,_ in model.previewKey(key) }
        return p.embeddedView
    }
    func updateNSView(_ view:NSView,context:Context) {
        let p = context.coordinator.presenter; p.previewSize = CGSize(width:width,height:height); p.settings = model.previewDocument
        let coordinator = context.coordinator
        let status = model.labelError.isEmpty ? "" : "Last valid letters"
        let size = CGSize(width:width,height:height)
        let unchanged = coordinator.lastState == model.previewState
            && coordinator.lastDocument == p.settings
            && coordinator.lastStatus == status
            && coordinator.lastSize == size
            && iconsEqual(coordinator.lastIcons,model.icons)
        guard !unchanged else { return }
        p.present(model.previewState,icons:model.icons,status:status)
        coordinator.lastState = model.previewState
        coordinator.lastDocument = p.settings
        coordinator.lastStatus = status
        coordinator.lastSize = size
        coordinator.lastIcons = model.icons
    }
}
func shortcutTitle(_ activation: ActivationPreferences) -> String {
    let symbols: [(UInt64,String)] = [(1<<18,"⌃"),(1<<19,"⌥"),(1<<17,"⇧"),(1<<20,"⌘")]
    return symbols.filter { activation.modifiers & $0.0 != 0 }.map(\.1).joined() + " " + (activation.keyCode == 49 ? String(localized:"Space") : activation.keyCode == 48 ? String(localized:"Tab") : InputRouter.letters[activation.keyCode]?.uppercased() ?? String(localized:"Key \(activation.keyCode)"))
}


@MainActor private struct ExclusionsSettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var preferences: Preferences
    @State private var appBundle = ""
    @State private var exceptionBundle = ""
    @State private var titleBundle = ""
    @State private var pattern = ""
    @State private var match: TitleMatch = .contains
    @State private var editing: UUID?
    private var proposed: TitleRule { TitleRule(id: editing ?? UUID(), bundleID: titleBundle, pattern: pattern, match: match) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            appList(exception: false)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Window and tab titles").font(.headline)
                Text("Rules affect individual native-window and browser-tab titles. App rows and sibling windows stay available. A tab is matched by its own title, not its browser window’s title.").font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.document.exclusions.titles) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(rule.match.title): \(rule.pattern)").font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                        Text(rule.bundleID.isEmpty ? "All apps" : rule.bundleID).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Edit") { editing = rule.id; titleBundle = rule.bundleID; pattern = rule.pattern; match = rule.match }
                                .accessibilityLabel("Edit title rule \(rule.pattern)")
                            Button("Remove") { model.change { $0.exclusions.titles.removeAll { $0.id == rule.id } } }
                                .accessibilityIdentifier("remove-title-\(rule.pattern)")
                                .accessibilityLabel("Remove title rule \(rule.pattern)")
                        }
                    }
                }
                TextField("Bundle ID (empty for all apps)", text: $titleBundle).textFieldStyle(.roundedBorder).accessibilityIdentifier("title-rule-bundle")
                Picker("Match", selection: $match) { ForEach(TitleMatch.allCases, id: \.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("title-rule-match")
                TextField("Title pattern", text: $pattern).textFieldStyle(.roundedBorder).accessibilityIdentifier("title-rule-pattern")
                Text("Case-insensitive; spaces and accents are significant. Contains finds literal text; Equals matches the whole title. Wildcard matches the whole title: * = zero or more characters, ? = one character. Escape *, ? or \\ with \\. Other punctuation is literal; regular expressions are not supported.").font(.caption).foregroundStyle(.secondary)
                if let error = proposed.validationError { Text(error).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("title-rule-error") }
                HStack {
                    Button(editing == nil ? "Add title rule" : "Save title rule") {
                        let rule = proposed
                        model.change { document in
                            if let i = document.exclusions.titles.firstIndex(where: { $0.id == rule.id }) { document.exclusions.titles[i] = rule }
                            else { document.exclusions.titles.append(rule) }
                        }
                        editing = nil; pattern = ""; titleBundle = ""
                    }.disabled(proposed.validationError != nil).accessibilityIdentifier("save-title-rule")
                    if editing != nil { Button("Cancel edit") { editing = nil; pattern = ""; titleBundle = "" } }
                }
            }
            Divider()
            appList(exception: true)
            if !model.appError.isEmpty { Text(model.appError).font(.caption).foregroundStyle(.red) }
            Text("Rules save immediately and support Undo. Exclusions preserve reserved letters. Apps without bundle IDs can use all-app title rules, but cannot have app exclusions or shortcut exceptions. Saved bundle IDs remain in these lists when an app is closed, moved or uninstalled.").font(.caption).foregroundStyle(.secondary)
        }.disabled(preferences.readOnly)
    }
    private func appList(exception: Bool) -> some View {
        let rules = exception ? preferences.document.exclusions.shortcutExceptions : preferences.document.exclusions.apps
        let field = exception ? $exceptionBundle : $appBundle
        let prefix = exception ? "shortcut-exception" : "app-exclusion"
        return VStack(alignment: .leading, spacing: 10) {
            Text(exception ? "Foreground shortcut exceptions" : "Excluded apps").font(.headline)
            Text(exception ? "Let VMs, remote desktops and games receive the original activation shortcuts while foreground. This is independent of visibility. Tabnax releases its fallback hotkey registration until you switch away. The menu can still open the switcher." : "Hide every window, tab, app row and direct launch target owned by these bundle IDs. Matching is exact and case-sensitive; display names are not used.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(rules) { rule in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        if !rule.name.isEmpty { Text(rule.name).font(.system(size: 12, weight: .medium)) }
                        Text(rule.bundleID).font(.caption).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Remove") {
                        model.change {
                            if exception { $0.exclusions.shortcutExceptions.removeAll { $0.bundleID == rule.bundleID } }
                            else { $0.exclusions.apps.removeAll { $0.bundleID == rule.bundleID } }
                        }
                    }.accessibilityIdentifier("remove-\(prefix)-\(rule.bundleID)").accessibilityLabel("Remove \(rule.bundleID) from \(exception ? "shortcut exceptions" : "excluded apps")")
                }
            }
            Button("Choose application…") { model.chooseRuleApplication(exception: exception) }.accessibilityIdentifier("choose-\(prefix)")
            TextField("Bundle ID, including a closed or uninstalled app", text: field).textFieldStyle(.roundedBorder).accessibilityIdentifier("\(prefix)-bundle")
            if !field.wrappedValue.isEmpty && !AppRule.validBundleID(field.wrappedValue) {
                Text("Use letters, digits, dots, hyphens or underscores; no spaces.").font(.caption).foregroundStyle(.secondary)
            }
            Button(exception ? "Add shortcut exception" : "Add app exclusion") {
                model.addAppRule(bundleID: field.wrappedValue, exception: exception)
                if model.appError.isEmpty { field.wrappedValue = "" }
            }.disabled(!AppRule.validBundleID(field.wrappedValue) || rules.contains { $0.bundleID == field.wrappedValue }).accessibilityIdentifier("add-\(prefix)")
        }
    }
}
