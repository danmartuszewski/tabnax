import AppKit
import ApplicationServices
import TabnaxCore

private struct Discovery: Sendable {
    var windows: [WindowRecord]
    var error: AXError
    var complete: Bool
    var focused: TargetID? = nil
    /// Windows left out for having neither a standard subrole nor a title and a usable size.
    var skipped = 0
}
@MainActor final class WindowCatalogue {
    private final class ProcessState {
        let info: ProcessInfo
        let running: NSRunningApplication
        var observer: AXObserver?
        var registrations = Set<TargetID>()
        var geometryRegistrations = Set<TargetID>()
        var childAddresses: AddressBook
        var windows: [WindowRecord] = []
        var busy = false
        var dirty = false
        var forcePending = false
        var epoch: UInt64 = 0
        var failures = 0
        var retryAfter = Date.distantPast
        var missingNotifications = 0
        var skipped = 0
        init(_ running: NSRunningApplication, alphabet: String) {
            childAddresses = try! AddressBook(alphabet: alphabet)
            self.running = running
            info = ProcessInfo(token: UUID(), pid: running.processIdentifier,
                               name: running.localizedName ?? "Application", app: AXHandle(AXUIElementCreateApplication(running.processIdentifier)), launchDate: running.launchDate)
        }
    }
    private var processes: [pid_t: ProcessState] = [:]
    private let workers: OperationQueue = {
        let q = OperationQueue(); q.name = "Tabnax bounded discovery"; q.maxConcurrentOperationCount = 3
        q.qualityOfService = .utility; return q
    }()
    private let observerWorkers: OperationQueue = {
        let q = OperationQueue(); q.name = "Tabnax observer registration"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q
    }()
    private let publication = CataloguePublicationBatcher()
    private let recoveryRefresh = CatalogueRecoveryRefresh()
    private var pendingGeometryRefresh = false
    private lazy var titleReader: CatalogueTitleReader = {
        let reader = CatalogueTitleReader(workers: workers)
        reader.onRead = { [weak self] request, title in
            guard let self, enabled, let state = processes[request.pid], state.info.token == request.id.process,
                  let index = state.windows.firstIndex(where: { $0.id == request.id && CFEqual($0.handle.element, request.handle.element) }),
                  state.windows[index].title != title else { return }
            state.windows[index].title = title
            schedulePublication()
        }
        return reader
    }()
    private var notifications: [NSObjectProtocol] = []
    private var windowAddresses: AddressBook
    private var appAddresses: AddressBook
    private var revision: UInt64 = 0
    private var enabled = false
    private var mode: DisplayMode = .shore
    private var desktopSpotlightEnabled = false
    private var needsGeometry: Bool { mode.usesGeometry || desktopSpotlightEnabled }
    private var history = FocusHistory()
    private var visibleIDs = Set<TargetID>()
    private var geometryBusy = false
    private var geometryDirty = false
    private var observationGeneration: UInt64 = 0
    /// Windows whose move/resize notification has not been read back yet. A drag emits one
    /// notification per frame; they collapse into a single off-main read per flush.
    private var pendingBounds: [TargetID: (pid: pid_t, handle: AXHandle)] = [:]
    private var boundsFlushScheduled = false
    private var delivered = false
    private let includeProcess: (NSRunningApplication) -> Bool
    private(set) var snapshot = CatalogueSnapshot()
    private(set) var icons: [UUID: NSImage] = [:]
    private(set) var notificationCounts: [String: Int] = [:]
    private(set) var status = "Accessibility is required to list windows."
    /// Tabs currently excluded by the browser-scope preference (still holding an address so
    /// their label survives if the preference is toggled back — see `BrowserCatalogue.excludedCount`).
    /// The owner sets this before/alongside merging browser tabs into a snapshot, so an
    /// otherwise-confusing "address pool full" status can explain why.
    var excludedTabCount = 0 { didSet { if oldValue != excludedTabCount { publish() } } }
    var onChange: ((CatalogueSnapshot, [TargetID: FocusTarget]) -> Void)?
    var onPermissionLost: (() -> Void)?
    var onExternalActivation: ((pid_t) -> Void)?
    var focusObservationToken: (() -> UInt64?)?
    func recordObservedFocus(_ id: TargetID) {
        guard id.window != nil, processes.values.contains(where: { $0.windows.contains { $0.id == id && $0.available } }) else { return }
        history.observe(id); publish()
    }
    func setMode(_ value: DisplayMode) {
        guard mode != value else { return }
        mode = value; visibleIDs.removeAll()
        // Geometry registrations are not mode-scoped: schedule() always tracks focused-window
        // bounds for placement, so unregistering them here would just be undone by the refresh()
        // below (which re-adds them since geometry stays true regardless of mode).
        for state in processes.values { state.epoch &+= 1 }
        refresh(); publish()
    }
    func setDesktopSpotlightEnabled(_ value: Bool) {
        guard desktopSpotlightEnabled != value else { return }
        desktopSpotlightEnabled = value
        if needsGeometry { refreshGeometry() } else { visibleIDs.removeAll(); publish() }
    }
    func refreshAfterWindowPreview() {
        // Raising changes occlusion without necessarily changing focus or AX bounds.
        observationGeneration &+= 1
        visibleIDs.removeAll()
        refreshGeometry(); publish()
    }
    func displaysChanged() {
        guard enabled else { return }
        // Reject work started in the old coordinate system, but keep process/window
        // identities and their shortcuts while macOS moves windows between displays.
        observationGeneration &+= 1
        visibleIDs.removeAll()
        pendingBounds.removeAll()
        for state in processes.values {
            state.epoch &+= 1
            state.retryAfter = .distantPast
        }
        refresh(force: true)
        refreshGeometry(); publish()
        // Wake and display notifications precede completion of WindowServer/AX recovery.
        // Refresh again even if the first pass succeeded with a temporarily incomplete list.
        recoveryRefresh.restart { [weak self] in self?.refresh(force: true) }
    }
    init(alphabet: String, includeProcess: @escaping (NSRunningApplication) -> Bool = { _ in true }) {
        self.includeProcess = includeProcess
        windowAddresses = try! AddressBook(alphabet: alphabet)
        appAddresses = try! AddressBook(alphabet: alphabet)
    }
    func start() {
        guard AXIsProcessTrusted() else { return }
        if enabled { refresh(); return }
        enabled = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                let name = note.name
                MainActor.assumeIsolated { self?.workspaceChanged(name: name, pid: pid) }
            })
        }
        refresh()
    }
    func stop() {
        enabled = false; workers.cancelAllOperations(); observerWorkers.cancelAllOperations()
        titleReader.reset(); publication.cancel(); recoveryRefresh.cancel(); pendingGeometryRefresh = false
        notifications.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; notifications.removeAll()
        for state in processes.values { removeObserver(state) }
        processes.removeAll(); icons.removeAll(); publish()
    }
    func resetAddresses(alphabet: String) {
        windowAddresses = try! AddressBook(alphabet: alphabet); appAddresses = try! AddressBook(alphabet: alphabet)
        for state in processes.values { state.childAddresses = try! AddressBook(alphabet: alphabet) }; publish()
    }
    /// Opening the switcher, Refresh and a failed focus are the user asking for current data, so
    /// they bypass the failure backoff that only exists to keep event-driven retries quiet.
    func refresh(force: Bool = true) {
        guard enabled else { return }
        let removed = reconcileProcesses()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let recent = Set(([history.current].compactMap { $0 } + history.recent).map(\.process))
        let identities = processes.mapValues { $0.info.token }
        for pid in Self.refreshOrder(processes: identities, frontmostPID: frontmostPID, history: history) {
            schedule(pid, force: force, priority: recent.contains(identities[pid]!) ? .high : .normal, isFrontmost: pid == frontmostPID)
        }
        if removed { publish() }
    }
    /// Focused and recently used apps become available first on a cold catalogue. PID order
    /// is only a deterministic fallback, never a reason to delay the foreground app.
    nonisolated static func refreshOrder(processes: [pid_t: UUID], frontmostPID: pid_t?, history: FocusHistory) -> [pid_t] {
        let byToken = Dictionary(uniqueKeysWithValues: processes.map { ($0.value, $0.key) })
        let recent = ([history.current].compactMap { $0 } + history.recent).compactMap { byToken[$0.process] }
        var seen = Set<pid_t>()
        return ([frontmostPID].compactMap { $0 } + recent + processes.keys.sorted()).filter {
            processes[$0] != nil && seen.insert($0).inserted
        }
    }
    private func workspaceChanged(name: Notification.Name, pid: pid_t?) {
        if name == NSWorkspace.didWakeNotification || name == NSWorkspace.screensDidWakeNotification {
            displaysChanged(); return
        }
        if name == NSWorkspace.activeSpaceDidChangeNotification { observationGeneration &+= 1; visibleIDs.removeAll() }
        if name == NSWorkspace.didActivateApplicationNotification, let pid {
            // Activation fires on nearly every app switch; the window set itself
            // hasn't necessarily changed, so skip the full runningApplications
            // rebuild here and just re-discover the activated process's windows.
            observationGeneration &+= 1; onExternalActivation?(pid)
            schedule(pid); publish(); return
        }
        // A Space change reshuffles which windows every app lists; the rest stay event-paced.
        if let pid { reconcileProcesses(); schedule(pid) } else { refresh(force: name == NSWorkspace.activeSpaceDidChangeNotification) }
        publish()
    }
    @discardableResult private func reconcileProcesses() -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter {
            // Tabnax itself stays an accessory-policy app (see AppDelegate) even while its
            // Settings window is open, so it never satisfies the .regular check other apps
            // rely on. Let it through explicitly so its own window is treated like any other.
            ($0.activationPolicy == .regular || $0.processIdentifier == ProcessInfoSelf.pid) && includeProcess($0) && !$0.isTerminated
        }
        let pids = Set(running.map(\.processIdentifier))
        var removed = false
        for (pid, state) in processes where !pids.contains(pid) || state.running.isTerminated {
            state.windows.forEach { titleReader.invalidate($0.id) }
            removeObserver(state); icons[state.info.token] = nil; processes[pid] = nil
            removed = true
        }
        for app in running.prefix(128) where processes[app.processIdentifier] == nil {
            let state = ProcessState(app, alphabet: windowAddresses.alphabet); processes[app.processIdentifier] = state
            // Fixed 32-point raster bounds the icon cache to about 2 MiB / 128 apps.
            if let source = app.icon {
                let image = NSImage(size: NSSize(width: 32, height: 32))
                image.lockFocus(); source.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32)); image.unlockFocus()
                icons[state.info.token] = image
            }
            installObserver(state)
        }
        return removed
    }
    private func installObserver(_ state: ProcessState) {
        var observer: AXObserver?
        let result = AXObserverCreate(state.info.pid, { _, element, notification, context in
            guard let context else { return }
            // This source is installed only on the main run loop.
            MainActor.assumeIsolated {
                Unmanaged<WindowCatalogue>.fromOpaque(context).takeUnretainedValue().axChanged(element, notification as String)
            }
        }, &observer)
        guard result == .success, let observer else { state.missingNotifications += 1; return }
        state.observer = observer
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        // Registration performs IPC, so it runs on the discovery queue too.
        register(state, handle: state.info.app, names: [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification])
    }
    private func register(_ state: ProcessState, handle: AXHandle, names: [String]) {
        guard let observer = state.observer else { return }
        let box = ObserverReference(observer)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let pointer = UInt(bitPattern: context)
        let token = state.info.token; let pid = state.info.pid
        observerWorkers.addOperation { [weak self] in
            var failures = 0
            for name in names {
                let result = AXObserverAddNotification(box.observer, handle.element, name as CFString, UnsafeMutableRawPointer(bitPattern: pointer))
                if result != .success && result != .notificationAlreadyRegistered { failures += 1 }
            }
            let count = failures
            Task { @MainActor [weak self] in
                guard let state = self?.processes[pid], state.info.token == token else { return }
                state.missingNotifications += count
            }
        }
    }
    private func removeObserver(_ state: ProcessState) {
        if let observer = state.observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        state.observer = nil
    }
    private func axChanged(_ element: AXUIElement, _ name: String) {
        notificationCounts[name, default: 0] += 1
        if name == kAXFocusedWindowChangedNotification || name == kAXMainWindowChangedNotification { observationGeneration &+= 1 }
        var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
        guard let state = processes[pid] else { return }
        if name == kAXUIElementDestroyedNotification {
            // Structural: the window set changed, so fall through to a full re-discovery.
            let removed = state.windows.filter { CFEqual($0.handle.element, element) }.map(\.id)
            removed.forEach { titleReader.invalidate($0) }
            state.registrations.subtract(removed); state.geometryRegistrations.subtract(removed)
            state.windows.removeAll { CFEqual($0.handle.element, element) }
            state.epoch &+= 1; publish()
            schedule(pid); return
        }
        // Geometry/title/minimized-state notifications identify a single already-tracked
        // window (the AXUIElement matches one of state.windows via CFEqual), so update that
        // record in place rather than re-enumerating every window of the process. If the
        // element can't be matched to a tracked window (e.g. it arrived before discovery
        // registered it), fall back to the full schedule(pid) path rather than risk dropping
        // the update.
        if name == kAXMovedNotification || name == kAXResizedNotification {
            guard let window = state.windows.first(where: { CFEqual($0.handle.element, element) }) else { schedule(pid); return }
            pendingBounds[window.id] = (pid, window.handle); scheduleBoundsFlush(); return
        }
        if name == kAXTitleChangedNotification {
            guard let window = state.windows.first(where: { CFEqual($0.handle.element, element) }) else { schedule(pid); return }
            titleReader.enqueue(id: window.id, pid: pid, handle: window.handle)
            return
        }
        if name == kAXWindowMiniaturizedNotification || name == kAXWindowDeminiaturizedNotification {
            guard let index = state.windows.firstIndex(where: { CFEqual($0.handle.element, element) }) else { schedule(pid); return }
            state.windows[index].minimized = name == kAXWindowMiniaturizedNotification
            refreshGeometry(); publish(); return
        }
        // kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
        // kAXMainWindowChangedNotification, or anything else unrecognized: the
        // window set (or focus) may have changed, so re-discover fully.
        schedule(pid)
    }
    /// Started by a notification and never re-armed on its own, so an idle catalogue stays idle.
    /// Anything arriving during the read lands in the next flush, which keeps the final
    /// resting bounds of a drag from being lost.
    private func scheduleBoundsFlush() {
        guard !boundsFlushScheduled else { return }
        boundsFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self] in
            MainActor.assumeIsolated { self?.flushBounds() }
        }
    }
    private func flushBounds() {
        boundsFlushScheduled = false
        let pending = pendingBounds.map { (id: $0.key, pid: $0.value.pid, handle: $0.value.handle) }
        pendingBounds.removeAll()
        guard enabled, !pending.isEmpty else { return }
        let generation = observationGeneration
        // The reads are IPC to the dragged app, which may be busy; keep them off the main thread.
        workers.addOperation { [weak self] in
            let measured = pending.compactMap { entry -> (TargetID, pid_t, CGRect)? in
                let (posError, posValue) = axValue(entry.handle.element, kAXPositionAttribute)
                let (sizeError, sizeValue) = axValue(entry.handle.element, kAXSizeAttribute)
                guard posError == .success, let posValue, sizeError == .success, let sizeValue,
                      let point = decodePoint(posValue), let size = decodeSize(sizeValue), size.width > 0, size.height > 0 else { return nil }
                return (entry.id, entry.pid, CGRect(origin: point, size: size))
            }
            Task { @MainActor [weak self] in
                guard let self, enabled, generation == observationGeneration else { return }
                var changed = false
                for (id, pid, bounds) in measured {
                    guard let state = processes[pid], let index = state.windows.firstIndex(where: { $0.id == id }),
                          state.windows[index].bounds != bounds else { continue }
                    state.windows[index].bounds = bounds; changed = true
                }
                if changed { refreshGeometry(); publish() }
            }
        }
    }
    nonisolated static func acceptsObservation(started: UInt64?, current: UInt64?) -> Bool {
        started != nil && started == current
    }
    private func schedule(_ pid: pid_t, force: Bool = false, priority: Operation.QueuePriority = .normal, isFrontmost: Bool? = nil) {
        guard enabled, let state = processes[pid] else { return }
        if state.busy { state.dirty = true; state.forcePending = state.forcePending || force; return }
        guard force || Date() >= state.retryAfter else { return } // Event-triggered backoff; no idle timer.
        state.busy = true; state.dirty = false; state.forcePending = false
        let info = state.info, old = state.windows, epoch = state.epoch
        let geometry = true // Placement needs the observed focused window on every mode.
        let generation = observationGeneration
        let titleVersions = titleReader.versions
        let wasFront = isFrontmost ?? (NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)
        let focusToken = focusObservationToken?() ?? (focusObservationToken == nil ? 0 : nil)
        let operation = BlockOperation { [weak self] in
            let result = Self.discover(info, old: old, geometry: geometry, observeFocus: wasFront)
            Task { @MainActor [weak self] in
                guard let self, let state = processes[pid], state.info.token == info.token, enabled else { return }
                state.busy = false
                guard state.epoch == epoch else { schedule(pid, force: state.forcePending); return }
                let previousWindows = state.windows
                state.windows = Self.preservingNewerTitles(result.windows, current: previousWindows,
                    startedVersions: titleVersions, currentVersions: titleReader.versions)
                if pid == ProcessInfoSelf.pid {
                    // Closing our own Settings window only orders it out, so AX never reports it
                    // destroyed and it would linger here as an unavailable row. AppKit knows.
                    let open = Set(NSApp.windows.filter { !($0 is NSPanel) && ($0.isVisible || $0.isMiniaturized) }.map(\.title))
                    state.windows.removeAll { !open.contains($0.title) }
                }
                state.registrations.formIntersection(Set(state.windows.map(\.id)))
                state.geometryRegistrations.formIntersection(Set(state.windows.map(\.id)))
                let liveIDs = Set(state.windows.map(\.id))
                for window in previousWindows where !liveIDs.contains(window.id) { titleReader.invalidate(window.id) }
                if result.error != .success {
                    state.failures += 1
                    // A busy app answers again soon; anything else is unlikely to heal quickly.
                    let ceiling: Double = result.error == .cannotComplete ? 8 : 30
                    state.retryAfter = Date().addingTimeInterval(min(ceiling, pow(2, Double(min(5, state.failures)))))
                    Trace.log.notice("AX discovery error \(result.error.rawValue, privacy: .public)")
                } else { state.failures = 0; state.retryAfter = .distantPast }
                if result.skipped != state.skipped {
                    state.skipped = result.skipped
                    Trace.log.info("Skipped \(result.skipped, privacy: .public) nonstandard windows in \(info.name)")
                }
                for window in state.windows where !state.registrations.contains(window.id) {
                    state.registrations.insert(window.id)
                    register(state, handle: window.handle, names: [kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
                        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification])
                }
                if geometry {
                    for window in state.windows where !state.geometryRegistrations.contains(window.id) {
                        state.geometryRegistrations.insert(window.id)
                        register(state, handle: window.handle, names: [kAXMovedNotification, kAXResizedNotification])
                    }
                }
                if wasFront, generation == observationGeneration,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                   Self.acceptsObservation(started: focusToken, current: focusObservationToken?() ?? (focusObservationToken == nil ? 0 : nil)), let focused = result.focused { history.observe(focused) }
                if result.error == .apiDisabled && !AXIsProcessTrusted() { stop(); onPermissionLost?(); return }
                let availableIDs = Set(state.windows.filter(\.available).map(\.id))
                pendingGeometryRefresh = pendingGeometryRefresh || geometry
                // Retiring a focus target must not wait for a display batch. Ordinary metadata
                // and discovery completions can share one catalogue rebuild.
                if previousWindows.contains(where: { $0.available && !availableIDs.contains($0.id) || !liveIDs.contains($0.id) }) { publish() }
                else { schedulePublication() }
                if state.dirty { schedule(pid, force: state.forcePending) }
            }
        }
        operation.queuePriority = wasFront ? .veryHigh : priority
        workers.addOperation(operation)
    }
    nonisolated static func preservingNewerTitles(_ discovered: [WindowRecord], current: [WindowRecord],
                                                  startedVersions: [TargetID: UInt64], currentVersions: [TargetID: UInt64]) -> [WindowRecord] {
        guard startedVersions != currentVersions else { return discovered }
        let titles = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.title) })
        return discovered.map { window in
            guard currentVersions[window.id] != startedVersions[window.id], let title = titles[window.id] else { return window }
            var updated = window; updated.title = title; return updated
        }
    }
    nonisolated private static func discover(_ process: ProcessInfo, old: [WindowRecord], geometry: Bool, observeFocus: Bool) -> Discovery {
        let started = ContinuousClock.now
        let (error, value) = axValue(process.app.element, kAXWindowsAttribute)
        guard error == .success, let elements = value as? [AXUIElement] else {
            // A busy app that missed the short timeout has not lost its windows. Keep what was
            // known, so they stay selectable; only a definite failure marks them unavailable.
            if error == .cannotComplete { return Discovery(windows: old, error: error, complete: false) }
            return Discovery(windows: old.map { var r = $0; r.available = false; return r }, error: error, complete: false)
        }
        var records = old.map { var r = $0; r.available = false; return r }
        var complete = elements.count <= 64
        var readError = AXError.success
        var skipped = 0
        var listed = Set<TargetID>() // Known windows this pass actually got to.
        func restore(_ record: WindowRecord?) {
            guard let record, let index = records.firstIndex(where: { $0.id == record.id }) else { return }
            records[index] = record
        }
        for element in elements.prefix(64) {
            if started.duration(to: .now) > .milliseconds(300) { complete = false; break }
            let existing = old.first { CFEqual($0.handle.element, element) }
            if let existing { listed.insert(existing.id) }
            let handle = existing?.handle ?? AXHandle(element)
            var values: CFArray?
            let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXMinimizedAttribute] + (geometry ? [kAXPositionAttribute, kAXSizeAttribute] : [])
            let attributes = names as CFArray
            let interval = Trace.signposter.beginInterval("axCall")
            let result = AXUIElementCopyMultipleAttributeValues(handle.element, attributes, [], &values)
            Trace.signposter.endInterval("axCall", interval)
            guard result == .success, let list = values as? [Any], list.count == names.count else {
                complete = false; if result != .success { readError = result }
                if result == .cannotComplete { restore(existing) } // Listed, just slow to answer.
                continue
            }
            guard (list[0] as? String) == kAXWindowRole else { continue }
            let subrole = list[1] as? String ?? ""
            if ![kAXStandardWindowSubrole, kAXDialogSubrole, kAXSystemDialogSubrole].contains(subrole) {
                // Some toolkits (Java, games, a few cross-platform frameworks) never adopt a
                // standard subrole. Admit their real windows by evidence: no subrole at all, a
                // title, and a usable size. Palettes, popovers and tooltips stay out.
                let titled = !((list[2] as? String) ?? "").isEmpty
                let size = geometry ? decodeSize(list[5]) : nil
                guard subrole.isEmpty || subrole == kAXUnknownSubrole, titled,
                      let size, size.width >= 200, size.height >= 120 else { skipped += 1; continue }
            }
            let id = existing?.id ?? TargetID(process: process.token, window: UUID())
            var record = WindowRecord(id: id, handle: handle, title: (list[2] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(1024)) } ?? "Untitled window",
                                      minimized: list[3] as? Bool ?? false, available: true)
            if geometry, let point = decodePoint(list[4]), let size = decodeSize(list[5]), size.width > 0, size.height > 0 {
                record.bounds = CGRect(origin: point, size: size)
            }
            if let index = records.firstIndex(where: { $0.id == id }) { records[index] = record }
            else if records.count < 128 { records.append(record) }
        }
        // A successful list omission is not closure (e.g. another Space). Probe
        // only the omitted, previously known handle. An explicit invalid-element
        // result is authoritative; timeout/unsupported/success retain it as stale.
        // A handle that still answers belongs to a window macOS is simply not listing here;
        // it stays selectable and the focus request makes the trip to its Space.
        if complete {
            var invalid = Set<TargetID>()
            for index in records.indices where !records[index].available && !listed.contains(records[index].id) {
                if started.duration(to: .now) > .milliseconds(300) { restore(old.first { $0.id == records[index].id }); continue }
                let (probe, _) = axValue(records[index].handle.element, kAXRoleAttribute)
                switch probe {
                case .success: records[index].available = true; records[index].elsewhere = true
                case .invalidUIElement: invalid.insert(records[index].id)
                case .cannotComplete: restore(old.first { $0.id == records[index].id })
                default: break
                }
            }
            records.removeAll { invalid.contains($0.id) }
        } else {
            // An incomplete pass says nothing about the windows it never reached.
            for record in old where !listed.contains(record.id) { restore(record) }
        }
        // A missing window is stale, never assumed closed from an incomplete list
        // (Spaces and some apps omit windows). Explicit destruction/termination retires it.
        var focused: TargetID?
        if observeFocus {
            let (_, raw) = axValue(process.app.element, kAXFocusedWindowAttribute)
            if let element = axElement(raw) { focused = records.first { $0.available && CFEqual($0.handle.element, element) }?.id }
        }
        return Discovery(windows: records, error: readError, complete: complete, focused: focused, skipped: skipped)
    }
    private func refreshGeometry() {
        guard enabled, needsGeometry else { return }
        if geometryBusy { geometryDirty = true; return }
        geometryBusy = true; geometryDirty = false
        let generation = observationGeneration
        let notificationCenterPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").map(\.processIdentifier))
        let screens = NSScreen.screens.map(\.frame)
        let primaryTop = screens.first?.maxY ?? 0
        let displayBounds = screens.map { CGRect(x: $0.minX, y: primaryTop-$0.maxY, width: $0.width, height: $0.height) }
        let candidates = processes.values.flatMap { state in state.windows.compactMap { window -> GeometryCandidate? in
            guard let bounds = window.bounds, window.available, !window.elsewhere, !window.minimized, !state.running.isHidden else { return nil }
            return GeometryCandidate(id: window.id, pid: state.info.pid, bounds: bounds)
        } }
        workers.addOperation { [weak self] in
            let visible = visibleGeometry(candidates, notificationCenterPIDs: notificationCenterPIDs, displayBounds: displayBounds)
            Task { @MainActor [weak self] in
                guard let self else { return }; geometryBusy = false
                guard enabled, needsGeometry else { return }
                // A result from the previous Space/app stack must not restore a
                // stale spotlight after a newer activation cleared visibility.
                guard generation == observationGeneration else { refreshGeometry(); return }
                visibleIDs = Set(candidates.filter { candidate in
                    visible.contains(candidate.id) && processes[candidate.pid]?.windows.contains { $0.id == candidate.id && $0.bounds == candidate.bounds } == true
                }.map(\.id)); publish()
                if geometryDirty { refreshGeometry() }
            }
        }
    }
    private func publish() {
        publication.cancel()
        if pendingGeometryRefresh { pendingGeometryRefresh = false; refreshGeometry() }
        var windows: [Target] = [], apps: [Target] = [], registry: [TargetID: FocusTarget] = [:]
        var exhausted = false
        history.retain(live: Set(processes.values.flatMap { $0.windows.map(\.id) }))
        for state in processes.values.sorted(by: { $0.info.name.localizedStandardCompare($1.info.name) == .orderedAscending }) {
            let appID = TargetID(process: state.info.token)
            do {
                let address = (try? appAddresses.address(for: appID)) ?? ""
                apps.append(Target(id: appID, app: state.info.name, title: state.info.name, address: address, hidden: state.running.isHidden, bundleID: state.running.bundleIdentifier ?? ""))
                registry[appID] = FocusTarget(process: state.info, window: nil)
            }
            let appCode = (try? appAddresses.address(for: appID)) ?? ""
            for window in state.windows {
                let address = (try? windowAddresses.address(for: window.id)) ?? ""
                if address.isEmpty { exhausted = true }
                windows.append(Target(id: window.id, app: state.info.name, title: window.title, address: address,
                                      minimized: window.minimized, hidden: state.running.isHidden, available: window.available,
                                      foldAddress: appCode.isEmpty ? "" : ((try? state.childAddresses.address(for: window.id)).map { appCode + $0 } ?? ""),
                                      bounds: window.bounds, onScreen: visibleIDs.contains(window.id), elsewhere: window.elsewhere))
                if window.available { registry[window.id] = FocusTarget(process: state.info, window: window) }
            }
        }
        for state in processes.values { state.childAddresses.retain(live: Set(state.windows.map(\.id))) }
        windowAddresses.retain(live: Set(windows.map(\.id))); appAddresses.retain(live: Set(apps.map(\.id)))
        // Addresses determine the index, not focus recency or changing titles.
        var rank: [Character: Int] = [:]
        for (index, character) in windowAddresses.alphabet.enumerated() { rank[character] = index }
        windows.sort { a, b in
            if a.address.count != b.address.count { return a.address.count < b.address.count }
            return a.address.map { rank[$0]! }.lexicographicallyPrecedes(b.address.map { rank[$0]! })
        }
        let allocated = windowAddresses.allocated.union(appAddresses.allocated)
        // Most triggers (activation, on-open refresh of every process, geometry passes) end up
        // describing the same windows. Handles are reused per window id, so equal targets mean an
        // equivalent registry too, and downstream relabelling/rendering can be skipped entirely.
        let unchanged = delivered && snapshot.windows == windows && snapshot.apps == apps && snapshot.history == history
            && snapshot.allocated == allocated && snapshot.alphabet == windowAddresses.alphabet
        if !unchanged {
            revision &+= 1
            snapshot = CatalogueSnapshot(revision: revision, windows: windows, apps: apps, alphabet: windowAddresses.alphabet,
                allocated: allocated, history: history)
        }
        let stale = windows.filter { !$0.available }.count
        status = exhausted ? (excludedTabCount > 0
                ? "Address session is full (\(excludedTabCount) excluded browser tab\(excludedTabCount == 1 ? "" : "s") holding addresses). Reset addresses in settings to include new windows."
                : "Address session is full. Reset addresses in settings to include new windows.") :
            (stale == 0 ? "Addresses stay fixed until you reset them" : "\(stale) unavailable · Refresh from the menu")
        guard !unchanged else { return }
        delivered = true
        onChange?(snapshot, registry)
    }
    private func schedulePublication() {
        publication.schedule { [weak self] in
            guard let self, enabled else { return }
            publish()
        }
    }
}

/// A finite recovery burst, restarted by the latest wake/display event. No idle polling.
/// Generation checks also invalidate callbacks already enqueued when stopping the catalogue.
@MainActor final class CatalogueRecoveryRefresh {
    typealias Enqueue = (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let enqueue: Enqueue
    private var generation: UInt64 = 0

    init(enqueue: @escaping Enqueue = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }) {
        self.enqueue = enqueue
    }
    func restart(_ refresh: @escaping @MainActor () -> Void) {
        generation &+= 1
        let expected = generation
        for delay in [0.5, 1.5, 3.0, 6.0] {
            enqueue(delay) { [weak self] in
                guard let self, generation == expected else { return }
                refresh()
            }
        }
    }
    func cancel() { generation &+= 1 }
}

/// A bounded delay groups discovery completions before the expensive full-snapshot rebuild.
/// Cancelling also invalidates an already-enqueued callback, so an immediate liveness update
/// or a stop/restart cannot be followed by an obsolete publication.
@MainActor final class CataloguePublicationBatcher {
    private var generation: UInt64 = 0
    private var scheduled = false

    func schedule(_ action: @escaping @MainActor () -> Void) {
        guard !scheduled else { return }
        scheduled = true; generation &+= 1
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.scheduled, self.generation == expected else { return }
                self.scheduled = false
                action()
            }
        }
    }
    func cancel() { scheduled = false; generation &+= 1 }
}

/// AX title IPC never runs on the notification/main thread. Notifications that arrive during
/// a read replace the pending request and invalidate the old result; only the latest title
/// can be applied. Versions also let a full discovery retain a title updated during its read.
@MainActor final class CatalogueTitleReader {
    struct Request: Sendable {
        let id: TargetID
        let pid: pid_t
        let handle: AXHandle
        let generation: UInt64
    }
    private let workers: OperationQueue
    private let read: @Sendable (AXHandle) -> String?
    private var pending: [TargetID: Request] = [:]
    private var requests: [TargetID: UInt64] = [:]
    private var counter: UInt64 = 0
    private var lifetime: UInt64 = 0
    private var busy = false
    private var scheduled = false
    private(set) var versions: [TargetID: UInt64] = [:]
    var onRead: ((Request, String) -> Void)?

    init(workers: OperationQueue, read: @escaping @Sendable (AXHandle) -> String? = CatalogueTitleReader.readTitle) {
        self.workers = workers; self.read = read
    }
    func enqueue(id: TargetID, pid: pid_t, handle: AXHandle) {
        counter &+= 1
        requests[id] = counter; versions[id] = counter
        pending[id] = Request(id: id, pid: pid, handle: handle, generation: counter)
        scheduleFlush()
    }
    func invalidate(_ id: TargetID) {
        pending[id] = nil; requests[id] = nil; versions[id] = nil
    }
    func reset() {
        lifetime &+= 1
        pending.removeAll(); requests.removeAll(); versions.removeAll()
        busy = false; scheduled = false
    }
    private func scheduleFlush() {
        guard !scheduled, !busy, !pending.isEmpty else { return }
        scheduled = true
        let expected = lifetime
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.lifetime == expected else { return }
                self.scheduled = false; self.flush()
            }
        }
    }
    private func flush() {
        guard !busy, !pending.isEmpty else { return }
        let batch = Array(pending.values), expected = lifetime, read = read
        pending.removeAll(); busy = true
        workers.addOperation { [weak self] in
            let results = batch.map { ($0, read($0.handle)) }
            Task { @MainActor [weak self] in
                guard let self, lifetime == expected else { return }
                busy = false
                for (request, title) in results {
                    guard lifetime == expected, requests[request.id] == request.generation, let title else { continue }
                    counter &+= 1; versions[request.id] = counter
                    onRead?(request, title)
                }
                scheduleFlush()
            }
        }
    }
    nonisolated private static func readTitle(_ handle: AXHandle) -> String? {
        let (error, value) = axValue(handle.element, kAXTitleAttribute)
        guard error == .success else { return nil }
        return (value as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(1024)) } ?? "Untitled window"
    }
}

private enum ProcessInfoSelf { static let pid = Foundation.ProcessInfo.processInfo.processIdentifier }
private final class ObserverReference: @unchecked Sendable {
    let observer: AXObserver
    init(_ observer: AXObserver) { self.observer = observer }
}

private func decodePoint(_ value: Any) -> CGPoint? {
    let ref = value as CFTypeRef
    guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
    let ax = unsafeDowncast(ref, to: AXValue.self); var point = CGPoint.zero
    return AXValueGetValue(ax, .cgPoint, &point) ? point : nil
}
private func decodeSize(_ value: Any) -> CGSize? {
    let ref = value as CFTypeRef
    guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
    let ax = unsafeDowncast(ref, to: AXValue.self); var size = CGSize.zero
    return AXValueGetValue(ax, .cgSize, &size) ? size : nil
}
struct GeometryCandidate: Sendable { let id: TargetID; let pid: pid_t; let bounds: CGRect }
private func visibleGeometry(_ candidates: [GeometryCandidate], notificationCenterPIDs: Set<pid_t>, displayBounds: [CGRect]) -> Set<TargetID> {
    guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return visibleGeometry(candidates, rows: rows, overlayPID: getpid(),
                           notificationCenterPIDs: notificationCenterPIDs, displayBounds: displayBounds)
}

/// Window-server rows are front to back. Exclude our floating switcher surfaces
/// from both matching and occlusion, while retaining normal Settings windows.
func visibleGeometry(_ candidates: [GeometryCandidate], rows: [[String: Any]], overlayPID: pid_t,
                     notificationCenterPIDs: Set<pid_t> = [], displayBounds: [CGRect] = []) -> Set<TargetID> {
    func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) < 2 && abs(a.minY-b.minY) < 2 && abs(a.width-b.width) < 2 && abs(a.height-b.height) < 2
    }
    let windows: [(pid_t, CGRect)] = rows.prefix(512).compactMap { row in
        guard let pid = row[kCGWindowOwnerPID as String] as? Int32,
              let raw = row[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: raw), bounds.width > 1, bounds.height > 1,
              (row[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
        let layer = row[kCGWindowLayer as String] as? Int ?? 0
        guard pid != overlayPID || layer == 0 else { return nil }
        // Notification Center keeps a transparent, display-sized desktop container
        // with window alpha 1. Its bounding box does not mean the desktop is covered.
        // Match its process identity and display bounds; smaller banners and panels,
        // normal app windows, and other apps' floating windows remain obstructions.
        if layer != 0, notificationCenterPIDs.contains(pid), displayBounds.contains(where: { near($0, bounds) }) { return nil }
        return (pid, bounds)
    }
    var visible = Set<TargetID>()
    for candidate in candidates {
        // Equal geometry in the same process is ambiguous; never guess the AX/CG pairing.
        guard candidates.filter({ $0.pid == candidate.pid && near($0.bounds, candidate.bounds) }).count == 1 else { continue }
        let indices = windows.indices.filter { windows[$0].0 == candidate.pid && near(windows[$0].1, candidate.bounds) }
        guard indices.count == 1, let index = indices.first else { continue }
        let titleRegion = CGRect(x: candidate.bounds.minX + 8, y: candidate.bounds.minY + 4,
                                 width: min(300, candidate.bounds.width - 16), height: 28)
        guard !windows.prefix(index).contains(where: { $0.1.intersects(titleRegion) }) else { continue }
        visible.insert(candidate.id)
    }
    return visible
}
