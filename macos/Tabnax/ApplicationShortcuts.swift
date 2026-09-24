import AppKit
import UniformTypeIdentifiers
import TabnaxCore

@MainActor enum ApplicationShortcuts {
    static func resolve(_ assignment: AppAssignment) -> URL? {
        let saved = URL(fileURLWithPath: assignment.path)
        if Bundle(url: saved)?.bundleIdentifier == assignment.bundleID { return saved }
        guard let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: assignment.bundleID),
              Bundle(url: installed)?.bundleIdentifier == assignment.bundleID else { return nil }
        return installed
    }
    static func identity(at url: URL) throws -> (bundleID: String, name: String, path: String) {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier, id != Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true else {
            throw SettingsError.invalid("Choose a regular application other than Tabnax.")
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return (id, name, url.path)
    }
    static func assignment(at url: URL, letter: String) throws -> AppAssignment {
        let identity = try identity(at: url)
        return .init(bundleID: identity.bundleID, name: identity.name, path: identity.path, letter: letter)
    }
    static func includingClosedApps(_ source: CatalogueSnapshot, preferences: AppShortcutPreferences) -> CatalogueSnapshot {
        guard preferences.enabled && preferences.launchClosedApps else { return source }
        var result = source
        for app in preferences.assignments where !source.apps.contains(where: { $0.bundleID == app.bundleID }) {
            result.apps.append(Target(id: app.targetID, app: app.name, title: app.name,
                                      available: resolve(app) != nil, bundleID: app.bundleID, isRunning: false))
        }
        return result
    }
    static func icons(_ assignments: [AppAssignment], source: CatalogueSnapshot) -> [UUID: NSImage] {
        var result: [UUID: NSImage] = [:]
        for app in assignments {
            guard let url = resolve(app) else { continue }
            let icon = IconCache.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            result[app.id] = icon
            for target in source.apps where target.bundleID == app.bundleID { result[target.id.process] = icon }
        }
        return result
    }
}

/// Dispatch uses the current opt-in registry and cancels queued intents before OS submission.
/// Once Launch Services accepts an open request it cannot be retracted.
final class ApplicationLauncher: @unchecked Sendable {
    private struct State {
        var registry: [TargetID: AppAssignment] = [:]
        var generation: UInt64 = 0
    }
    private let state = Locked(State())
    var onOutcome: (@MainActor @Sendable (String) -> Void)?
    func update(_ assignments: [TargetID: AppAssignment]) { state.withValue { $0.registry = assignments } }
    func cancel() { state.withValue { $0.generation &+= 1 } }
    @discardableResult func submit(_ id: TargetID) -> Bool {
        let request = state.withValue { s -> (AppAssignment, UInt64)? in
            guard let assignment = s.registry[id] else { return nil }
            s.generation &+= 1; return (assignment, s.generation)
        }
        guard let (assignment, generation) = request else { return false }
        Task { @MainActor [self] in
            guard state.withValue({ $0.generation == generation && $0.registry[id] == assignment }) else { return }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: assignment.bundleID).first(where: { !$0.isTerminated }) {
                if running.isHidden { running.unhide() }
                if NSApp.isActive { NSApp.yieldActivation(to: running) }
                onOutcome?(running.activate(options: []) ? "Activated \(assignment.name)." : "Could not activate \(assignment.name).")
                return
            }
            guard let url = ApplicationShortcuts.resolve(assignment) else {
                onOutcome?("\(assignment.name) is unavailable. Choose the app again in Apps settings."); return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.promptsUserIfNeeded = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                guard state.withValue({ $0.generation == generation }) else { return }
                onOutcome?("Opened \(assignment.name).")
            } catch {
                guard state.withValue({ $0.generation == generation }) else { return }
                onOutcome?("Could not open \(assignment.name): \(error.localizedDescription)")
            }
        }
        return true
    }
}
