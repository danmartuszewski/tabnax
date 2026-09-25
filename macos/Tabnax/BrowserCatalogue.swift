import AppKit
import SafariServices
import ApplicationServices
import Carbon
import TabnaxCore

private struct ScriptResult: Sendable { var tabs: [BrowserTabRecord] = []; var error: String?; var selected = false }
/// Distinguishes a tab that's merely filtered out by the user's browser-scope preference
/// (still live, just not eligible right now) from one whose underlying browser connection
/// is actually unhealthy — `Target.excluded` alone can't tell these apart.
enum TabUnavailableReason: Equatable { case filteredByRange, connectionUnhealthy }
@MainActor final class BrowserCatalogue: ObservableObject {
    private struct Connection {
        var generation = UUID()
        var launchDate: Date?
        var pid: pid_t
        var ids: [String:UUID] = [:]
        var tabs: [BrowserTabRecord] = []
        var healthy = false
    }
    @Published private(set) var status: [BrowserID:String] = [:] {
        didSet { if status != oldValue { onStatusChange?() } }
    }
    /// Per-tab reason a target isn't currently selectable, keyed alongside `targets`/`routes`.
    /// Rebuilt every `publish()`. See `TabUnavailableReason`.
    private(set) var unavailableReasons: [TargetID:TabUnavailableReason] = [:]
    /// Live tabs currently held out of the switcher by the user's browser-scope preference
    /// (not by a connection problem) — they still occupy an address so their label survives
    /// if the preference is toggled back. Surfaced so an "address pool full" message elsewhere
    /// can explain why, instead of just reporting the pool is full.
    var excludedCount: Int { targets.filter(\.excluded).count }
    private var connections: [BrowserID:Connection] = [:]
    // Last pid/launchDate a built-in browser was seen at, kept even after it fully quits
    // (unlike `connections`, which is nil'd out while not running) so `discover()` can tell
    // "first time we've ever seen this browser" apart from "it relaunched," and only warn
    // about the address-identity reset (see `Connection.generation`) in the latter case.
    private var lastKnownLaunch: [BrowserID:(pid_t,Date?)] = [:]
    private var extensionConnections: [UUID:(BrowserID,[BrowserTabRecord],BrowserPeer)] = [:]
    private var extensionIDs: [UUID:[String:UUID]] = [:]
    private var routes: [TargetID:(BrowserID,BrowserTabRecord,UUID?)] = [:]
    private let worker: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.name = "Tabnax browser adapters"; return q }()
    private var busy = Set<BrowserID>()
    // Tracks in-flight async reads for the current refresh() cycle (and any overlapping
    // one), so publish() only rebuilds the target list once they've all completed.
    private var pendingRefreshOps = 0
    // Automation-permission probes are AppleEvents (AECreateDesc / AEDeterminePermissionToAutomateTarget)
    // and must not run synchronously on the main actor. Results are cached with a short TTL and
    // refreshed on the background `worker` queue; `discover()` reads the cache synchronously.
    private var permissionCache: [BrowserID:OSStatus] = [:]
    private var permissionCheckedAt: [BrowserID:Date] = [:]
    private var permissionChecking = Set<BrowserID>()
    private var permissionRevision: [BrowserID:UInt64] = [:]
    private let observesSystem: Bool
    private static let permissionTTL: TimeInterval = 10
    private var preferences = BrowserPreferences()
    private var focusGeneration: UInt64 = 0
    private let focusGate: Locked<UInt64>
    private var bridge: BrowserBridge?
    private var bridgeError: String?
    private var requests: [String:(TargetID,UInt64)] = [:]
    private var expectedBrowser: BrowserID?
    var activeBrowser: BrowserID?
    var onChange: (() -> Void)?
    /// Connection status can change without affecting any selectable targets.
    var onStatusChange: (() -> Void)?
    var onOutcome: ((String) -> Void)?
    private(set) var targets: [Target] = []
    private(set) var icons: [UUID:NSImage] = [:]
    private var browserIcons: [BrowserID:NSImage] = [:]
    static let builtIn: Set<BrowserID> = [.arc,.chrome,.edge,.brave]
    init(focusGate:Locked<UInt64> = Locked(0), observesSystem: Bool = true) {
        self.focusGate = focusGate
        self.observesSystem = observesSystem
        guard observesSystem else { return }
        bridge = BrowserBridge(onMessage:{ [weak self] message,peer in self?.receive(message,peer:peer) },onDisconnect:{ [weak self] id in self?.disconnected(id) })
        do { try bridge?.start() } catch { bridgeError = "Browser bridge unavailable: " + error.localizedDescription }
        discover()
    }
    func configure(_ value: BrowserPreferences) {
        if preferences != value { cancelFocus() }
        preferences = value
        for (id,(browser,_,peer)) in extensionConnections { peer.send(["version":1,"kind":"configure","connection":id.uuidString,"enabled":value.includes(browser)]) }
        refresh()
    }
    func discover() {
        guard observesSystem else { return }
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != Foundation.ProcessInfo.processInfo.processIdentifier {
            activeBrowser = BrowserID.allCases.first { $0.bundleID == app.bundleIdentifier }
        }
        // Assign once: every write to a @Published dictionary notifies observers, even an equal one.
        var next = status
        defer { if next != status { status = next } }
        for browser in BrowserID.allCases {
            guard let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier:browser.bundleID) else { next[browser] = "Not installed"; continue }
            if browserIcons[browser] == nil { browserIcons[browser] = NSWorkspace.shared.icon(forFile:installedURL.path) }
            if !Self.builtIn.contains(browser) {
                next[browser] = bridgeError ?? (extensionConnections.values.contains { $0.0 == browser } ? "Connected through companion" : "Companion add-on required")
                continue
            }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleID).first else { next[browser] = "Installed · not running"; connections[browser] = nil; continue }
            if connections[browser]?.pid != app.processIdentifier || connections[browser]?.launchDate != app.launchDate {
                connections[browser] = Connection(launchDate:app.launchDate,pid:app.processIdentifier)
                let previous = lastKnownLaunch[browser]
                if let previous, previous.0 != app.processIdentifier || previous.1 != app.launchDate {
                    // Every relaunch gets a fresh connection generation, so tabs get new
                    // TargetIDs and lose whatever addresses/pins they held. Unlike windows
                    // and pinned app letters, that loss is currently silent — say so.
                    onOutcome?("Tab addresses reset — \(browser.title) restarted")
                }
                lastKnownLaunch[browser] = (app.processIdentifier,app.launchDate)
            }
            if let cached = permissionCache[browser] {
                next[browser] = cached == noErr ? "Available" : "Automation approval required"
                if cached != noErr { connections[browser]?.healthy = false }
            } else {
                next[browser] = "Checking automation approval…"
            }
            refreshPermission(browser)
        }
    }
    /// Probes automation permission for `browser` on the background worker queue and
    /// caches the result. Skips the probe if one is already in flight or the cache is
    /// still fresh, so repeated `discover()` calls (menu open, activation, timers) stay cheap.
    private func refreshPermission(_ browser:BrowserID) {
        guard !permissionChecking.contains(browser) else { return }
        if let checkedAt = permissionCheckedAt[browser], Date().timeIntervalSince(checkedAt) < Self.permissionTTL { return }
        permissionChecking.insert(browser)
        let revision = permissionRevision[browser, default:0]
        worker.addOperation { [weak self] in
            let result = Self.permission(browser,ask:false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                permissionChecking.remove(browser)
                guard permissionRevision[browser, default:0] == revision else { return }
                acceptPermission(result, for:browser)
            }
        }
    }
    private func acceptPermission(_ result:OSStatus, for browser:BrowserID) {
        permissionCache[browser] = result
        permissionCheckedAt[browser] = Date()
        guard connections[browser] != nil else { publish(); return }
        status[browser] = result == noErr ? "Available" : "Automation approval required"
        if result != noErr { connections[browser]?.healthy = false }
        // Publish revocations immediately, and fetch tabs after an approval arrives;
        // neither should depend on the next activation or settings edit.
        if result == noErr { refresh() } else { publish() }
    }
    /// Opening the switcher only refreshes browser data when tabs are enabled.
    /// Explicit refresh/configuration still discovers browsers for Settings and
    /// reconciles process lifetimes, including when tabs are disabled.
    func refreshForOpening() {
        guard preferences.enabled else { return }
        refresh()
    }
    func refresh() {
        guard observesSystem else { publish(); return }
        discover()
        for browser in Self.builtIn where preferences.includes(browser) && status[browser] == "Available" && !busy.contains(browser) {
            guard let generation = connections[browser]?.generation else { continue }
            busy.insert(browser)
            pendingRefreshOps += 1
            worker.addOperation { [weak self] in
                let result = Self.read(browser)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    busy.remove(browser)
                    if connections[browser]?.generation == generation, permissionCache[browser] == noErr {
                        if let error = result.error { status[browser] = error; connections[browser]?.healthy = false }
                        else { connections[browser]?.tabs = result.tabs; connections[browser]?.healthy = true; status[browser] = "Connected · \(result.tabs.count) tabs" }
                    }
                    // Coalesce: a single refresh() cycle fires one async read per built-in
                    // browser (up to 4). Only publish once all of them have completed,
                    // instead of rebuilding the full target list after each one lands.
                    pendingRefreshOps -= 1
                    if pendingRefreshOps <= 0 { publish() }
                }
            }
        }
        publish()
    }
    func externalActivation(_ pid: pid_t) {
        guard pid != Foundation.ProcessInfo.processInfo.processIdentifier else { return }
        let bundle = NSRunningApplication(processIdentifier:pid)?.bundleIdentifier
        activateBrowser(BrowserID.allCases.first { $0.bundleID == bundle })
    }
    private func activateBrowser(_ browser:BrowserID?) {
        let changed = activeBrowser != browser
        activeBrowser = browser
        // Cancellation is independent of whether the new activation affects the
        // visible tab range, including repeated activations of non-browser apps.
        if activeBrowser != expectedBrowser { cancelFocus() }
        guard changed, preferences.enabled, preferences.range != .all else { return }
        publish()
    }
    func cancelFocus() {
        // Called on every mouse click system-wide (InputRouter's onCancel), so skip the
        // generation bump and extension broadcast when there is nothing in flight to cancel.
        guard expectedBrowser != nil || !requests.isEmpty else { return }
        focusGeneration = focusGate.withValue { $0 &+= 1; return $0 }; requests.removeAll(); expectedBrowser = nil
        for (id,(_,_,peer)) in extensionConnections { peer.send(["version":1,"kind":"cancel","connection":id.uuidString]) }
    }
    func owns(_ id:TargetID) -> Bool { routes[id] != nil }
    func select(_ id:TargetID) {
        guard let (browser,tab,connection) = routes[id], preferences.includes(browser),
              targets.contains(where: { $0.id == id && $0.available && !$0.excluded }) else { return }
        let generation = focusGate.withValue { $0 &+= 1; return $0 }; focusGeneration = generation; expectedBrowser = browser
        if let connection, let peer = extensionConnections[connection]?.2 {
            let request = UUID().uuidString; requests[request] = (id,generation)
            peer.send(["version":1,"kind":"select","connection":connection.uuidString,"request":request,"tab":tab.id,"window":tab.window])
            Task { @MainActor [weak self] in
                try? await Task.sleep(for:.seconds(3))
                guard let self, requests.removeValue(forKey:request) != nil else { return }
                onOutcome?("Browser selection was not confirmed. Refresh tabs and try again.")
            }
            return
        }
        guard connections[browser]?.healthy == true else { return }
        let gate = focusGate
        worker.addOperation { [weak self] in
            guard gate.withValue({ $0 == generation }) else { return }
            let result = Self.focus(browser,tab:tab)
            Task { @MainActor [weak self] in
                guard let self, focusGate.withValue({ $0 == generation }) else { return }
                let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browser.bundleID
                expectedBrowser = nil
                onOutcome?(result.selected && foreground ? "Selected \(browser.title) tab" : result.error ?? "The exact browser tab could not be confirmed.")
                refresh()
            }
        }
    }
    func connect(_ browser:BrowserID) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:browser.bundleID) != nil else { onOutcome?("Install \(browser.title), then return to Tabnax."); return }
        if Self.builtIn.contains(browser) {
            guard NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleID).first != nil else { onOutcome?("Open \(browser.title), then choose Set up again."); return }
            let alert = NSAlert(); alert.messageText = "Connect \(browser.title)?"
            alert.informativeText = "Tabnax uses Automation to list non-private tabs and select the exact tab you choose. macOS may ask for approval. No page contents are read."
            alert.addButton(withTitle:"Continue"); alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            // An earlier passive probe must not overwrite this explicit approval result.
            permissionRevision[browser, default:0] &+= 1
            worker.addOperation { [weak self] in
                let result = Self.permission(browser,ask:true)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Seed the cache with this authoritative, user-prompted result so the
                    // refresh() below doesn't show a transient "Checking…" state.
                    onOutcome?(result == noErr ? "\(browser.title) approved" : "Automation was not approved. You can retry in System Settings.")
                    acceptPermission(result, for:browser)
                }
            }
        } else {
            if let bridgeError { onOutcome?(bridgeError); return }
            if browser == .safari {
                SFSafariApplication.showPreferencesForExtension(withIdentifier:"pl.tabnax.Tabnax.Safari") { [weak self] error in
                    let message = error.map { "Safari setup: " + $0.localizedDescription } ?? "Enable the Tabnax companion in Safari Extensions."
                    Task { @MainActor in self?.onOutcome?(message) }
                }
                return
            }
            do { try BrowserBridge.installHost(for:browser) } catch { onOutcome?(error.localizedDescription); return }
            let alert = NSAlert(); alert.messageText = "Connect \(browser.title) with the companion"
            alert.informativeText = browser == .safari ? "The Safari companion is included with Tabnax. Enable it in Safari Settings → Extensions. Safari controls extension approval; a development build may require Safari’s Allow Unsigned Extensions option." : "The app-side connection is ready. Install the Tabnax companion in \(browser.title). This development build includes the source add-on; a signed add-on is required for a normal permanent installation. The setup guide includes the browser’s temporary development-loading steps."
            alert.addButton(withTitle:"Open setup guide"); alert.addButton(withTitle:"Done")
            if alert.runModal() == .alertFirstButtonReturn, let url = Bundle.main.url(forResource:"SETUP",withExtension:"html",subdirectory:"BrowserCompanion") { NSWorkspace.shared.open(url) }
        }
    }
    private func publish() {
        var all: [Target] = []
        var nextRoutes: [TargetID:(BrowserID,BrowserTabRecord,UUID?)] = [:]
        var nextIcons: [UUID:NSImage] = [:]
        var nextUnavailableReasons: [TargetID:TabUnavailableReason] = [:]
        func append(_ browser:BrowserID,_ records:[BrowserTabRecord],generation:UUID,ids:inout [String:UUID],healthy:Bool,extensionID:UUID?) {
            nextIcons[generation] = browserIcons[browser]
            for tab in records where !tab.incognito {
                let token = ids[tab.id] ?? UUID(); ids[tab.id] = token
                let id = TargetID(process:generation,window:token)
                nextRoutes[id] = (browser,tab,extensionID)
                // Keep raw live targets even when a preference excludes them. Eligibility
                // is separate, so re-enabling restores their labels.
                let included = preferences.includes(browser) && (preferences.range == .all || activeBrowser == browser) && (preferences.range != .activeWindow || tab.focusedWindow)
                if !included { nextUnavailableReasons[id] = .filteredByRange }
                else if !healthy { nextUnavailableReasons[id] = .connectionUnhealthy }
                all.append(Target(id:id,app:browser.title,title:tab.title,address:"",available:healthy && included,group:browser.title + " · " + (tab.group ?? "Window \(tab.window)"),excluded:!included,bundleID:browser.bundleID))
            }
            let live = Set(records.filter { !$0.incognito }.map(\.id))
            ids = ids.filter { live.contains($0.key) }
        }
        for browser in BrowserID.allCases {
            if var c = connections[browser] { append(browser,c.tabs,generation:c.generation,ids:&c.ids,healthy:c.healthy,extensionID:nil); connections[browser] = c }
        }
        for (id,(browser,tabs,_)) in extensionConnections.sorted(by:{ $0.key.uuidString < $1.key.uuidString }) {
            var ids = extensionIDs[id] ?? [:]; append(browser,tabs,generation:id,ids:&ids,healthy:true,extensionID:id); extensionIDs[id] = ids
        }
        // Always refresh selection routes: tab metadata can change without
        // changing its rendered target. Only remap the app/window catalogue when
        // the published browser contribution actually changes.
        routes = nextRoutes
        let changed = targets != all || icons != nextIcons || unavailableReasons != nextUnavailableReasons
        targets = all; icons = nextIcons; unavailableReasons = nextUnavailableReasons
        if changed { onChange?() }
    }
    private func receive(_ message:BrowserMessage,peer:BrowserPeer) {
        guard let checked = try? message.validated(), let browser = checked.browser, let id = UUID(uuidString:checked.connection), !Self.builtIn.contains(browser) else { peer.close(); return }
        if checked.kind == "hello" {
            if extensionConnections[id]?.2.id != peer.id { extensionConnections[id] = (browser,[],peer); extensionIDs[id] = nil }
            peer.send(["version":1,"kind":"configure","connection":id.uuidString,"enabled":preferences.includes(browser)])
        } else if extensionConnections[id]?.2.id != peer.id || extensionConnections[id]?.0 != browser {
            peer.close()
        } else if checked.kind == "snapshot",let tabs = checked.tabs {
            extensionConnections[id] = (browser,tabs,peer); status[browser] = "Connected · \(tabs.count) tabs"; publish()
        } else if checked.kind == "result",let request = checked.request,let (target,generation) = requests[request],routes[target]?.2 == id,focusGate.withValue({ $0 == generation }) {
            requests[request] = nil
            expectedBrowser = nil
            let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == browser.bundleID
            onOutcome?(checked.selected == true && foreground ? "Selected \(browser.title) tab" : checked.error ?? "Browser selection was not confirmed.")
        }
    }
    private func disconnected(_ peerID:UUID) {
        for (id,value) in extensionConnections where value.2.id == peerID {
            extensionConnections[id] = nil; extensionIDs[id] = nil
            // Firefox/Zen currently run the companion as a temporary add-on (see
            // BrowserCompanion/SETUP.html): it unloads whenever the browser quits and must be
            // reloaded by hand via about:debugging — reopening the browser alone won't restore
            // it, unlike the other companion-based browsers once a signed add-on ships.
            status[value.0] = (value.0 == .firefox || value.0 == .zen)
                ? "Companion disconnected · reload the temporary add-on in about:debugging, then reopen \(value.0.title)"
                : "Companion disconnected · open browser to reconnect"
        }
        publish()
    }
    nonisolated private static func permission(_ browser:BrowserID,ask:Bool) -> OSStatus {
        let data = Array(browser.bundleID.utf8)
        var target = AEAddressDesc()
        let created = data.withUnsafeBytes { AECreateDesc(DescType(typeApplicationBundleID),$0.baseAddress,data.count,&target) }
        guard created == noErr else { return OSStatus(created) }; defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target,AEEventClass(typeWildCard),AEEventID(typeWildCard),ask)
    }
    nonisolated private static let scripts = CompiledScripts()
    /// Runs a cached compilation of `source`, or the handler `call` names inside it. Compiling
    /// loads the browser's scripting dictionary, which costs more than a typical tab read.
    nonisolated private static func execute(_ browser:BrowserID,pid:pid_t,focus:Bool,source:() -> String,call:NSAppleEventDescriptor? = nil) -> (NSAppleEventDescriptor?,String?) {
        var error: NSDictionary?
        guard let script = scripts.take(browser,pid:pid,focus:focus) ?? NSAppleScript(source:source()) else { return (nil,"Browser script could not compile") }
        let result = call.map { script.executeAppleEvent($0,error:&error) } ?? script.executeAndReturnError(&error)
        if script.isCompiled { scripts.give(script,browser,pid:pid,focus:focus) }
        if let error { return (nil,error[NSAppleScript.errorMessage] as? String ?? "Browser unavailable") }
        return (result,nil)
    }
    nonisolated private static func read(_ browser:BrowserID) -> ScriptResult {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleID).first else { return .init(error:"Browser is closed") }
        let (result,error) = execute(browser,pid:app.processIdentifier,focus:false,source:{ Self.queryScript(browser) })
        guard let result,error == nil else { return .init(error:error) }
        var tabs: [BrowserTabRecord] = [], seen = Set<String>()
        if result.numberOfItems > 0 { for i in 1...min(4000,result.numberOfItems) {
            guard let row = result.atIndex(i),row.numberOfItems == 5,let id = row.atIndex(1)?.stringValue,let window = row.atIndex(2)?.stringValue,let title = row.atIndex(3)?.stringValue else { continue }
            if seen.insert(id).inserted { tabs.append(.init(id:id,window:window,title:String(title.prefix(4096)),active:row.atIndex(4)?.booleanValue ?? false,focusedWindow:row.atIndex(5)?.booleanValue ?? false)) }
        } }
        return .init(tabs:tabs)
    }
    /// Every property read inside `tell` is a separate Apple event, so the ids and titles of a
    /// window are fetched as two lists rather than per tab; with hundreds of tabs that is the
    /// difference between a handful of round trips and thousands. A browser that refuses the
    /// list form, or whose tabs changed between the two reads, drops to the per-tab loop.
    nonisolated static func queryScript(_ browser:BrowserID) -> String {
        let privateCheck = browser == .arc ? "incognito of w is false" : "mode of w is \"normal\""
        return """
        with timeout of 2 seconds
            tell application id "\(browser.bundleID)"
                set rows to {}
                repeat with w in windows
                    if \(privateCheck) then
                        set windowID to id of w as text
                        set isFront to index of w is 1
                        set activeID to id of active tab of w as text
                        set bulk to false
                        try
                            set tabIDs to id of tabs of w
                            set tabTitles to title of tabs of w
                            if (count of tabIDs) is (count of tabTitles) then set bulk to true
                        end try
                        if bulk then
                            repeat with n from 1 to count of tabIDs
                                set tabID to (item n of tabIDs) as text
                                set end of rows to {tabID, windowID, (item n of tabTitles) as text, tabID is activeID, isFront}
                            end repeat
                        else
                            repeat with t in tabs of w
                                set tabID to id of t as text
                                set end of rows to {tabID, windowID, title of t as text, tabID is activeID, isFront}
                            end repeat
                        end if
                    end if
                end repeat
                return rows
            end tell
        end timeout
        """
    }
    nonisolated private static func literal(_ text:String) -> String { "\"" + text.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"") + "\"" }
    nonisolated private static func focus(_ browser:BrowserID,tab:BrowserTabRecord) -> ScriptResult {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:browser.bundleID).first else { return .init(error:"Browser is closed") }
        // Identities travel as handler parameters, so one compilation serves every selection.
        let call = NSAppleEventDescriptor(eventClass:AEEventClass(kASAppleScriptSuite),eventID:AEEventID(kASSubroutineEvent),
            targetDescriptor:.currentProcess(),returnID:AEReturnID(kAutoGenerateReturnID),transactionID:AETransactionID(kAnyTransactionID))
        call.setDescriptor(NSAppleEventDescriptor(string:"focustab"),forKeyword:AEKeyword(keyASSubroutineName))
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string:tab.window),at:1); parameters.insert(NSAppleEventDescriptor(string:tab.id),at:2)
        call.setDescriptor(parameters,forKeyword:keyDirectObject)
        let (result,error) = execute(browser,pid:app.processIdentifier,focus:true,source:{ Self.focusHandler(browser) },call:call)
        return .init(error:error,selected:result?.booleanValue ?? false)
    }
    nonisolated static func focusScript(_ browser:BrowserID,tab:BrowserTabRecord) -> String {
        focusHandler(browser) + "\nreturn focusTab(\(literal(tab.window)),\(literal(tab.id)))\n"
    }
    nonisolated static func focusHandler(_ browser:BrowserID) -> String {
        let select = browser == .arc ? "select t" : "set active tab index of w to n"
        let privateCheck = browser == .arc ? "incognito of w is false" : "mode of w is \"normal\""
        return """
        on focusTab(windowID, tabID)
            with timeout of 2 seconds
                tell application id "\(browser.bundleID)"
                    set orderedWindows to {}
                    repeat with candidateWindow in windows
                        if (id of candidateWindow as text) is windowID then
                            set orderedWindows to {contents of candidateWindow} & orderedWindows
                        else
                            set end of orderedWindows to contents of candidateWindow
                        end if
                    end repeat
                    repeat with w in orderedWindows
                        if \(privateCheck) then
                            set n to 0
                            repeat with t in tabs of w
                                set n to n + 1
                                if (id of t as text) is tabID then
                                    \(select)
                                    set index of w to 1
                                    activate
                                    return ((id of active tab of w as text) is tabID) and (index of w is 1)
                                end if
                            end repeat
                        end if
                    end repeat
                    return false
                end tell
            end timeout
        end focusTab
        """
    }

}

/// One compiled script per browser process and kind. A script is checked out while it runs,
/// because an NSAppleScript instance must not execute on two threads at once; an overlapping
/// call compiles its own. A relaunched browser gets fresh compilations.
private final class CompiledScripts: @unchecked Sendable {
    private struct Key: Hashable { let browser:BrowserID; let focus:Bool }
    private let lock = NSLock()
    private var idle: [Key:(pid_t,NSAppleScript)] = [:]
    func take(_ browser:BrowserID,pid:pid_t,focus:Bool) -> NSAppleScript? {
        lock.lock(); defer { lock.unlock() }
        guard let (owner,script) = idle.removeValue(forKey:Key(browser:browser,focus:focus)), owner == pid else { return nil }
        return script
    }
    func give(_ script:NSAppleScript,_ browser:BrowserID,pid:pid_t,focus:Bool) {
        lock.lock(); idle[Key(browser:browser,focus:focus)] = (pid,script); lock.unlock()
    }
}

#if DEBUG
extension BrowserCatalogue {
    /// Isolated adapter fixtures: no bridge, browser discovery or Apple events.
    func seedForTesting(_ browser:BrowserID, tabs:[BrowserTabRecord]) {
        precondition(!observesSystem)
        connections[browser] = Connection(pid:0, tabs:tabs, healthy:true)
        permissionCache[browser] = noErr
        status[browser] = "Available"
        publish()
    }
    func permissionForTesting(_ result:OSStatus, browser:BrowserID) {
        precondition(!observesSystem)
        acceptPermission(result, for:browser)
    }
    func updateTabsForTesting(_ browser:BrowserID, tabs:[BrowserTabRecord]) {
        precondition(!observesSystem && connections[browser] != nil)
        connections[browser]?.tabs = tabs
        publish()
    }
    func activateBrowserForTesting(_ browser:BrowserID?) {
        precondition(!observesSystem)
        activateBrowser(browser)
    }
    func expectFocusForTesting(_ browser:BrowserID) {
        precondition(!observesSystem)
        expectedBrowser = browser
    }
    func tabForTesting(_ id:TargetID) -> BrowserTabRecord? {
        precondition(!observesSystem)
        return routes[id]?.1
    }
}
#endif
