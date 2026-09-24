import AppKit
import TabnaxCore

struct ForegroundIdentity: Equatable, Sendable {
    var pid: pid_t
    var bundleID: String?
}

/// Main-actor observation/Carbon work publishes a small lock-protected decision to the tap.
/// Kept independent of a particular shortcut so additional activation routes share it.
final class ShortcutExceptionGate: @unchecked Sendable {
    private let value = Locked(false)
    var passesThrough: Bool { value.withValue { $0 } }
    func set(_ passes: Bool) { value.withValue { $0 = passes } }
}

@MainActor final class ShortcutExceptionRouter {
    let gate = ShortcutExceptionGate()
    private(set) var external: ForegroundIdentity?
    private var preferences = ExclusionPreferences()
    private var enabled = false
    private var transition = false
    private var departingPID: pid_t?
    private var observation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private let ownPID: pid_t
    private let sample: () -> ForegroundIdentity?
    private let isPreview: (pid_t) -> Bool
    private let configureFallback: (Bool) -> Void
    init(ownPID: pid_t = Foundation.ProcessInfo.processInfo.processIdentifier,
         sample: @escaping () -> ForegroundIdentity? = {
             NSWorkspace.shared.frontmostApplication.map { ForegroundIdentity(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
         }, isPreview: @escaping (pid_t) -> Bool, configureFallback: @escaping (Bool) -> Void) {
        self.ownPID = ownPID; self.sample = sample; self.isPreview = isPreview; self.configureFallback = configureFallback
    }
    func startObserving() {
        guard observation == nil else { return }
        // Observe before the first registration: a launch directly into an exception must
        // never register first and then discover the foreground application afterward.
        observation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
            // KVO has no queue contract. Carbon APIs are not thread safe; stay on main.
            if Thread.isMainThread { MainActor.assumeIsolated { self?.refresh() } }
            else { Task { @MainActor in self?.refresh() } }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didDeactivateApplicationNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let name = note.name
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWorkspace.didDeactivateApplicationNotification {
                        // Release conservatively at the beginning of an activation transition.
                        // Never trust a queued notification's app as the new foreground app.
                        self.beginTransition(from: pid)
                        DispatchQueue.main.async { [weak self] in self?.refresh() }
                    } else if name == NSWorkspace.didActivateApplicationNotification { self.activationCompleted(for: pid) }
                    else { self.refresh() }
                }
            })
        }
        refresh()
    }
    func configure(_ preferences: ExclusionPreferences, enabled: Bool) {
        self.preferences = preferences; self.enabled = enabled
        refresh()
    }
    /// Resample instead of trusting notification payloads, which can arrive out of order.
    func refresh(acceptPreview: Bool = false) {
        observe(sample(), acceptPreview: acceptPreview)
        // The app can activate during RegisterEventHotKey. Reconcile once more before
        // returning, and let KVO/activation notifications handle subsequent transitions.
        let after = sample()
        if after != lastSample { observe(after, acceptPreview: acceptPreview) }
    }
    /// An activation can be cancelled and return to the same app. Its completion ends
    /// the conservative deactivation suspension even though the PID never changed.
    func activationCompleted(for pid: pid_t?) {
        if let pid, sample()?.pid == pid { departingPID = nil }
        refresh()
    }
    func beginTransition(from pid: pid_t?) {
        // A delayed deactivation for an older app cannot suspend the new foreground app.
        guard pid == nil || sample()?.pid == pid else { refresh(); return }
        departingPID = pid; transition = true; publish()
    }
    private var lastSample: ForegroundIdentity?
    private func observe(_ current: ForegroundIdentity?, acceptPreview: Bool) {
        lastSample = current
        if let departingPID, current?.pid != departingPID { self.departingPID = nil }
        transition = current == nil || departingPID != nil
        if let current, current.pid != ownPID, acceptPreview || !isPreview(current.pid) { external = current }
        publish()
    }
    private func publish() {
        // With no exceptions configured there is no need to suspend during transitions.
        let pass = preferences.passesActivationShortcuts(to: external?.bundleID)
            || (transition && !preferences.shortcutExceptions.isEmpty)
        gate.set(pass)
        configureFallback(enabled && !pass)
    }
    /// Called again at dispatch: stale queued Carbon callbacks must not open an overlay.
    func permitsActivation() -> Bool { refresh(); return enabled && !gate.passesThrough }
}
