import AppKit
import ApplicationServices
import TabnaxCore

struct FocusTarget: Sendable {
    let process: ProcessInfo
    let window: WindowRecord?
}
struct FocusOutcome: Sendable {
    let id: TargetID
    let generation: UInt64
    let observed: Bool
    let message: String
}
/// One reserved action lane, one latest pending focus intent. Discovery cannot
/// occupy this queue. Focus steps check generation; explicit actions check identity.
final class FocusCoordinator: @unchecked Sendable {
    private struct State {
        var registry: [TargetID: FocusTarget] = [:]
        var generation: UInt64 = 0
        var moveCursorToSelectedWindow = false
        var cursorGeneration: UInt64?
        var pending: (TargetID, UInt64)?
        var running = false
        var expectedPID: pid_t?
        var previewID: TargetID?
        var previewedID: TargetID?
        var previewActivationPIDs = Set<pid_t>()
        /// The generation whose late repair was called off by the user typing.
        var repairDisarmed: UInt64?
    }
    private let state = Locked(State())
    private let queue = DispatchQueue(label: "Tabnax reserved focus", qos: .userInteractive)
    var onWillActivate: (@MainActor @Sendable () -> Void)?
    var onOutcome: (@MainActor @Sendable (FocusOutcome) -> Void)?
    var onActionOutcome: (@MainActor @Sendable (SwitcherAction, TargetID, Bool, String) -> Void)?
    var onPreviewRaised: (@MainActor @Sendable (TargetID) -> Void)?
    /// A discovery may record focus only if it began and ended outside every preview
    /// or focus transition. A Boolean alone admits a late preview read after cancel.
    var observationToken: UInt64? {
        state.withValue { s in
            s.expectedPID == nil && s.previewID == nil && s.previewActivationPIDs.isEmpty ? s.generation : nil
        }
    }
    var hasPendingFocus: Bool { state.withValue { $0.expectedPID != nil } }
    var hasWindowPreview: Bool { state.withValue { $0.previewID != nil || !$0.previewActivationPIDs.isEmpty } }
    var previewedID: TargetID? { state.withValue { $0.previewedID } }
    func isPreviewActivation(_ pid: pid_t) -> Bool {
        state.withValue { s in s.previewActivationPIDs.contains(pid) || s.previewID.flatMap { s.registry[$0]?.process.pid } == pid }
    }
    func update(_ registry: [TargetID: FocusTarget]) { state.withValue { $0.registry = registry } }
    func cancel() {
        state.withValue {
            $0.generation &+= 1; $0.pending = nil; $0.expectedPID = nil; $0.previewID = nil; $0.previewedID = nil
            // A raised preview remains foreground, and its queued activation can arrive
            // after cancellation (including opening a menu). Keep that provenance until
            // a verified selection or a different external activation replaces it.
        }
    }

    /// Preview uses the same verified raise/activation path as final selection,
    /// but keeps the switcher open and does not record a committed focus outcome.
    func preview(_ id: TargetID?) {
        let start = state.withValue { s in
            guard s.previewID != id else { return false }
            if id == nil {
                if s.previewID != nil {
                    s.generation &+= 1; s.pending = nil; s.expectedPID = nil
                }
                s.previewID = nil; s.previewedID = nil; return false
            }
            guard s.expectedPID == nil || s.previewID != nil else { return false }
            s.generation &+= 1; s.pending = nil; s.expectedPID = nil
            s.previewID = nil; s.previewedID = nil
            guard let id, let target = s.registry[id], let window = target.window,
                  window.available, !window.minimized, !window.elsewhere else { return false }
            s.previewID = id; s.expectedPID = target.process.pid; s.pending = (id, s.generation)
            if s.running { return false }; s.running = true; return true
        }
        if start { queue.async { [self] in drain() } }
    }
    /// Typing after a selection keeps the switch itself going but forbids the late repair,
    /// which could otherwise pull focus back while the user is already working.
    func disarmRepair() { state.withValue { if $0.expectedPID != nil { $0.repairDisarmed = $0.generation } } }
    private func repairArmed(_ generation: UInt64) -> Bool { state.withValue { $0.repairDisarmed != generation } }
    func externalActivation(_ pid: pid_t) {
        state.withValue { s in
            guard !s.previewActivationPIDs.contains(pid), s.expectedPID != pid else { return }
            guard s.expectedPID != nil || s.previewID != nil || !s.previewActivationPIDs.isEmpty else { return }
            s.generation &+= 1; s.pending = nil; s.expectedPID = nil; s.previewID = nil; s.previewedID = nil
            s.previewActivationPIDs.removeAll()
        }
    }
    #if DEBUG
    /// Model a dispatched preview activation without raising any real window.
    func markPreviewActivationForTesting(_ pid: pid_t) { state.withValue { $0.previewActivationPIDs.insert(pid) } }
    #endif
    func configureCursorMovement(_ enabled: Bool) { state.withValue { $0.moveCursorToSelectedWindow = enabled } }
    func submit(_ id: TargetID, moveCursor: Bool = true) {
        Trace.signposter.emitEvent("focusEnqueued")
        let start = state.withValue { s in
            // An already submitted preview activation can be delivered after this
            // final intent. Keep recognizing those events until selection completes.
            s.previewID = nil; s.previewedID = nil
            s.generation &+= 1; s.pending = (id, s.generation)
            s.cursorGeneration = moveCursor && s.moveCursorToSelectedWindow ? s.generation : nil
            s.expectedPID = s.registry[id]?.process.pid
            if s.running { return false }; s.running = true; return true
        }
        if start { queue.async { [self] in drain() } }
    }
    /// Uses the reserved lane and the same process/window lifetimes as focus. The
    /// event tap only enqueues intent; no AX or AppKit work runs in its callback.
    func perform(_ action: SwitcherAction, on id: TargetID) {
        // Each accepted action is independent: quickly acting on a second app must
        // not cancel the first quit/restore request. Only focus is latest-wins.
        let target = state.withValue { s in
            s.previewID = nil; s.previewedID = nil; s.previewActivationPIDs.removeAll()
            s.generation &+= 1; s.pending = nil; s.expectedPID = nil
            return s.registry[id]
        }
        guard let target else {
            actionFinished(action, id, false, "That app or window is no longer available."); return
        }
        let work: @Sendable () -> Void = { [self] in
            guard state.withValue({ $0.registry[id] != nil }) else { return }
            // The PID alone is not an identity: macOS can reuse it after an app exits.
            guard let app = NSRunningApplication(processIdentifier: target.process.pid), !app.isTerminated,
                  target.process.launchDate == nil || target.process.launchDate == app.launchDate else {
                actionFinished(action, id, false, "That application is no longer running."); return
            }
            switch action {
            case .quitApplication:
                Task { @MainActor [self] in
                    guard state.withValue({ $0.registry[id] != nil }), !app.isTerminated else { return }
                    // A normal quit request leaves save dialogs and cancellation to the app.
                    // Acceptance is not proof of exit; catalogue notifications retire its rows.
                    let accepted = app.terminate()
                    actionFinished(action, id, accepted, accepted
                        ? "Quit requested for \(target.process.name)."
                        : "\(target.process.name) could not be asked to quit.")
                }
            case .hideApplication, .unhideApplication:
                Task { @MainActor [self] in
                    guard state.withValue({ $0.registry[id] != nil }), !app.isTerminated else { return }
                    let accepted = action == .hideApplication ? app.hide() : app.unhide()
                    actionFinished(action, id, accepted, accepted ? "\(action.title) requested for \(target.process.name)." : "\(action.title) was declined by the app.")
                }
            case .restoreWindow, .closeWindow, .minimizeWindow, .zoomWindow, .toggleFullscreen:
                guard let reason = windowActionUnavailable(target, id: id) else {
                    let result = WindowActionAccess(window: target.window!.handle.element).perform(action, hidden: app.isHidden)
                    actionFinished(action, id, result.0, result.1); return
                }
                actionFinished(action, id, false, reason)
            }
        }
        // Restoring our own minimized Settings window enters AppKit too.
        if target.process.pid == Foundation.ProcessInfo.processInfo.processIdentifier {
            Task { @MainActor in work() }
        } else {
            queue.async(execute: work)
        }
    }
    private func windowActionUnavailable(_ target: FocusTarget, id: TargetID) -> String? {
        guard AXIsProcessTrusted() else { return "Accessibility is unavailable" }
        guard let known = target.window, known.id == id, known.available,
              state.withValue({ $0.registry[id]?.window.map { CFEqual($0.handle.element, known.handle.element) } == true }) else {
            return "That exact window is no longer available"
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(known.handle.element, &pid) == .success, pid == target.process.pid,
              axValue(known.handle.element, kAXRoleAttribute).1 as? String == kAXWindowRole else {
            return "That exact window is no longer available"
        }
        return nil
    }
    /// Probe only this frozen menu's small target set, off the event tap and main thread
    /// (except our own windows, whose AX handlers enter AppKit). Never enumerate fallback windows.
    func inspectActions(_ items: [SwitcherActionItem], completion: @escaping @MainActor @Sendable ([SwitcherActionItem]) -> Void) {
        let captured = state.withValue { $0.registry }
        let work: @Sendable () -> Void = { [self] in
            let checked = items.map { original -> SwitcherActionItem in
                var item = original
                guard item.disabledReason == nil, let id = item.target else { return item }
                guard let target = captured[id], state.withValue({ $0.registry[id] != nil }),
                      let app = NSRunningApplication(processIdentifier: target.process.pid), !app.isTerminated,
                      target.process.launchDate == nil || target.process.launchDate == app.launchDate else {
                    item.disabledReason = "App is no longer running"; return item
                }
                switch item.action {
                case .quitApplication: break
                case .hideApplication, .unhideApplication:
                    item = SwitcherActionItem(action: app.isHidden ? .unhideApplication : .hideApplication, target: id)
                default:
                    item.disabledReason = windowActionUnavailable(target, id: id)
                    if item.disabledReason == nil, let window = target.window {
                        item.disabledReason = WindowActionAccess(window: window.handle.element).disabledReason(for: item.action, hidden: app.isHidden)
                    }
                }
                return item
            }
            Task { @MainActor in completion(checked) }
        }
        if items.contains(where: { $0.target.flatMap { captured[$0]?.process.pid } == getpid() }) {
            Task { @MainActor in work() }
        } else { queue.async(execute: work) }
    }
    private func actionFinished(_ action: SwitcherAction, _ id: TargetID, _ success: Bool, _ message: String) {
        Task { @MainActor [self] in
            onActionOutcome?(action, id, success, message)
        }
    }
    private func drain() {
        while let request = state.withValue({ s -> (TargetID, UInt64, FocusTarget?)? in
            guard let pending = s.pending else { s.running = false; return nil }
            s.pending = nil; return (pending.0, pending.1, s.registry[pending.0])
        }) {
            Trace.signposter.emitEvent("focusWorkerStart")
            guard let target = request.2 else { finish(request.0, request.1, false, "That window is no longer available."); continue }
            focus(request.0, generation: request.1, target: target)
        }
    }
    private func current(_ generation: UInt64, _ id: TargetID) -> Bool {
        state.withValue { $0.generation == generation && $0.registry[id] != nil }
    }
    private func focus(_ id: TargetID, generation: UInt64, target: FocusTarget) {
        // AX calls targeting this process enter AppKit synchronously on the caller's
        // thread. Raising Settings on the worker races the main-thread panel dismissal
        // and trips NSWMWindowCoordinator's transaction assertion.
        if target.process.pid == Foundation.ProcessInfo.processInfo.processIdentifier {
            Task { @MainActor [self] in beginFocus(id, generation: generation, target: target) }
        } else {
            beginFocus(id, generation: generation, target: target)
        }
    }
    private func beginFocus(_ id: TargetID, generation: UInt64, target: FocusTarget) {
        let started = ContinuousClock.now
        func valid() -> Bool { current(generation, id) && started.duration(to: .now) < .milliseconds(700) }
        guard valid(), AXIsProcessTrusted() else { finish(id, generation, false, "Accessibility is unavailable."); return }
        if state.withValue({ $0.previewID == id }) {
            guard let window = target.window,
                  let app = NSRunningApplication(processIdentifier: target.process.pid), !app.isTerminated, !app.isHidden,
                  target.process.launchDate == nil || target.process.launchDate == app.launchDate,
                  axValue(window.handle.element, kAXMinimizedAttribute).1 as? Bool == false else {
                finish(id, generation, false, "Window preview is unavailable."); return
            }
        }
        Trace.signposter.emitEvent("focusDispatch")
        if let window = target.window {
            if window.minimized {
                guard valid() else { finish(id, generation, false, "Focus request expired before completion."); return }
                let error = AXUIElementSetAttributeValue(window.handle.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                guard error == .success else { finish(id, generation, false, "This window could not be restored (AX \(error.rawValue))."); return }
            }
            guard valid() else { finish(id, generation, false, "Focus request expired before completion."); return }
            let raised = AXUIElementPerformAction(window.handle.element, kAXRaiseAction as CFString)
            if raised == .invalidUIElement || raised == .apiDisabled {
                finish(id, generation, false, "The window handle is no longer available. Refreshing the catalogue."); return
            }
            guard valid() else { finish(id, generation, false, "Focus request expired before completion."); return }
            // Unsupported attributes are allowed; observation is the success criterion.
            _ = AXUIElementSetAttributeValue(window.handle.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        guard valid() else { finish(id, generation, false, "Focus request expired before completion."); return }
        // AppKit activation is submitted asynchronously. Never block the input thread
        // or wait on the main queue from a discovery operation.
        Task { @MainActor [self] in
            guard started.duration(to: .now) < .milliseconds(700) else {
                finish(id, generation, false, "Activation expired before dispatch."); return
            }
            guard current(generation, id), let app = NSRunningApplication(processIdentifier: target.process.pid), !app.isTerminated,
                  target.process.launchDate == nil || target.process.launchDate == app.launchDate else { return }
            let preview = state.withValue { s in
                guard s.previewID == id else { return false }
                s.previewActivationPIDs.insert(target.process.pid); return true
            }
            if !preview { onWillActivate?() }
            if app.isHidden { app.unhide() }
            if app == .current {
                // Our own window: nobody is there to yield activation to an accessory app asking
                // for itself, so macOS may decline it. AppKit brings the window up directly.
                NSApp.activate()
                for window in NSApp.windows where !(window is NSPanel) && window.title == target.window?.title {
                    window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
                }
            } else {
                if NSApp.isActive { NSApp.yieldActivation(to: app) }
                _ = app.activate(options: [])
            }
            queue.async { [self] in verify(id, generation: generation, target: target, started: started, attempt: 0) }
        }
    }
    private func verify(_ id: TargetID, generation: UInt64, target: FocusTarget, started: ContinuousClock.Instant, attempt: Int) {
        // Verification can also raise/set focus during its bounded repair.
        if target.process.pid == Foundation.ProcessInfo.processInfo.processIdentifier {
            Task { @MainActor [self] in verifyFocus(id, generation: generation, target: target, started: started, attempt: attempt) }
        } else {
            verifyFocus(id, generation: generation, target: target, started: started, attempt: attempt)
        }
    }
    private func verifyFocus(_ id: TargetID, generation: UInt64, target: FocusTarget, started: ContinuousClock.Instant, attempt: Int) {
        guard current(generation, id) else { return }
        guard started.duration(to: .now) < .milliseconds(900) else {
            finish(id, generation, false, "Focus was not confirmed. This app or Space may not support exact-window switching."); return
        }
        let system = AXHandle(AXUIElementCreateSystemWide())
        let (_, frontValue) = axValue(system.element, kAXFocusedApplicationAttribute)
        var pid: pid_t = 0
        if let front = axElement(frontValue) { AXUIElementGetPid(front, &pid) }
        guard current(generation, id) else { return }
        var exact = target.window == nil
        if let window = target.window {
            let (_, focused) = axValue(target.process.focusApp.element, kAXFocusedWindowAttribute)
            if let element = axElement(focused) { exact = CFEqual(element, window.handle.element) }
        }
        if pid == target.process.pid && exact {
            Trace.signposter.emitEvent("focusObserved")
            let elapsed = started.duration(to: .now).components
            Trace.log.info("Focus observed after \(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000, privacy: .public) ms, \(attempt, privacy: .public) rechecks")
            centerCursorIfRequested(id, generation: generation, target: target)
            finish(id, generation, true, target.window == nil ? "Application activation observed." : "Exact window focus observed.")
            return
        }
        // One bounded post-activation repair, only while the intent remains current.
        // Never repeatedly raise a target after an external key/click/activation.
        if attempt == 0, pid == target.process.pid, let window = target.window, current(generation, id), repairArmed(generation) {
            _ = AXUIElementPerformAction(window.handle.element, kAXRaiseAction as CFString)
            if current(generation, id) {
                _ = AXUIElementSetAttributeValue(target.process.focusApp.element, kAXFocusedWindowAttribute as CFString, window.handle.element)
            }
        }
        // A background accessory app's activate(options:) request can be declined by macOS.
        // Asking the target to bring itself forward is the public alternative; once, and only
        // while the intent is still current and the user has not moved on.
        if attempt == 2, pid != target.process.pid, current(generation, id), repairArmed(generation) {
            Trace.log.notice("Activation not observed; asking the app to come forward")
            _ = AXUIElementSetAttributeValue(target.process.focusApp.element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if let window = target.window, current(generation, id) {
                _ = AXUIElementPerformAction(window.handle.element, kAXRaiseAction as CFString)
            }
        }
        guard current(generation, id) else { return }
        queue.asyncAfter(deadline: .now() + .milliseconds(40)) { [self] in
            verify(id, generation: generation, target: target, started: started, attempt: attempt + 1)
        }
    }
    private func centerCursorIfRequested(_ id: TargetID, generation: UInt64, target: FocusTarget) {
        guard state.withValue({ $0.cursorGeneration == generation && $0.moveCursorToSelectedWindow }),
              current(generation, id), repairArmed(generation), let window = target.window else { return }
        // Read live geometry after restoring/focusing. AX and Quartz cursor coordinates
        // both use screen points with the origin at the primary display's top left.
        let (positionError, positionValue) = axValue(window.handle.element, kAXPositionAttribute)
        let (sizeError, sizeValue) = axValue(window.handle.element, kAXSizeAttribute)
        guard positionError == .success, sizeError == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        guard center.x.isFinite, center.y.isFinite, current(generation, id), repairArmed(generation) else { return }
        _ = CGWarpMouseCursorPosition(center)
    }
    private func finish(_ id: TargetID, _ generation: UInt64, _ observed: Bool, _ message: String) {
        if !observed { Trace.log.notice("Focus not confirmed: \(message, privacy: .public)") }
        Task { @MainActor [self] in
            guard current(generation, id) else { return }
            let preview = state.withValue { s -> Bool? in
                guard s.generation == generation else { return nil }
                s.expectedPID = nil
                if s.previewID == id { s.previewedID = observed ? id : nil; return true }
                // A failed selection may have left the last preview in front.
                if observed { s.previewActivationPIDs.removeAll() }
                return false
            }
            guard let preview else { return }
            if preview {
                if observed { onPreviewRaised?(id) }
                return
            }
            onOutcome?(FocusOutcome(id: id, generation: generation, observed: observed, message: message))
        }
    }
}
