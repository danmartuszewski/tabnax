import AppKit
import ApplicationServices
import Carbon
import TabnaxCore

/// Mutable routing state is confined to the event-tap run loop. The callback
/// accepts the final key and submits focus before scheduling any presentation.
final class InputRouter: @unchecked Sendable {
    private struct ActivationTrace: Sendable {
        let session: UInt64
        let source: String
        let recognizedAt: CFTimeInterval
        var publishedAt: CFTimeInterval?
    }
    private struct Bridge {
        var loop: CFRunLoop?
        var latest = SelectionState()
        var presentationPending = false
        var activationTrace: ActivationTrace?
        var running = false
        var snapshot = CatalogueSnapshot()
        var snapshotPending = false
        var stopRequested = false
        var mode: DisplayMode = .shore
        var settings = SettingsDocument()
        var searchMemory: SearchMemory?
        var surfaces: [CGRect] = []
        var suspended = false
        var menuSession: UInt64?
        var menuReady = false
        var menuDisarmSession: UInt64?
        var searchFocusSession: UInt64?
        var searchHandoffSession: UInt64?
        var searchEvents: [CGEvent] = []
        var shortcutRecorder: (@Sendable (Shortcut) -> Void)?
    }
    private let bridge = Locked(Bridge())
    var shortcutExceptionGate = ShortcutExceptionGate()
    private var passedKeys = KeyOwnership()
    private var state = SelectionState()
    private var ownership = KeyOwnership()
    private var earlySearchKeys = KeyOwnership()
    private var heldActivation = false
    /// True after opening with Command–Tab or cycling with the activation modifiers down.
    /// Typing, searching or letting the modifiers go clears it.
    private var cycledWhileHeld = false
    /// True until the activation modifiers are first let go after opening. While it holds,
    /// pressing the trigger again cycles instead of toggling the switcher closed.
    private var modifiersHeldSinceOpen = false
    private var optionWasDown = false
    private var restoredWhileHeld: (id: TargetID, highlight: NavigationAction?)?
    private var previewedDuringSession = false
    private var actionPreviewSuspended = false
    /// Events captured before the first search frame are delivered to its native editor,
    /// never reconstructed as strings or reposted to another application.
    var onSearchInput: (@MainActor @Sendable (CGEvent, UInt64) -> Void)?
    var onSearchFocus: (@MainActor @Sendable (UInt64) -> Void)?
    var onSearchMemory: (@MainActor @Sendable (SearchMemory) -> Void)?
    var onActionMenu: (@MainActor @Sendable (SelectionState) -> Void)?
    var onMenuShortcut: (@MainActor @Sendable (SwitcherAction, UInt64) -> Void)?
    private var tapLosses: [CFAbsoluteTime] = []
    private var lastTapActivation: CFAbsoluteTime = 0
    private var pendingActivationTrace: ActivationTrace?
    private var tap: CFMachPort?
    private var thread: Thread?
    private let onState: @MainActor @Sendable (SelectionState) -> Void
    private let onSelect: @Sendable (TargetID) -> Void
    private let onCancel: @Sendable () -> Void
    private let onPassiveKey: @Sendable () -> Void
    private let onPreview: @Sendable (TargetID?) -> Void
    private let onRestorePreview: @Sendable (TargetID) -> Void
    private let onAction: @Sendable (SwitcherAction, TargetID) -> Void
    private let onHealth: @MainActor @Sendable (String) -> Void
    init(onState: @escaping @MainActor @Sendable (SelectionState) -> Void,
         onSelect: @escaping @Sendable (TargetID) -> Void,
         onCancel: @escaping @Sendable () -> Void,
         onPassiveKey: @escaping @Sendable () -> Void = {},
         onPreview: @escaping @Sendable (TargetID?) -> Void = { _ in },
         onRestorePreview: @escaping @Sendable (TargetID) -> Void = { _ in },
         onAction: @escaping @Sendable (SwitcherAction, TargetID) -> Void = { _, _ in },
         onHealth: @escaping @MainActor @Sendable (String) -> Void) {
        self.onState = onState; self.onSelect = onSelect; self.onCancel = onCancel; self.onPassiveKey = onPassiveKey; self.onHealth = onHealth
        self.onAction = onAction
        self.onPreview = onPreview
        self.onRestorePreview = onRestorePreview
    }
    func start(snapshot: CatalogueSnapshot, mode: DisplayMode = .shore) {
        guard bridge.withValue({ $0.snapshot = snapshot; $0.mode = mode; if $0.running { return false }; $0.stopRequested = false; $0.running = true; return true }) else {
            // Becoming active (including selecting our own Settings window) retries
            // capture. An already-running tap must preserve the current session and
            // in-flight focus request; cancel() also calls onCancel().
            update(snapshot)
            perform { [self] in
                if state.mode != mode { state.configure(mode: mode); publish() }
            }
            return
        }
        let worker = Thread { [self] in
            state.configure(mode: mode); state.update(snapshot)
            let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<InputRouter>.fromOpaque(context).takeUnretainedValue().route(type, event)
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
            guard let tap else {
                bridge.withValue { $0.running = false }
                Task { @MainActor in onHealth("Keyboard capture is unavailable. Check Accessibility, then Retry. Input Monitoring is not requested.") }
                return
            }
            let loop = CFRunLoopGetCurrent()!
            let shouldStop = bridge.withValue { $0.loop = loop; state.update($0.snapshot); return $0.stopRequested }
            if shouldStop { CFMachPortInvalidate(tap); bridge.withValue { $0.running = false; $0.loop = nil }; return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Task { @MainActor in onHealth("Ready") }
            CFRunLoopRun()
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            self.tap = nil; ownership.reset(); earlySearchKeys.reset(); passedKeys.reset(); state.cancel()
            bridge.withValue { $0.loop = nil; $0.running = false; $0.snapshotPending = false }
            publish()
        }
        worker.name = "Tabnax input"; worker.qualityOfService = .userInteractive
        thread = worker; worker.start()
    }
    private func perform(_ body: @escaping @Sendable () -> Void) {
        guard let loop = bridge.withValue({ $0.loop }) else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, body); CFRunLoopWakeUp(loop)
    }
    func update(_ snapshot: CatalogueSnapshot) {
        let enqueue = bridge.withValue { b in
            b.snapshot = snapshot
            guard b.loop != nil, !b.snapshotPending else { return false }
            b.snapshotPending = true; return true
        }
        if enqueue { perform { [self] in
            let latest = bridge.withValue { b in b.snapshotPending = false; return b.snapshot }
            state.update(state.active ? state.snapshot.reconcilingLive(latest) : latest); if state.active { publish() }
        } }
    }
    func configureSearchMemory(_ memory: SearchMemory?) {
        bridge.withValue { b in
            if let memory, let current = b.searchMemory, current.salt == memory.salt, current.revision > memory.revision { return }
            b.searchMemory = memory
        }
        perform { [self] in state.configureSearch(memory: bridge.withValue { $0.searchMemory }) }
    }
    func configureSettings(_ value: SettingsDocument) {
        // `route()` reads settings straight from `bridge` on every event (see below), so this
        // single locked write is also the point where the change takes effect on the tap
        // thread — no separate, laggier local copy to keep in sync with it.
        bridge.withValue { $0.settings = value }
        perform { [self] in cancel() }
    }
    func suspendActivation(_ value:Bool) { bridge.withValue { $0.suspended = value }; perform { [self] in cancel() } }
    func recordShortcut(using handler: (@Sendable (Shortcut) -> Void)?) {
        bridge.withValue { $0.shortcutRecorder = handler; $0.suspended = handler != nil }
        perform { [self] in cancel() }
    }
    func setSurfaces(_ rects: [CGRect]) { bridge.withValue { $0.surfaces = rects } }
    /// Starts timing only for an opening activation, before cancellation or state preparation.
    /// This is recognition on the input thread, not the hardware event's creation timestamp.
    private func recognizeActivation(source: String, eventTimestamp: CGEventTimestamp? = nil) -> ActivationTrace {
        let trace = ActivationTrace(session: state.session &+ 1, source: source, recognizedAt: CACurrentMediaTime())
        Trace.signposter.emitEvent("activationRecognized", "session=\(trace.session, privacy: .public) source=\(source, privacy: .public)")
        Trace.log.info("perf: activationRecognized session=\(trace.session, privacy: .public) source=\(source, privacy: .public) t=\(trace.recognizedAt, privacy: .public)")
        if let eventTimestamp, eventTimestamp > 0 {
            // CGEvent timestamps are nanoseconds since startup; CACurrentMediaTime uses
            // the same uptime clock in seconds. This covers latency before our callback,
            // which recognition-to-ordering measurements cannot see after idle.
            let age = trace.recognizedAt - Double(eventTimestamp) / 1_000_000_000
            if age >= 0 {
                Trace.log.info("perf: activationEventAge session=\(trace.session, privacy: .public) seconds=\(age, privacy: .public)")
            }
        }
        return trace
    }
    /// Returns whether the session opened on the previously used window.
    @discardableResult private func openSession(_ trace: ActivationTrace) -> Bool {
        bridge.withValue { $0.menuSession = nil; $0.menuDisarmSession = nil }
        actionPreviewSuspended = false
        cycledWhileHeld = false; modifiersHeldSinceOpen = false; restoredWhileHeld = nil; previewedDuringSession = false
        state.cancel()
        state.configure(ordering: bridge.withValue { $0.settings.traversalOrder })
        state.update(bridge.withValue { $0.snapshot })
        state.configureSearch(memory: bridge.withValue { $0.searchMemory })
        let onPrevious = state.open(), preparedAt = CACurrentMediaTime()
        pendingActivationTrace = trace
        Trace.signposter.emitEvent("activationStatePrepared", "session=\(trace.session, privacy: .public)")
        // Keep the existing state-ready marker for earlier Instruments traces.
        Trace.signposter.emitEvent("activationAccepted", "session=\(trace.session, privacy: .public)")
        Trace.log.info("perf: activationStatePrepared session=\(trace.session, privacy: .public) t=\(preparedAt, privacy: .public) preparation=\(preparedAt-trace.recognizedAt, privacy: .public)")
        return onPrevious
    }
    func configureMode(_ mode: DisplayMode) { perform { [self] in state.configure(mode: mode); publish() } }
    func open() { perform { [self] in
        let trace = recognizeActivation(source: "programmatic")
        onCancel(); openSession(trace); publish()
    } }
    /// The registered hot key only fires when the tap did not swallow the chord first, which is
    /// what happens while Secure Input withholds keyboard events from taps. The session is a
    /// latch: without the tap there is no modifier release to observe.
    func toggleFromHotKey(search: Bool = false) {
        perform { [self] in
            guard !shortcutExceptionGate.passesThrough, CFAbsoluteTimeGetCurrent() - lastTapActivation > 0.3, !bridge.withValue({ $0.suspended || $0.menuSession == state.session }) else { return }
            if search {
                guard bridge.withValue({ $0.settings.searchActivation.enabled }) else { return }
                activateSearch(source: "searchHotKey"); return
            }
            if state.active { cancel() } else {
                let trace = recognizeActivation(source: "hotKey")
                onCancel(); openSession(trace); publish()
            }
        }
    }
    private func activateSearch(source: String, eventTimestamp: CGEventTimestamp? = nil) {
        onCancel()
        if !state.active { openSession(recognizeActivation(source: source, eventTimestamp: eventTimestamp)) }
        heldActivation = false; cycledWhileHeld = false; modifiersHeldSinceOpen = false; restoredWhileHeld = nil
        if state.query == nil {
            _ = state.handle(.beginSearch)
            bridge.withValue { $0.searchHandoffSession = state.session; $0.searchEvents.removeAll() }
        }
        bridge.withValue { $0.searchFocusSession = state.session }
        actionPreviewSuspended = false
        publish()
    }
    func choose(_ id: TargetID, session: UInt64? = nil) { perform { [self] in guard session == nil || session == state.session else { return }; apply(state.select(id)) } }
    func key(_ value: SelectionKey, session: UInt64? = nil) { perform { [self] in guard session == nil || session == state.session else { return }; restoredWhileHeld = nil; actionPreviewSuspended = false; apply(state.handle(value)) } }
    func action(_ value: SwitcherAction, session: UInt64) {
        perform { [self] in
            guard session == state.session else { return }
            if value == .quitApplication { performAction(value) } else { performShortcutAction(value) }
        }
    }
    /// The synchronous gate protects the gap before the input loop processes the queued
    /// disarm, including a modifier release immediately after a pointer/VoiceOver press.
    func setMenuTracking(_ tracking: Bool, session: UInt64) {
        bridge.withValue {
            if tracking { $0.menuSession = session; $0.menuReady = false; $0.menuDisarmSession = session }
            else if $0.menuSession == session { $0.menuSession = nil }
        }
        if tracking { perform { [self] in if state.session == session { disarmForMenu() } } }
    }
    func setMenuReady(session: UInt64) { bridge.withValue { if $0.menuSession == session { $0.menuReady = true } } }
    func disarmMenuRelease(session: UInt64) {
        bridge.withValue { $0.menuDisarmSession = session }
        perform { [self] in if state.session == session { disarmForMenu() } }
    }
    private func disarmForMenu() {
        heldActivation = false; cycledWhileHeld = false; modifiersHeldSinceOpen = false; restoredWhileHeld = nil
        actionPreviewSuspended = true; onCancel()
    }
    func menuAction(_ value: SwitcherAction, target: TargetID, session: UInt64) {
        perform { [self] in
            guard state.active, state.session == session, bridge.withValue({ $0.settings.windowActionsEnabled }) else { return }
            disarmForMenu(); previewedDuringSession = false
            // The menu owns this ID; do not resolve a potentially changed highlight here.
            // Let document-owned save prompts be unobstructed by our floating panel.
            if value == .closeWindow { state.cancel(); publish() }
            onAction(value, target)
        }
    }
    func hideForActivation() { perform { [self] in state.cancel(); publish() } }
    func dismiss() { perform { [self] in cancel() } }
    func stop() { bridge.withValue { $0.stopRequested = true }; perform { [self] in cancel(); CFRunLoopStop(CFRunLoopGetCurrent()) } }
    private func cancel() { bridge.withValue { $0.menuSession = nil; $0.searchHandoffSession = nil; $0.searchFocusSession = nil; $0.searchEvents.removeAll() }; heldActivation = false; cycledWhileHeld = false; modifiersHeldSinceOpen = false; restoredWhileHeld = nil; state.cancel(); onCancel(); publish() }
    private func performAction(_ action: SwitcherAction) {
        guard state.active else { return }
        // Quit disarms release selection. Restore preserves the normal Command–Tab
        // release behavior, including the exact child restored from an app group.
        if action == .quitApplication { cycledWhileHeld = false; restoredWhileHeld = nil }
        guard let id = state.actionTarget(for: action) else {
            if action == .quitApplication {
                Task { @MainActor [self] in onHealth("Highlight a running app or one of its windows to quit it.") }
            }
            return
        }
        if action == .restoreWindow, modifiersHeldSinceOpen {
            restoredWhileHeld = (id, state.highlightedAction)
        }
        onCancel(); onAction(action, id)
    }
    private func performShortcutAction(_ action: SwitcherAction) {
        guard state.active, bridge.withValue({ $0.settings.windowActionsEnabled }) else { return }
        let entry = state.actionMenuItems.first { $0.action == action || (action == .hideApplication && $0.action == .unhideApplication) }
        disarmForMenu(); previewedDuringSession = false
        guard let entry, let id = entry.target, entry.disabledReason == nil else {
            let reason = entry?.disabledReason ?? "Highlight a target for this action."
            Task { @MainActor [self] in onHealth(reason) }
            publish(); return
        }
        // Match menu behavior without ever sending these chords to the target app.
        if entry.action == .closeWindow { state.cancel() }
        publish(); onAction(entry.action, id)
    }
    /// Cycling and then letting go means "this one", in either behavior. Anything typed since
    /// the last cycle keeps the old meaning of the release: hold closes, latch stays open.
    private func modifiersReleased() {
        modifiersHeldSinceOpen = false
        let cycled = cycledWhileHeld; cycledWhileHeld = false
        let restored = restoredWhileHeld; restoredWhileHeld = nil
        let effect: SelectionEffect
        if let restored, restored.highlight == state.highlightedAction { effect = state.select(restored.id) }
        else { effect = cycled ? state.commitHighlight() : .none }
        if effect != .none { heldActivation = false; apply(effect) } else if heldActivation { cancel() }
    }
    private func apply(_ effect: SelectionEffect) {
        if case .selected(let id) = effect {
            Trace.signposter.emitEvent("selectionAccepted")
            if let memory = state.searchMemory {
                // Do not let an old input event undo a concurrent Clear/off action.
                let accepted = bridge.withValue { b in
                    guard let current = b.searchMemory, current.salt == memory.salt, memory.revision > current.revision else { return false }
                    b.searchMemory = memory; return true
                }
                if accepted { Task { @MainActor [weak self] in self?.onSearchMemory?(memory) } }
            }
            onSelect(id)
        } else if effect == .cancelled {
            onCancel()
            if previewedDuringSession, let original = state.openingHistory.current { onRestorePreview(original) }
            previewedDuringSession = false
        }
        if effect != .none { publish() }
    }
    /// `silent` still records the state for `bridge.latest` but never schedules `onState`, so
    /// the switcher panel never appears on screen for this publish.
    private func publish(silent: Bool = false) {
        // Submit on the input lane so a committed selection/cancellation cannot be
        // overtaken by an older main-thread presentation requesting a preview.
        let enabled = bridge.withValue { $0.settings.appearance.desktopSpotlight.previewsWindows }
        let preview = silent || actionPreviewSuspended ? nil : Self.previewTarget(in: state, enabled: enabled)
        if preview != nil { previewedDuringSession = true }
        onPreview(preview)
        let enqueue = bridge.withValue { b in
            b.latest = state
            if let trace = pendingActivationTrace { b.activationTrace = trace; pendingActivationTrace = nil }
            guard !silent else { return false }
            if b.activationTrace != nil, b.activationTrace?.publishedAt == nil { b.activationTrace?.publishedAt = CACurrentMediaTime() }
            guard !b.presentationPending else { return false }
            b.presentationPending = true; return true
        }
        guard enqueue else { return }
        Task { @MainActor [self] in
            let (latest, activation) = bridge.withValue { b in
                b.presentationPending = false
                let trace = b.activationTrace; b.activationTrace = nil
                return (b.latest, trace)
            }
            if let activation, activation.session == latest.session {
                let deliveredAt = CACurrentMediaTime()
                Trace.signposter.emitEvent("activationMainDelivered", "session=\(latest.session, privacy: .public) active=\(latest.active, privacy: .public)")
                // Coalescing may deliver a cancelled state (including quiet return). Neither
                // this marker nor onState delivery claims that a panel was shown or drawn.
                Trace.log.info("perf: activationMainDelivered session=\(latest.session, privacy: .public) source=\(activation.source, privacy: .public) active=\(latest.active, privacy: .public) t=\(deliveredAt, privacy: .public) fromRecognition=\(deliveredAt-activation.recognizedAt, privacy: .public) queueWait=\(deliveredAt-(activation.publishedAt ?? deliveredAt), privacy: .public)")
            }
            onState(latest)
            let focus = bridge.withValue { b -> UInt64? in
                guard latest.active, latest.query != nil, b.searchFocusSession == latest.session else { return nil }
                defer { b.searchFocusSession = nil }
                return b.searchFocusSession
            }
            if latest.active, latest.query != nil, focus == latest.session { onSearchFocus?(latest.session) }
            // Keep accepting early events until the native field is focused and the queue
            // is drained. The locked empty transition prevents losing an event at handoff.
            while true {
                let events = bridge.withValue { b -> [CGEvent] in
                    guard latest.active, latest.query != nil, b.searchHandoffSession == latest.session else {
                        if !b.latest.active { b.searchHandoffSession = nil; b.searchEvents.removeAll() }
                        return []
                    }
                    let events = b.searchEvents; b.searchEvents.removeAll()
                    if events.isEmpty { b.searchHandoffSession = nil }
                    return events
                }
                if events.isEmpty { break }
                for event in events { onSearchInput?(event, latest.session) }
            }
        }
    }

    static func previewTarget(in state: SelectionState, enabled: Bool) -> TargetID? {
        guard enabled, state.active, case .target(let id) = state.highlightedAction,
              let target = state.snapshot.windows.first(where: { $0.id == id }),
              target.available, target.isRunning, !target.hidden, !target.minimized, !target.elsewhere,
              let bounds = target.bounds, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.maxX.isFinite, bounds.maxY.isFinite, bounds.width > 1, bounds.height > 1 else { return nil }
        // Covered windows deliberately qualify: raising them makes their content visible.
        return id
    }
    private func route(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel(); ownership.reset(); earlySearchKeys.reset()
            // One loss is routine (a slow callback, a sleeping display), so capture re-arms at
            // once. Repeated losses mean something is wrong: stop, and make Retry explicit.
            let now = CFAbsoluteTimeGetCurrent()
            tapLosses = tapLosses.filter { now - $0 < 10 } + [now]
            if tapLosses.count < 3 {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                Trace.log.notice("Keyboard capture re-armed after tap loss \(type.rawValue, privacy: .public)")
                return Unmanaged.passUnretained(event)
            }
            tapLosses.removeAll()
            Task { @MainActor [self] in onHealth("Keyboard capture stopped. Retry in Tabnax settings.") }
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            CFRunLoopStop(CFRunLoopGetCurrent())
            return Unmanaged.passUnretained(event)
        }
        let eventCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp { _ = earlySearchKeys.release(eventCode) }
        if type == .keyUp && passedKeys.release(eventCode) { return Unmanaged.passUnretained(event) }
        if type == .keyDown && passedKeys.contains(eventCode) { return Unmanaged.passUnretained(event) }
        if !state.active && (type == .keyDown || type == .keyUp || type == .flagsChanged) && shortcutExceptionGate.passesThrough && !bridge.withValue({ $0.shortcutRecorder != nil }) {
            // Finish key sequences Tabnax already owns; never swallow a repeat/up for a
            // shortcut that began in the exception app, even if focus or rules changed.
            if type == .keyUp { return ownership.release(eventCode) ? nil : Unmanaged.passUnretained(event) }
            if type == .keyDown {
                if ownership.contains(eventCode) { return nil }
                passedKeys.claim(eventCode); onPassiveKey()
            }
            if type == .flagsChanged { optionWasDown = event.flags.contains(.maskAlternate) }
            return Unmanaged.passUnretained(event)
        }
        let menu = bridge.withValue { b in
            let pending = b.menuDisarmSession == state.session; b.menuDisarmSession = nil
            return (b.menuSession == state.session, pending, b.menuReady)
        }
        if menu.1 { disarmForMenu() }
        if menu.0 && state.active {
            // Native menu tracking owns keys, outside clicks and modifier transitions.
            // Only finish swallowing keys we owned before tracking began.
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if type == .flagsChanged { optionWasDown = event.flags.contains(.maskAlternate) }
            if type == .keyUp { return ownership.release(code) ? nil : Unmanaged.passUnretained(event) }
            if type == .keyDown && ownership.contains(code) { return nil }
            // Capability checks are asynchronous. Until NSMenu begins tracking, keys
            // must not reach the search editor or the app that was previously active.
            if type == .keyDown && !menu.2 { ownership.claim(code); return nil }
            if type == .keyDown, let action = WindowActionShortcut.action(code: code, flags: event.flags,
                activation: CGEventFlags(rawValue: bridge.withValue { $0.settings.activation.modifiers })) {
                ownership.claim(code)
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    let session = state.session
                    Task { @MainActor [self] in onMenuShortcut?(action, session) }
                }
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            // Mouse activity supersedes in-flight focus. The UI handles outside dismissal
            // so clicking an accessible row in our nonactivating panel still works.
            onCancel()
            if state.active {
                // CGEvent coordinates and the published surface frames both use the
                // Quartz top-left coordinate space. Read the event's own location.
                let point = event.location
                if !bridge.withValue({ $0.surfaces.contains { $0.contains(point) } }) { cancel() }
            }
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        // Fetched fresh per event (not cached in an ivar) so a settings change made while
        // this thread was between events is never processed against a stale copy.
        let settings = bridge.withValue { $0.settings }
        let shortcut = Shortcut(keyCode: settings.activation.keyCode, modifiers: CGEventFlags(rawValue: settings.activation.modifiers))
        let optionPressed = (code == 58 || code == 61) && event.flags.contains(.maskAlternate) && !optionWasDown
        optionWasDown = event.flags.contains(.maskAlternate)
        if type == .flagsChanged {
            if state.active && event.flags.intersection(shortcut.modifiers) != shortcut.modifiers { modifiersReleased() }
            if optionPressed, state.active, state.query == nil,
               event.flags.intersection(Shortcut.relevant).subtracting(shortcut.modifiers.union(.maskAlternate)).isEmpty,
               !bridge.withValue({ $0.suspended }) {
                performAction(.restoreWindow)
            }
            // Keep modifier transitions paired for the OS and any native search field.
            return Unmanaged.passUnretained(event)
        }
        if type == .keyUp {
            // The trigger doubles as the cycle key while its modifiers stay down (see below):
            // releasing it between taps must not cancel, only releasing the modifiers does.
            return ownership.release(code) ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if ownership.contains(code) {
            if repeated, state.active, state.query != nil, earlySearchKeys.contains(code) {
                let buffered = bridge.withValue { b -> Bool in
                    guard b.searchHandoffSession == state.session else { return false }
                    b.searchEvents.append(event.copy() ?? event); return true
                }
                return buffered ? nil : Unmanaged.passUnretained(event)
            }
            // Holding the cycle key down keeps advancing, matching the system switcher's
            // key-repeat behavior; every other key's autorepeat stays inert once handled.
            if repeated, state.active, state.query == nil, code == 48 || code == 125 || code == 126 {
                let heldFlags = event.flags.intersection(Shortcut.relevant)
                let key: SelectionKey = code == 126 || heldFlags.contains(.maskShift) ? .previous : .next
                restoredWhileHeld = nil
                cycledWhileHeld = heldFlags.intersection(shortcut.modifiers) == shortcut.modifiers
                apply(state.handle(key, repeated: true))
            }
            return nil // Includes autorepeat after commit.
        }
        if repeated { return Unmanaged.passUnretained(event) }
        let flags = event.flags.intersection(Shortcut.relevant)
        // Capture before macOS handles Command–Tab. Local AppKit monitors never
        // see that system chord. Ownership also swallows its repeat and key-up,
        // even when recording finishes before the physical key is released.
        if let recorder = bridge.withValue({ $0.shortcutRecorder }) {
            ownership.claim(code)
            recorder(Shortcut(keyCode:code,modifiers:flags))
            return nil
        }
        let searchShortcut = settings.searchActivation.shortcut
        if settings.searchActivation.enabled, searchShortcut.valid,
           code == searchShortcut.keyCode, flags.rawValue == searchShortcut.modifiers,
           sideMatches(event.flags, activation: searchShortcut), !bridge.withValue({ $0.suspended }) {
            ownership.claim(code); lastTapActivation = CFAbsoluteTimeGetCurrent()
            activateSearch(source: "searchEventTap", eventTimestamp: event.timestamp)
            return nil
        }
        var retrigger = false
        if code == shortcut.keyCode && flags == shortcut.modifiers && settings.activation.valid && sideMatches(event.flags, activation: settings.activation) && !bridge.withValue({$0.suspended}) {
            // Held open: repeated trigger taps must cycle like the switcher they replace, not
            // re-toggle the panel. Tab always cycles, since a second Tab tap with Command still
            // held is the ordinary way people use Command–Tab. Any other trigger cycles while
            // its modifiers have stayed down since opening; once they were let go, pressing the
            // chord again closes a latched switcher. Cycling falls through to .next below.
            retrigger = state.active && (code == 48 || heldActivation || modifiersHeldSinceOpen)
            if !retrigger {
                ownership.claim(code); lastTapActivation = CFAbsoluteTimeGetCurrent()
                if state.active { cancel() } else {
                    let trace = recognizeActivation(source: "eventTap", eventTimestamp: event.timestamp)
                    onCancel(); let onPrevious = openSession(trace)
                    heldActivation = settings.activation.behavior == .hold; modifiersHeldSinceOpen = true
                    // Command–Tab counts its opening press as a selection, including in latch
                    // mode. Other hold shortcuts return only when a previous window is known.
                    cycledWhileHeld = settings.activation.isCommandTab || (heldActivation && onPrevious)
                    // Quiet return: don't show the panel yet. If the release comes before any
                    // further cycling, modifiersReleased() commits straight to the previous
                    // window and the panel is never seen. Cycling further (below) always
                    // publishes normally, so continuing to hold still reveals the switcher.
                    publish(silent: heldActivation && onPrevious && settings.activation.quietReturnEnabled)
                }
                return nil
            }
        }
        guard state.active else {
            // Typing after a switch was dispatched must not abort it halfway: the raise and
            // activation complete, and only the late repair that could steal focus back from
            // whatever the user is now doing is disarmed.
            onPassiveKey(); return Unmanaged.passUnretained(event)
        }
        if settings.windowActionsEnabled, Self.isActionMenuShortcut(code: code, flags: flags, activation: shortcut.modifiers) {
            ownership.claim(code); disarmForMenu()
            bridge.withValue { $0.menuSession = state.session; $0.menuReady = false }
            publish()
            let menuState = state
            Task { @MainActor [self] in onActionMenu?(menuState) }
            return nil
        }
        // Resolve commands before label typing, search handoff and modifier-release
        // selection. Residual activation modifiers may still be held with Command-Q.
        if Self.isQuitShortcut(code: code, flags: flags, activation: shortcut.modifiers) {
            ownership.claim(code); performAction(.quitApplication); return nil
        }
        if settings.windowActionsEnabled, let action = WindowActionShortcut.action(code: code, flags: flags, activation: shortcut.modifiers) {
            ownership.claim(code); performShortcutAction(action); return nil
        }
        if flags.intersection(shortcut.modifiers) != shortcut.modifiers {
            // A key without the activation modifiers proves they were let go, even when the
            // release itself was never delivered. A held session ends there.
            if heldActivation { modifiersReleased(); return Unmanaged.passUnretained(event) }
            modifiersHeldSinceOpen = false
        }
        // Search text, IME composition and editing commands belong to AppKit.
        if state.query != nil {
            let buffered = bridge.withValue { b -> Bool in
                guard b.searchHandoffSession == state.session else { return false }
                b.searchEvents.append(event.copy() ?? event); return true
            }
            if buffered { ownership.claim(code); earlySearchKeys.claim(code); return nil }
            return Unmanaged.passUnretained(event)
        }
        // Modified typing belongs to the user's application/IME/VoiceOver. Only
        // residual activation modifiers are accepted while the latch is open.
        let commandFlags = code == 48 ? flags.subtracting(.maskShift) : flags
        guard commandFlags.subtracting(shortcut.modifiers).isEmpty else {
            cancel(); return Unmanaged.passUnretained(event)
        }
        let key: SelectionKey?
        switch code {
        case _ where retrigger && code != 48: key = .next
        case 53: key = .escape
        case 51: key = .backspace
        case 48, 125: key = flags.contains(.maskShift) ? .previous : .next
        case 126: key = .previous
        case 123: key = .lateral(-1)
        case 124: key = .lateral(1)
        case 36, 76: key = .enter
        case 44: key = .beginSearch
        default:
            if settings.selection.interpretation == .characters {
                let text = NSEvent(cgEvent:event)?.charactersIgnoringModifiers?.lowercased() ?? ""
                // Fixed app letters and overflow prefixes may be outside the user's
                // alphabet. Accept the same A–Z address vocabulary as physical input.
                key = text.utf8.count == 1 && text.utf8.allSatisfy { (97...122).contains($0) } ? .letter(text) : nil
            } else { key = Self.letters[code].map { .letter($0) } }
        }
        guard let key else {
            // A stray key must neither close the switcher nor leak into the app underneath.
            // Function keys keep working; everything else is swallowed along with its key-up.
            if Self.functionKeys.contains(code) { return Unmanaged.passUnretained(event) }
            ownership.claim(code); return nil
        }
        switch key {
        case .next, .previous, .lateral: cycledWhileHeld = flags.intersection(shortcut.modifiers) == shortcut.modifiers
        default: cycledWhileHeld = false
        }
        restoredWhileHeld = nil
        actionPreviewSuspended = false
        ownership.claim(code); apply(state.handle(key)); return nil
    }
    private func sideMatches(_ flags: CGEventFlags, activation: ActivationPreferences) -> Bool {
        let shortcut = Shortcut(keyCode: activation.keyCode, modifiers: CGEventFlags(rawValue: activation.modifiers))
        guard activation.side != .either else { return true }
        let raw = flags.rawValue
        // NX device-dependent masks from IOLLEvent.h, retained by Quartz events.
        let masks: [(CGEventFlags,UInt64,UInt64)] = [(.maskControl,0x1,0x2000),(.maskShift,0x2,0x4),(.maskCommand,0x8,0x10),(.maskAlternate,0x20,0x40)]
        return masks.filter { shortcut.modifiers.contains($0.0) }.allSatisfy { _,left,right in
            activation.side == .left ? raw & left != 0 && raw & right == 0 : raw & right != 0 && raw & left == 0
        }
    }
    static func isQuitShortcut(code: UInt16, flags: CGEventFlags, activation: CGEventFlags) -> Bool {
        SwitcherAction.quitApplication.shortcut.matches(code: code, flags: flags, activation: activation)
    }
    static func isActionMenuShortcut(code: UInt16, flags: CGEventFlags, activation: CGEventFlags) -> Bool {
        code == 47 && flags.contains(.maskCommand)
            && flags.intersection(Shortcut.relevant).subtracting(activation.union(.maskCommand)).isEmpty
    }
    // Physical key addresses are deliberate, independent of text composition.
    // Settings names this contract; normal typing while closed is passed unchanged.
    static let functionKeys: Set<UInt16> = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
    static let letters: [UInt16: String] = [0:"a",1:"s",2:"d",3:"f",4:"h",5:"g",6:"z",7:"x",8:"c",9:"v",11:"b",12:"q",13:"w",14:"e",15:"r",16:"y",17:"t",31:"o",32:"u",34:"i",35:"p",37:"l",38:"j",40:"k",45:"n",46:"m"]
}

/// A registered hot key for the activation chord, kept alongside the event tap. The tap sees
/// the chord first and swallows it, so this normally never fires. It fires when the tap gets
/// no keyboard events at all: while another app holds Secure Input (a password field, a
/// terminal with secure entry) or after capture was lost. Once open, the key panel handles
/// its own keys. Command–Tab cannot be registered this way and stays tap-only.
@MainActor final class HotKeyFallback {
    // Each handler must reject other instances before consuming a Carbon callback.
    // Generation alone is local to the instance and is not a dispatch identity.
    private static var nextSignature: UInt32 = 0x54424E58
    let signature: UInt32
    var eventID: EventHotKeyID { EventHotKeyID(signature: signature, id: registrationGeneration) }
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var registered: ActivationPreferences?
    private var wanted: ActivationPreferences?
    private var retry: DispatchWorkItem?
    private(set) var registrationGeneration: UInt32 = 0
    private let keyIsDown: (UInt16) -> Bool
    private let installHandlerForTesting: Bool
    private let registerForTesting: ((ActivationPreferences) -> Bool)?
    private let unregisterForTesting: (() -> Void)?
    var onFire: (() -> Void)?
    var onRetryRegistration: (() -> Void)?
    func retryRegistration() {
        if let onRetryRegistration { onRetryRegistration() } else { reconcile() }
    }
    init(keyIsDown: @escaping (UInt16) -> Bool = { CGEventSource.keyState(.combinedSessionState, key: $0) },
         register: ((ActivationPreferences) -> Bool)? = nil, unregister: (() -> Void)? = nil, installHandlerForTesting: Bool = false) {
        self.installHandlerForTesting = installHandlerForTesting
        signature = Self.nextSignature; Self.nextSignature &+= 1
        self.keyIsDown = keyIsDown; registerForTesting = register; unregisterForTesting = unregister
    }
    func configure(_ activation: ActivationPreferences?) {
        wanted = activation.flatMap { $0.valid && !$0.isCommandTab && $0.side == .either && $0.modifiers != 0 ? $0 : nil }
        reconcile()
    }
    private func sameChord(_ a: ActivationPreferences?, _ b: ActivationPreferences?) -> Bool {
        a?.keyCode == b?.keyCode && a?.modifiers == b?.modifiers
    }
    func reconcile() {
        guard !sameChord(wanted, registered) else { return }
        retry?.cancel(); retry = nil
        if registered != nil {
            if let unregisterForTesting { unregisterForTesting() }
            else if let hotKey {
                let status = UnregisterEventHotKey(hotKey)
                guard status == noErr else {
                    Trace.log.error("Could not release hot key fallback (\(status, privacy: .public)); retrying")
                    let work = DispatchWorkItem { [weak self] in self?.retryRegistration() }
                    retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
                    return
                }
            }
            hotKey = nil; registered = nil
            registrationGeneration &+= 1
        }
        guard let wanted else { return }
        // Re-registering during a passed-through physical key sequence would reserve its
        // repeats/key-up. Wait for release, including initialization and secure-input use.
        guard !keyIsDown(wanted.keyCode) else {
            let work = DispatchWorkItem { [weak self] in self?.retryRegistration() }
            retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: work)
            return
        }
        registrationGeneration &+= 1
        if let registerForTesting, !installHandlerForTesting {
            if registerForTesting(wanted) { registered = wanted }
            return
        }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let fallback = Unmanaged<HotKeyFallback>.fromOpaque(context).takeUnretainedValue()
                    guard id.signature == fallback.signature else { return OSStatus(eventNotHandledErr) }
                    fallback.dispatch(generation: id.id)
                    return noErr
                }
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        }
        if let registerForTesting {
            if registerForTesting(wanted) { registered = wanted }
            return
        }
        let flags = CGEventFlags(rawValue: wanted.modifiers)
        var carbon: UInt32 = 0
        if flags.contains(.maskCommand) { carbon |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { carbon |= UInt32(optionKey) }
        if flags.contains(.maskControl) { carbon |= UInt32(controlKey) }
        let status = RegisterEventHotKey(UInt32(wanted.keyCode), carbon, eventID, GetApplicationEventTarget(), 0, &hotKey)
        if status == noErr { registered = wanted } else {
            hotKey = nil; Trace.log.notice("Hot key fallback unavailable (\(status, privacy: .public))")
        }
    }
    func dispatch(generation: UInt32) {
        guard registered != nil, generation == registrationGeneration else { return }
        if IsSecureEventInputEnabled() { Trace.log.notice("Activation arrived by hot key while Secure Input is on") }
        onFire?()
    }
    func stop() {
        configure(nil)
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    var isRegistered: Bool { registered != nil }
}

#if DEBUG
extension HotKeyFallback {
    func sendPressForTesting() {
        var event: EventRef?, id = eventID
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr, let event else { return }
        defer { ReleaseEvent(event) }
        guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr else { return }
        SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}
extension InputRouter {
    /// Calls the real callback router without installing a tap or posting events.
    /// One isolated router instance per test; no run loop/UI frame is advanced.
    func replayForTesting(snapshot: CatalogueSnapshot, mode: DisplayMode = .shore, settings: SettingsDocument = .init(), events: [(CGEventType, CGEvent)]) -> [Bool] {
        precondition(!bridge.withValue { $0.running })
        bridge.withValue { $0.snapshot = snapshot; $0.settings = settings }
        state.configure(mode: mode); state.update(snapshot)
        return events.map { route($0.0, $0.1) == nil }
    }
    /// True right after a `publish()` that scheduled `onState`, i.e. the panel would appear.
    /// Set synchronously inside `publish()`, before the async dispatch that shows it runs, so
    /// it can be asserted immediately after `replayForTesting` without waiting on the run loop.
    func routeForTesting(_ event: CGEvent) -> Bool { route(event.type, event) == nil }
    var stateForTesting: SelectionState { state }
    var presentationPendingForTesting: Bool { bridge.withValue { $0.presentationPending } }
    func markRunningForTesting() {
        bridge.withValue { $0.running = true; $0.loop = CFRunLoopGetCurrent() }
    }
    func clearRunningForTesting() {
        bridge.withValue { $0.running = false; $0.loop = nil }
    }
}
#endif
