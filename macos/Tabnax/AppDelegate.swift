import AppKit
import ServiceManagement
import ApplicationServices
import TabnaxCore

@main @MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let preferences = Preferences(defaults: AppDelegate.settingsDefaults())
    private static func settingsDefaults() -> UserDefaults {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of:"--test-domain"),args.indices.contains(i+1),args[i+1].hasPrefix("pl.tabnax.tests.") { return UserDefaults(suiteName:args[i+1])! }
        if args.contains("--render-settings") || args.contains("--render-preview") { return UserDefaults(suiteName:"pl.tabnax.preview.\(UUID().uuidString)")! }
        return .standard
    }
    private let focus = FocusCoordinator()
    private let launcher = ApplicationLauncher()
    private var shortcutIcons: [UUID: NSImage] = [:] { didSet { presentationIconsCache = nil } }
    // Recomputed lazily and cached: catalogue.icons/browsers?.icons/shortcutIcons only
    // change occasionally, but this is read on every keystroke via input.onState.
    // Invalidated wherever those sources are known to update (see catalogue.onChange,
    // browsers?.onChange below, and shortcutIcons' didSet above).
    private var presentationIconsCache: [UUID: NSImage]?
    private var presentationIcons: [UUID: NSImage] {
        if let cached = presentationIconsCache { return cached }
        let merged = catalogue.icons.merging(browsers?.icons ?? [:]) { old,_ in old }.merging(shortcutIcons) { old,_ in old }
        presentationIconsCache = merged
        return merged
    }
    private let presenter = SwitcherPresenter()
    private var catalogue: WindowCatalogue!
    private var input: InputRouter!
    private let hotKey = HotKeyFallback()
    private let searchHotKey = HotKeyFallback()
    private lazy var shortcutExceptions = ShortcutExceptionRouter(isPreview: { [focus] in focus.isPreviewActivation($0) }, configureFallback: { [weak self] allowed in
        guard let self else { return }
        let available = allowed && settings?.model.recordingSession == nil
        hotKey.configure(available ? preferences.document.activation : nil)
        searchHotKey.configure(available && preferences.document.searchActivation.enabled ? preferences.document.searchActivation.shortcut : nil)
    })
    private var shortcutsEnabled = false
    private func configureShortcutExceptions(enabled: Bool? = nil) {
        if let enabled { shortcutsEnabled = enabled }
        shortcutExceptions.configure(preferences.document.exclusions, enabled: shortcutsEnabled)
    }
    private var settings: SettingsController?
    private var statusItem: NSStatusItem!
    private let menuStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let menuHeader = StatusMenuHeaderView()
    private var accessibilityMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private let updates = UpdateController()
    private var modeMenuItems: [DisplayMode: NSMenuItem] = [:]
    private var demoIcons: [UUID: NSImage] = [:]
    private var health = String(localized:"Accessibility is required to control other apps' windows.")
    private var demoState = SelectionState()
    private var demo = false
    #if DEBUG
    private var shortcutFixtureWindow: NSWindow?
    private var shortcutFixtureMonitor: Any?
    private var shortcutFixtureFallback: HotKeyFallback?
    #endif
    private var switcherWasOpen = false
    private var rawSnapshot = CatalogueSnapshot()
    private var rawRegistry: [TargetID: FocusTarget] = [:]
    private var labelSession = LabelSession()
    private var mappedSnapshot = CatalogueSnapshot()
    private var browsers: BrowserCatalogue?
    private let browserIDs = Locked(Set<TargetID>())
    private let browserFocusGate = Locked<UInt64>(0)

    static func main() {
        let args = CommandLine.arguments
        if args.last == "tabnax@tabnax.local" { BrowserBridge.runNativeHost(); return }
        if args.contains("--diagnostics") {
            print("accessibilityTrusted=\(AXIsProcessTrusted())")
            print("architecture=arm64; deployment=macOS15; input=sessionEventTap; network=none")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !CommandLine.arguments.contains("--demo") { showSettings(nil) }
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let verificationArgs = CommandLine.arguments
        if let i = verificationArgs.firstIndex(of: "--verify-fixture"), verificationArgs.indices.contains(i + 2) {
            Task { await VerificationHarness.run(fixturePath: verificationArgs[i + 1], outputPath: verificationArgs[i + 2]) }
            return
        }
        #endif
        if CommandLine.arguments.contains("--render-settings") || CommandLine.arguments.contains("--render-preview") {
            var document = preferences.document
            let args = CommandLine.arguments
            func value(_ flag:String) -> String? { args.firstIndex(of:flag).flatMap { args.indices.contains($0+1) ? args[$0+1] : nil } }
            if let raw = value("--theme"),let preset = ThemePreset(rawValue:raw) { document.appearance.preset = preset }
            if let raw = value("--appearance"),let source = AppearanceSource(rawValue:raw) { document.appearance.source = source }
            if let raw = value("--label-size"),let scale = LabelScale(rawValue:raw) { document.appearance.scale = scale }
            if let raw = value("--mode"),let mode = DisplayMode(rawValue:raw) { document.mode = mode }
            var placement = document.placement(for:document.mode)
            if let raw = value("--anchor"),let anchor = Anchor(rawValue:raw) { placement.anchor = anchor }
            if let raw = value("--inset"),let inset = Double(raw) { placement.inset = inset }
            if let raw = value("--display"),let display = DisplayChoice(rawValue:raw) { placement.display = display; document.display = display }
            document.positions[document.mode.rawValue] = placement
            if args.contains("--preview-launcher") {
                document.selection.appShortcuts.enabled = true
                document.selection.appShortcuts.launchClosedApps = true
                document.selection.appShortcuts.assignments = [
                    AppAssignment(bundleID:"com.apple.Safari",name:"Safari",path:"/Applications/Safari.app",letter:"s"),
                    AppAssignment(bundleID:"com.apple.TextEdit",name:"TextEdit",path:"/System/Applications/TextEdit.app",letter:"t"),
                    AppAssignment(bundleID:"com.apple.calculator",name:"Calculator",path:"/System/Applications/Calculator.app",letter:"c")
                ]
            }
            _ = preferences.commit(document)
        }
        labelSession = LabelSession(selection:preferences.document.selection)
        focus.configureCursorMovement(preferences.document.moveCursorToSelectedWindow)
        presenter.settings = preferences.document
        #if DEBUG
        if CommandLine.arguments.contains("--all-displays"), let i = CommandLine.arguments.firstIndex(of: "--test-domain"),
           CommandLine.arguments.indices.contains(i+1), CommandLine.arguments[i+1].hasPrefix("pl.tabnax.tests.") {
            presenter.settings.allDisplays = true
        }
        #endif
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        catalogue = WindowCatalogue(alphabet: preferences.alphabet)
        catalogue.setMode(preferences.mode)
        catalogue.setDesktopSpotlightEnabled(preferences.document.appearance.desktopSpotlight.previewsWindows)
        catalogue.focusObservationToken = { [focus] in focus.observationToken }
        input = InputRouter(onState: { [weak self] state in
            guard let self else { return }
            let newlyOpened = state.active && !switcherWasOpen
            let newlyClosed = !state.active && switcherWasOpen
            switcherWasOpen = state.active
            // Committing an already-previewed app may produce no new OS activation.
            // Once closed, sample actual foreground even while focus verification finishes.
            if newlyClosed { shortcutExceptions.refresh(acceptPreview: true) }
            let missingLabels = state.targets.filter { $0.address.isEmpty }.count
            let status = missingLabels > 0 ? String(localized:"Some shortcuts are unavailable. Search or click to select a window.")
                : browserIssueMessage()
                ?? ""
            presenter.desktopSpotlightReady = focus.previewedID != nil && focus.previewedID == InputRouter.previewTarget(in: state, enabled: preferences.document.appearance.desktopSpotlight.previewsWindows)
            presenter.present(state, icons: presentationIcons, status: status)
            // present() submits the opening frame before we enqueue discovery. Merely
            // dispatching refresh asynchronously does not give deferred drawing priority.
            if newlyOpened { DispatchQueue.main.async { [weak self] in self?.catalogue.refresh(); self?.browsers?.refreshForOpening() } }
            if !state.active { presenter.prepare(mappedSnapshot, icons: presentationIcons) }
        }, onSelect: { [weak self,focus,browserIDs,launcher] id in
            if browserIDs.withValue({$0.contains(id)}) { Task { @MainActor in self?.browsers?.select(id) } }
            else if launcher.submit(id) { focus.cancel() }
            else { focus.submit(id) }
        }, onCancel: { [weak self,focus,browserFocusGate,launcher] in focus.cancel(); launcher.cancel(); browserFocusGate.withValue { $0 &+= 1 }; Task { @MainActor in self?.browsers?.cancelFocus() } },
            onPassiveKey: { [focus] in focus.disarmRepair() },
            onPreview: { [focus] id in focus.preview(id) },
            onRestorePreview: { [focus] id in focus.submit(id, moveCursor: false) },
            onAction: { [focus] action, id in focus.perform(action, on: id) },
            onHealth: { [weak self] message in self?.setHealth(message) })
        catalogue.onChange = { [weak self] snapshot, registry in
            guard let self else { return }
            // catalogue.icons only ever changes as part of a publish (reconcileProcesses()
            // adding/removing an app, or stop() clearing it), so this is a reliable
            // invalidation point without WindowCatalogue needing its own icon-change hook.
            presentationIconsCache = nil
            rawRegistry = registry; rawSnapshot = snapshot; rawSnapshot.tabs = browsers?.targets ?? []; publishCatalogue()
        }
        presenter.onSurfaces = { [weak self] frames in
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            self?.input.setSurfaces(frames.map { CGRect(x:$0.minX,y:top-$0.maxY,width:$0.width,height:$0.height) })
        }
        preferences.captureRuntime = { [weak self] in
            let old = self?.labelSession
            return { [weak self] in guard let self, let old else { return }; labelSession = old; publishCatalogue() }
        }
        preferences.prepareCommit = { new,old in
            if new.launchAtLogin != old.launchAtLogin {
                try LoginItemService().setEnabled(new.launchAtLogin)
            }
        }
        preferences.onChange = { [weak self] new,old in
            guard let self else { return }
            input.dismiss(); focus.cancel(); launcher.cancel(); presenter.dismiss(); presenter.settings = new
            focus.configureCursorMovement(new.moveCursorToSelectedWindow)
            input.configureSettings(new); configureShortcutExceptions()
            // Settings sliders and color wells commit continuously while dragging. Only
            // reconfigure what actually changed: a browser reconfigure refreshes every
            // connected browser, and a mode publish re-presents the switcher state.
            if new.mode != old.mode { input.configureMode(new.mode) }
            catalogue.setMode(new.mode)
            if new.browsers != old.browsers { browsers?.configure(new.browsers) }
            catalogue.setDesktopSpotlightEnabled(new.appearance.desktopSpotlight.previewsWindows)
            if new.selection != old.selection { labelSession = (try? labelSession.changing(to:new.selection,source:rawSnapshot)) ?? labelSession }
            if Self.affectsOnlyPresentation(new,old) { presenter.prepare(mappedSnapshot, icons: presentationIcons) }
            else { publishCatalogue() }
        }
        preferences.onSearchMemoryChange = { [weak self] memory in self?.input.configureSearchMemory(memory) }
        input.onSearchMemory = { [weak self] memory in self?.preferences.saveSearchChoices(memory) }
        input.onSearchFocus = { [weak self] session in self?.presenter.focusSearch(session: session) }
        input.onSearchInput = { [weak self] event, session in self?.presenter.deliverSearchInput(event, session: session) }
        input.configureSearchMemory(preferences.searchMemory)
        input.configureSettings(preferences.document)
        hotKey.onRetryRegistration = { [weak self] in self?.shortcutExceptions.refresh() }
        searchHotKey.onRetryRegistration = { [weak self] in self?.shortcutExceptions.refresh() }
        input.shortcutExceptionGate = shortcutExceptions.gate
        shortcutExceptions.startObserving()
        configureShortcutExceptions()
        hotKey.onFire = { [weak self] in
            guard let self, !demo, AXIsProcessTrusted(), !(settings?.model.recordingSession != nil), shortcutExceptions.permitsActivation() else { return }
            input.toggleFromHotKey()
        }
        searchHotKey.onFire = { [weak self] in
            guard let self, !demo, AXIsProcessTrusted(), settings?.model.recordingSession == nil,
                  preferences.document.searchActivation.enabled, shortcutExceptions.permitsActivation() else { return }
            input.toggleFromHotKey(search: true)
        }
        catalogue.onPermissionLost = { [weak self] in
            self?.input.stop(); self?.configureShortcutExceptions(enabled: false); self?.focus.cancel(); self?.setHealth(String(localized:"Accessibility was revoked. Enable it, then Retry."))
        }
        catalogue.onExternalActivation = { [weak self] pid in
            let previewActivation = self?.focus.isPreviewActivation(pid) == true
            self?.focus.externalActivation(pid); self?.browsers?.externalActivation(pid)
            // A different app activation closes the open overlay; panel itself is nonactivating.
            if !previewActivation && pid != Foundation.ProcessInfo.processInfo.processIdentifier { self?.input.hideForActivation() }
        }
        presenter.onChoose = { [weak self] id, session in
            guard let self else { return }
            if demo { demoEffect(demoState.select(id)) } else { input.choose(id,session:session) }
        }
        presenter.onKey = { [weak self] key, session in
            guard let self else { return }
            if demo { demoEffect(demoState.handle(key)) } else { input.key(key,session:session) }
        }
        presenter.onAction = { [weak self] action, session in
            guard let self, !demo else { return }
            input.action(action, session: session)
        }
        presenter.onMenuTracking = { [weak self] tracking, session in self?.input.setMenuTracking(tracking, session: session) }
        presenter.onMenuReady = { [weak self] session in self?.input.setMenuReady(session: session) }
        presenter.onMenuDisarm = { [weak self] session in self?.input.disarmMenuRelease(session: session) }
        presenter.onMenuAction = { [weak self] action, id, session in
            guard let self, !demo else { return }
            input.menuAction(action, target: id, session: session)
        }
        presenter.onInspectActions = { [weak self, focus] items, completion in
            if self?.demo == true {
                completion(items.map { original in
                    var item = original
                    if item.disabledReason == nil { item.disabledReason = "Preview does not control real windows" }
                    return item
                })
            } else { focus.inspectActions(items, completion: completion) }
        }
        input.onActionMenu = { [weak self] state in
            guard let self else { return }
            presenter.present(state, icons: presentationIcons, status: health)
            presenter.showActionMenu(for: state)
        }
        input.onMenuShortcut = { [weak self] action, session in
            self?.presenter.performMenuShortcut(action, session: session)
        }
        presenter.onRefresh = { [weak self] in self?.refresh() }
        focus.onWillActivate = { [weak self] in self?.presenter.dismiss() }
        focus.onPreviewRaised = { [weak self] _ in
            self?.catalogue.refreshAfterWindowPreview()
            self?.presenter.restoreSearchInputAfterPreview()
        }
        focus.onActionOutcome = { [weak self] action, id, _, message in
            self?.setHealth(message); self?.presenter.showActionOutcome(message, action: action, target: id)
            self?.catalogue.refresh(); self?.browsers?.refresh()
        }
        launcher.onOutcome = { [weak self] message in
            self?.setHealth(message); self?.preferences.report(message); self?.catalogue.refresh()
        }
        focus.onOutcome = { [weak self] outcome in
            self?.shortcutExceptions.refresh()
            self?.setHealth(outcome.message)
            if outcome.observed { self?.catalogue.recordObservedFocus(outcome.id) }
            if !outcome.observed {
                self?.catalogue.refresh()
                self?.statusItem.button?.toolTip = outcome.message
                self?.statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: String(localized:"Tabnax focus was not confirmed"))
            }
        }
        if !CommandLine.arguments.contains("--demo") && !CommandLine.arguments.contains("--render-preview") && !CommandLine.arguments.contains("--render-settings") && !CommandLine.arguments.contains("--test-domain") {
            browsers = BrowserCatalogue(focusGate:browserFocusGate)
            browsers?.onChange = { [weak self] in
                guard let self else { return }
                presentationIconsCache = nil
                rawSnapshot.tabs = browsers?.targets ?? []; publishCatalogue(); settings?.model.browserStatus = browsers?.status ?? [:]
                catalogue.excludedTabCount = browsers?.excludedCount ?? 0
            }
            browsers?.onStatusChange = { [weak self] in
                guard let self else { return }
                settings?.model.browserStatus = browsers?.status ?? [:]
                // Status can change without target changes (e.g. permission feedback).
                // Refresh an open panel's message without rerunning label allocation.
                input.update(mappedSnapshot)
            }
            browsers?.onOutcome = { [weak self] message in self?.setHealth(message); self?.preferences.report(message) }
            browsers?.configure(preferences.document.browsers)
        }
        installMenu()
        let args = CommandLine.arguments
        if args.contains("--settings") || args.contains("--render-settings") {
            demo = args.contains("--render-settings") || args.contains("--test-domain")
            if !demo { retry() }
            showSettings(nil)
            if args.contains("--compact") { settings?.window?.setContentSize(NSSize(width:820,height:650)) }
            if let i = args.firstIndex(of:"--pane"),args.indices.contains(i+1),let raw = Int(args[i+1]) { settings?.model.selectPane(SettingsPane(rawValue:raw) ?? .general) }
            if let i = args.firstIndex(of:"--render-settings"),args.indices.contains(i+1) {
                if let prefix = args.firstIndex(of:"--prefix"),args.indices.contains(prefix+1) { settings?.model.previewKey(.prefix(args[prefix+1])) }
                if let tone = args.firstIndex(of:"--settings-tone"),args.indices.contains(tone+1) { settings?.window?.appearance = NSAppearance(named:args[tone+1] == "dark" ? .darkAqua : .aqua) }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [self] in
                    do { try settings?.savePreview(to:args[i+1]) } catch { print(error) }; NSApp.terminate(nil)
                }
            }
        } else if args.contains("--demo") || args.contains("--render-preview") {
            presenter.allowsDesktopSpotlight = false
            presenter.previewOnly = args.contains("--render-preview")
            if args.contains("--compact") { presenter.previewSize = CGSize(width: 620, height: 460) }
            demo = true; loadDemo(); if !presenter.previewOnly { NSApp.activate() }
            #if DEBUG
            if args.contains("--test-search-shortcut"), let i = args.firstIndex(of:"--test-domain"), args.indices.contains(i+1), args[i+1].hasPrefix("pl.tabnax.tests.") { installSearchShortcutFixture() }
            #endif
            if let index = args.firstIndex(of: "--render-preview"), args.indices.contains(index + 1) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    do { try presenter.savePreview(to: args[index + 1]) } catch { print(error) }
                    NSApp.terminate(nil)
                }
            }
        } else {
            retry()
            let hasSeenWelcomeKey = "hasSeenWelcome"
            let isFirstRun = !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
            if isFirstRun || !AXIsProcessTrusted() {
                showSettings(nil)
                if isFirstRun {
                    settings?.model.isFirstRun = true
                    UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
                }
            }
        }
        #if DEBUG
        if let i = args.firstIndex(of: "--verify-own-selection"), args.indices.contains(i + 1) {
            showSettings(nil)
            if let window = settings?.window {
                Task { @MainActor [self] in
                    await VerificationHarness.runOwnSelection(window: window, outputPath: args[i + 1],
                        snapshot: { self.mappedSnapshot }, refresh: { self.catalogue.refresh() },
                        open: { self.input.open() }, choose: { self.input.choose($0) })
                }
            }
        }
        #endif
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        settings?.model.refreshLogin()
        if let window = settings?.window,window.isVisible { window.makeKeyAndOrderFront(nil) }
        guard input != nil, !demo else { return }
        if AXIsProcessTrusted() { retry() } else { input.stop(); configureShortcutExceptions(enabled: false); catalogue.stop(); setHealth(String(localized:"Accessibility is unavailable. Enable Tabnax and click Retry.")) }
    }
    @objc private func displayWake(_ notification: Notification) { applicationDidChangeScreenParameters(notification) }
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        // Reopen on an available display; never leave a key panel off-screen.
        input?.dismiss(); presenter.dismiss()
        focus.cancel()
        catalogue?.displaysChanged()
    }
    func applicationWillTerminate(_ notification: Notification) { hotKey.stop(); searchHotKey.stop(); input?.stop(); catalogue?.stop(); focus.cancel() }
    private func installMenu() {
        // Accessory apps still need the standard Edit responder commands so
        // native text fields support Select All, copy/paste and text Undo.
        let main = NSMenu()
        let editRoot = NSMenuItem(title:String(localized:"Edit"),action:nil,keyEquivalent:"")
        let edit = NSMenu(title:String(localized:"Edit"))
        for (title,selector,key) in [(String(localized:"Undo"),"undo:","z"),(String(localized:"Cut"),"cut:","x"),(String(localized:"Copy"),"copy:","c"),(String(localized:"Paste"),"paste:","v"),(String(localized:"Select All"),"selectAll:","a")] {
            edit.addItem(NSMenuItem(title:title,action:NSSelectorFromString(selector),keyEquivalent:key))
        }
        editRoot.submenu = edit; main.addItem(editRoot); NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: String(localized:"Tabnax"))
        statusItem.button?.toolTip = String(localized:"Tabnax — \(shortcutTitle(preferences.document.activation))")
        let menu = NSMenu(title: String(localized:"Tabnax"))
        menu.delegate = self
        menu.minimumWidth = StatusMenuHeaderView.width
        menuStatus.isEnabled = false
        menuStatus.title = String(localized:"Tabnax")
        menuStatus.view = menuHeader
        menu.addItem(menuStatus)
        menu.addItem(.separator())
        func addItem(_ title: String, symbol: String, action: Selector, key: String = "", to destination: NSMenu? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.image?.size = NSSize(width: 16, height: 16)
            (destination ?? menu).addItem(item)
            return item
        }
        accessibilityMenuItem = addItem(String(localized:"Set Up Accessibility…"), symbol: "hand.raised", action: #selector(showAccessibilitySettings))
        _ = addItem(String(localized:"Switch Windows"), symbol: "rectangle.on.rectangle", action: #selector(openSwitcher))
        let modeItem = NSMenuItem(title: String(localized:"Switcher Style"), action: nil, keyEquivalent: "")
        modeItem.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        modeItem.image?.size = NSSize(width: 16, height: 16)
        let modeMenu = NSMenu(title: String(localized:"Switcher Style"))
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.toolTip = mode.explanation
            modeMenu.addItem(item)
            modeMenuItems[mode] = item
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())
        _ = addItem(String(localized:"Settings…"), symbol: "gearshape", action: #selector(showSettings(_:)), key: ",")
        if UpdateController.isConfigured {
            updateMenuItem = addItem(String(localized:"Check for Updates…"), symbol: "arrow.down.circle", action: #selector(checkForUpdates))
            updates.onPendingUpdateChange = { [weak self] pending in self?.showPendingUpdate(pending) }
            updates.start()
        }
        let recovery = NSMenu(title: String(localized:"Troubleshooting"))
        _ = addItem(String(localized:"Refresh Windows"), symbol: "arrow.clockwise", action: #selector(refresh), to: recovery)
        _ = addItem(String(localized:"Restart Tabnax"), symbol: "arrow.triangle.2.circlepath", action: #selector(restart), to: recovery)
        let recoveryItem = NSMenuItem(title: String(localized:"Troubleshooting"), action: nil, keyEquivalent: "")
        recoveryItem.submenu = recovery; menu.addItem(recoveryItem)
        menu.addItem(.separator())
        _ = addItem(String(localized:"Quit Tabnax"), symbol: "power", action: #selector(quit), key: "q")
        statusItem.menu = menu
        updateMenuHeader()
    }
    func menuWillOpen(_ menu: NSMenu) { updateMenuHeader() }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
    private func showPendingUpdate(_ pending: Bool) {
        updateMenuItem?.title = pending ? String(localized:"Update Available…") : String(localized:"Check for Updates…")
        updateMenuItem?.image = NSImage(systemSymbolName: pending ? "arrow.down.circle.fill" : "arrow.down.circle", accessibilityDescription: nil)
        updateMenuItem?.image?.size = NSSize(width: 16, height: 16)
    }
    private func updateMenuHeader() {
        let trusted = AXIsProcessTrusted()
        menuHeader.update(mode: preferences.mode.title, shortcut: shortcutTitle(preferences.document.activation),
                          message: health, accessibilityTrusted: trusted)
        menuStatus.toolTip = health
        accessibilityMenuItem?.isHidden = trusted
        let current = preferences.mode
        for (mode, item) in modeMenuItems { item.state = mode == current ? .on : .off }
    }
    // Surfaces the specific reason browser tabs aren't showing (e.g. "Automation approval
    // required") on the HUD itself, instead of only in Settings — browsers.enabled being on
    // doesn't mean any individual browser is actually connected.
    private func browserIssueMessage() -> String? {
        guard preferences.document.browsers.enabled, mappedSnapshot.tabs.isEmpty, let statuses = browsers?.status else { return nil }
        let healthy: (String) -> Bool = { $0 == "Available" || $0 == "Not installed" || $0.hasPrefix("Connected") || $0.hasPrefix("Checking") }
        for id in BrowserID.allCases where preferences.document.browsers.includes(id) {
            if let status = statuses[id], !healthy(status) { return String(localized:"\(id.title): \(status). Check Settings → Browser tabs.") }
        }
        return nil
    }
    private func setHealth(_ message: String) {
        health = message
        updateMenuHeader()
        // update(status:) also queries the login-item service over XPC, and health changes after
        // every switch; showSettings() replays the current message when the window opens.
        if settingsVisible { settings?.update(status: message) }
        statusItem?.button?.toolTip = String(localized:"Tabnax: \(message)")
    }
    @objc private func showAccessibilitySettings() {
        showSettings(nil)
        settings?.model.selectPane(.general)
    }
    @objc private func openSwitcher() {
        if demo { loadDemo(); return }
        guard AXIsProcessTrusted() else { showSettings(nil); return }
        input.open()
    }
    @objc private func refresh() { catalogue.refresh(); browsers?.refresh() }
    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? DisplayMode else { return }
        var document = preferences.document
        document.mode = mode
        _ = preferences.commit(document)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func restart() {
        // Spawn `open` as an independent process before terminating: NSWorkspace's async
        // openApplication can drop the launch request if we terminate before its XPC
        // call lands, since it shares our process rather than forking immediately.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
    @objc private func showSettings(_ sender: Any?) {
        input.dismiss()
        if settings == nil {
            let controller = SettingsController(preferences: preferences)
            controller.model.onRecordingChange = { [weak self, weak model = controller.model] recording in
                self?.configureShortcutExceptions()
                guard recording, let session = model?.recordingSession else { self?.input.recordShortcut(using:nil); return }
                self?.input.recordShortcut { [weak model] shortcut in
                    Task { @MainActor in model?.acceptRecordedShortcut(shortcut,session:session) }
                }
            }
            controller.onRetry = { [weak self] in self?.retry() }
            controller.onRestart = { [weak self] in self?.restart() }
            controller.onClose = { [weak self] in self?.catalogue?.refresh() }
            controller.onApply = { [weak self] session in
                guard let self else { return }
                input.dismiss(); focus.cancel(); labelSession = session; publishCatalogue()
            }
            controller.onConnect = { [weak self] browser in self?.browsers?.connect(browser) }
            controller.model.browserStatus = browsers?.status ?? Dictionary(uniqueKeysWithValues:BrowserID.allCases.map { ($0,String(localized:"Preview · connection not started")) })
            settings = controller
        }
        settings?.model.receive(rawSnapshot,session:labelSession,icons:presentationIcons)
        settings?.update(status: health); settings?.show()
    }
    private func retry() {
        guard AXIsProcessTrusted() else { input.stop(); configureShortcutExceptions(enabled: false); catalogue.stop(); setHealth(String(localized:"Accessibility is required for window titles, exact focus, and the activation shortcut. Enable Tabnax in System Settings, then Retry.")); return }
        catalogue.start()
        input.start(snapshot: mappedSnapshot, mode: preferences.mode)
        configureShortcutExceptions(enabled: true)
    }
    private func publishCatalogue() {
        let d = preferences.document
        var source = ApplicationShortcuts.includingClosedApps(rawSnapshot,preferences:d.selection.appShortcuts)
        // A tab's own id is per-connection, not the browser's process, so resolve its
        // real owning app by bundleID before mapping — this is what lets Fold/Canopy
        // nest it under the right app container.
        // Two processes can briefly share a bundle ID (e.g. mid-relaunch, or an app that
        // allows multiple instances), so tolerate duplicates instead of crashing.
        source = source.resolvingTabOwners()
        mappedSnapshot = d.exclusions.applying(to: labelSession.map(source))
        focus.update(rawRegistry.filter { !mappedSnapshot.suppressedIDs.contains($0.key) })
        // Assigning invalidates the merged icon cache, so only do it for a real change;
        // IconCache hands back the same NSImage instances, which keeps this comparison cheap.
        let icons = ApplicationShortcuts.icons(d.selection.appShortcuts.assignments,source:source)
        if icons != shortcutIcons { shortcutIcons = icons }
        var launches: [TargetID: AppAssignment] = [:]
        if d.selection.appShortcuts.enabled && d.selection.appShortcuts.launchClosedApps {
            for target in mappedSnapshot.apps where !target.isRunning {
                if let app = d.selection.appShortcuts.assignment(for:target) { launches[target.id] = app }
            }
        }
        launcher.update(launches)
        mappedSnapshot.windows = mappedSnapshot.windows.filter { (d.includeMinimized || !$0.minimized) && (d.includeHidden || !$0.hidden) }
        mappedSnapshot.apps = mappedSnapshot.apps.filter { d.includeHidden || !$0.hidden || d.selection.appShortcuts.assignment(for:$0) != nil }
        mappedSnapshot.tabs = mappedSnapshot.tabs.filter { d.browsers.enabled && !$0.excluded }
        browserIDs.withValue { $0 = Set(mappedSnapshot.tabs.map(\.id)) }
        input.update(mappedSnapshot)
        presenter.prepare(mappedSnapshot, icons: presentationIcons)
        // The settings preview re-runs the whole labelling pipeline; a closed window has no
        // use for that, and showSettings() brings it up to date before reopening.
        if settingsVisible { settings?.model.receive(rawSnapshot,session:labelSession,icons:presentationIcons) }
    }
    /// Appearance and placement never change the mapped catalogue or the settings preview's
    /// targets, so rerunning the labelling pipeline (and the settings preview's copy of it)
    /// for them is wasted work; the presenter only needs its warmed rows restyled.
    private static func affectsOnlyPresentation(_ new: SettingsDocument, _ old: SettingsDocument) -> Bool {
        var unchanged = new
        unchanged.appearance = old.appearance; unchanged.positions = old.positions; unchanged.display = old.display
        return unchanged == old
    }
    /// A minimized window counts: it comes back without passing through showSettings().
    private var settingsVisible: Bool { settings?.window.map { $0.isVisible || $0.isMiniaturized } ?? false }
    private func loadDemo() {
        var book = try! AddressBook()
        var children: [UUID: AddressBook] = [:]
        var apps: [Target] = []
        var specs = [("Xcode", "Tabnax · InputRouter.swift"), ("Safari", "Tabnax · Keyboard guide"),
                     ("Safari", "Tabnax · Layout preview"), ("Finder", "Assets"), ("Figma", "Interaction studies"),
                     ("Terminal", "tabnax · swift test"), ("Notes", "Switching · Interview notes"), ("Safari", "Weekend walks"),
                     ("Xcode", "Review changes"), ("Finder", "Exports")]
        #if DEBUG
        if CommandLine.arguments.contains("--search-fixture"), CommandLine.arguments.contains("--test-domain") {
            specs = [("Alpha", "Remote configuration"), ("Alpha", "Really cool notes"), ("Beta", "rc"), ("Beta", "recent changes")]
        }
        #endif
        let bundleIDs = ["Xcode": "com.apple.dt.Xcode", "Safari": "com.apple.Safari", "Finder": "com.apple.finder",
                         "Terminal": "com.apple.Terminal", "Notes": "com.apple.Notes", "Figma": "com.figma.Desktop"]
        var processIDs: [String: UUID] = [:]
        demoIcons.removeAll()
        // Apps and windows now draw addresses from the same shared pool.
        var appCodes: [UUID: String] = [:]
        let targets = specs.enumerated().map { index, spec in
            let token = processIDs[spec.0] ?? UUID(); processIDs[spec.0] = token
            if demoIcons[token] == nil, let bundle = bundleIDs[spec.0], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                demoIcons[token] = NSWorkspace.shared.icon(forFile: url.path)
            }
            let appID = TargetID(process: token)
            if appCodes[token] == nil {
                let appCode = try! book.address(for: appID)
                appCodes[token] = appCode
                apps.append(Target(id: appID, app: spec.0, title: spec.0, address: appCode, foldAddress: appCode))
            }
            let id = TargetID(process: token, window: UUID())
            if children[token] == nil { children[token] = try! AddressBook() }
            let fold = appCodes[token]! + (try! children[token]!.address(for: id))
            let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1400, height: 900)
            let bounds = CGRect(x: screen.minX + 30 + CGFloat(index%3)*400, y: 55 + CGFloat(index/3)*140, width: 380, height: 260)
            return Target(id: id, app: spec.0, title: spec.1, address: try! book.address(for: id), minimized: index == 7, foldAddress: fold, bounds: bounds, onScreen: index < 3)
        }
        let args = CommandLine.arguments
        let mode = args.firstIndex(of: "--mode").flatMap { args.indices.contains($0+1) ? DisplayMode(rawValue: args[$0+1]) : nil } ?? preferences.mode
        var history = FocusHistory(); history.observe(targets[1].id); history.observe(targets[0].id)
        #if DEBUG
        if args.contains("--search-fixture"), args.contains("--test-domain") {
            apps.insert(Target(id: .init(process: UUID()), app: "rc", title: "Closed only", address: "z", foldAddress: "z", isRunning: false), at: 0)
        }
        #endif
        demoState.configure(mode: mode)
        var order = preferences.document.traversalOrder
        #if DEBUG
        if args.contains("--test-domain"), let i = args.firstIndex(of: "--order"), args.indices.contains(i+1),
           let requested = TraversalOrder(rawValue: args[i+1]) { order = requested }
        #endif
        demoState.configure(ordering: order)
        demoState.update(.init(windows: targets, apps: apps, allocated: book.allocated, history: history)); demoState.open()
        if let i = args.firstIndex(of: "--prefix"), args.indices.contains(i+1) { _ = demoState.handle(.prefix(args[i+1])) }
        if let i = args.firstIndex(of: "--search"), args.indices.contains(i+1) {
            _ = demoState.handle(.beginSearch); _ = demoState.handle(.query(args[i+1]))
        }
        presenter.present(demoState, icons: demoIcons, status: "")
    }
    #if DEBUG
    /// Isolated UI fixture: real router, presenter and Carbon dispatcher; no global tap,
    /// hotkey reservation, real target registry, login registration or preference mutation.
    private func installSearchShortcutFixture() {
        presenter.dismiss()
        var fixtureSettings = presenter.settings; fixtureSettings.searchActivation.enabled = true
        fixtureSettings.activation.behavior = .hold; fixtureSettings.activation.quietReturn = true
        if fixtureSettings.allDisplays { fixtureSettings.mouse = .clickAndWheel }
        presenter.settings = fixtureSettings
        let source = demoState.snapshot, mode = demoState.mode
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:160),styleMask:[.titled],backing:.buffered,defer:false)
        window.title = "Shortcut fixture"; window.identifier = .init("shortcut-fixture"); window.isReleasedWhenClosed = false
        let sink = NSTextField(string: ""); sink.placeholderString = "Input must stay empty"; sink.identifier = .init("shortcut-fixture-sink")
        sink.frame = NSRect(x:20,y:75,width:380,height:28); window.contentView?.addSubview(sink)
        let count = NSTextField(labelWithString:"0"); count.identifier = .init("shortcut-fixture-selection-count")
        count.frame = NSRect(x:20,y:2,width:80,height:20); window.contentView?.addSubview(count)
        let displays = NSTextField(labelWithString:"\(NSScreen.screens.count)"); displays.identifier = .init("shortcut-fixture-display-count")
        displays.frame = NSRect(x:100,y:2,width:80,height:20); window.contentView?.addSubview(displays)
        let result = NSTextField(labelWithString:"No selection"); result.identifier = .init("shortcut-fixture-result")
        result.frame = NSRect(x:20,y:25,width:380,height:28); window.contentView?.addSubview(result)
        input = InputRouter(onState:{ [weak self] state in
            guard let self else { return }; presenter.present(state,icons:demoIcons,status:"")
        },onSelect:{ id in Task { @MainActor in result.stringValue = source.windows.first { $0.id == id }?.title ?? "Selected"; count.integerValue += 1 } },onCancel:{},onHealth:{ _ in })
        input.onSearchFocus = { [weak self] in self?.presenter.focusSearch(session:$0) }
        input.onSearchInput = { [weak self] in self?.presenter.deliverSearchInput($0,session:$1) }
        presenter.onKey = { [weak self] in self?.input.key($0,session:$1) }
        presenter.onChoose = { [weak self] in self?.input.choose($0,session:$1) }
        _ = input.replayForTesting(snapshot:source,mode:mode,settings:fixtureSettings,events:[])
        input.markRunningForTesting()
        let useFallback = CommandLine.arguments.contains("--test-fallback")
        if useFallback {
            let fallback = HotKeyFallback(keyIsDown:{ _ in false },register:{ _ in true },unregister:{},installHandlerForTesting:true)
            fallback.configure(fixtureSettings.searchActivation.shortcut)
            fallback.onFire = { [weak self] in self?.input.toggleFromHotKey(search:true) }
            shortcutFixtureFallback = fallback
        }
        shortcutFixtureMonitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { () -> EventRoute in
                guard let self, let cg = event.cgEvent else { return EventRoute(event:event) }
                if useFallback {
                    if event.keyCode == 49 && event.modifierFlags.intersection([.control,.shift,.option,.command]) == [.control,.shift] {
                        if event.type == .keyDown && !event.isARepeat { self.shortcutFixtureFallback?.sendPressForTesting() }
                        return EventRoute(event:nil)
                    }
                    return EventRoute(event:event)
                }
                return EventRoute(event:self.input.routeForTesting(cg) ? nil : event)
            }.event
        }
        shortcutFixtureWindow = window; window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(sink)
    }
    #endif
    private func demoEffect(_ effect: SelectionEffect) {
        presenter.present(demoState, icons: demoIcons, status: "")
        if case .selected = effect { Trace.signposter.emitEvent("demoSelectionAccepted") }
    }
}
