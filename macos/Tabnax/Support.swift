import AppKit
import ApplicationServices
import TabnaxCore
import os
import Combine
import ServiceManagement
import CoreServices

/// The system owns login-item state; the saved preference records successful requests.
@MainActor struct LoginItemService {
    var status: () -> SMAppService.Status = { SMAppService.mainApp.status }
    var register: () throws -> Void = { try SMAppService.mainApp.register() }
    var unregister: () throws -> Void = { try SMAppService.mainApp.unregister() }
    var repairRegistration: () throws -> Void = {
        let result = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        guard result == noErr else { throw NSError(domain:NSOSStatusErrorDomain,code:Int(result)) }
    }

    func setEnabled(_ enabled: Bool) throws {
        let current = status()
        if enabled {
            if current == .enabled || current == .requiresApproval { return }
            // Development bundles can be replaced at the same path. Refresh their
            // Launch Services record before asking Service Management to find them.
            if current == .notFound { try repairRegistration() }
            do { try register() }
            catch {
                // macOS may report denial while retaining an approval-pending item.
                guard status() == .requiresApproval else { throw error }
            }
            guard status() == .enabled || status() == .requiresApproval else {
                throw SettingsError.invalid("macOS could not enable Launch at login. Check Login Items in System Settings, then retry. If this copy was moved or rebuilt, reopen it from its current location when convenient.")
            }
        } else {
            if current == .notRegistered || current == .notFound { return }
            try unregister()
            guard status() == .notRegistered || status() == .notFound else {
                throw SettingsError.invalid("macOS has not disabled Launch at login. Check Login Items in System Settings, then retry.")
            }
        }
    }
}

/// Only immutable values cross the AX/input/UI boundaries. Mutable storage below
/// is always protected by this lock; no caller performs IPC inside withValue.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body(&value)
    }
}
/// NSWorkspace icon lookups decode/render an icon on every call; Settings UI can
/// otherwise trigger this repeatedly per keystroke (refreshPreview, view bodies).
/// All call sites are already main-thread Settings/UI code.
@MainActor enum IconCache {
    private static var cache: [String: NSImage] = [:]
    static func icon(forFile path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
enum Trace {
    static let log = Logger(subsystem: "pl.tabnax.Tabnax", category: "health")
    static let signposter = OSSignposter(subsystem: "pl.tabnax.Tabnax", category: .pointsOfInterest)
}
struct Shortcut: Sendable, Equatable {
    var keyCode: UInt16 = 49 // Space, deliberately requires two modifiers.
    var modifiers: CGEventFlags = [.maskControl, .maskAlternate]
    static let choices: [(String, Shortcut)] = [
        ("⌃⌥ Space", Shortcut()),
        ("⌃⇧ Space", Shortcut(modifiers: [.maskControl, .maskShift])),
        ("⌥⇧ Space", Shortcut(modifiers: [.maskAlternate, .maskShift]))
    ]
    static let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
}
@MainActor final class Preferences: ObservableObject {
    @Published private(set) var document: SettingsDocument
    @Published private(set) var message = "Changes are saved automatically."
    @Published private(set) var canUndo = false
    private let defaults: UserDefaults
    @Published private(set) var searchMemory: SearchMemory?
    var onSearchMemoryChange: ((SearchMemory?) -> Void)?
    static let searchMemoryKey = "searchChoices.v1"
    func clearSearchChoices() {
        searchMemory = document.rememberSearchChoices ? SearchMemory() : nil
        defaults.removeObject(forKey: Self.searchMemoryKey)
        onSearchMemoryChange?(searchMemory)
        message = "Remembered search choices cleared."
    }
    func saveSearchChoices(_ memory: SearchMemory) {
        // A delayed selection callback cannot repopulate memory after Clear/off/reset.
        guard !readOnly, document.rememberSearchChoices, let current = searchMemory, current.salt == memory.salt,
              memory.revision >= current.revision else { return }
        guard let data = try? JSONEncoder().encode(memory) else { return }
        searchMemory = memory; defaults.set(data, forKey: Self.searchMemoryKey)
    }
    private func applySearchConsent() {
        if document.rememberSearchChoices {
            if searchMemory == nil { searchMemory = SearchMemory() }
        } else {
            searchMemory = nil; defaults.removeObject(forKey: Self.searchMemoryKey)
        }
        onSearchMemoryChange?(searchMemory)
    }
    private var undoStack: [(SettingsDocument, (() -> Void)?)] = []
    private(set) var readOnly = false
    var onChange: ((SettingsDocument, SettingsDocument) -> Void)?
    var prepareCommit: ((SettingsDocument, SettingsDocument) throws -> Void)?
    var captureRuntime: (() -> (() -> Void))?
    var mode: DisplayMode { document.mode }
    var alphabet: String { document.selection.alphabet }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var value = SettingsDocument()
        var loadError: String?
        if let data = defaults.data(forKey:"settingsDocument.v1") {
            do { value = try JSONDecoder().decode(SettingsDocument.self,from:data).validated() }
            catch { loadError = error.localizedDescription; readOnly = true }
        } else {
            value.mode = DisplayMode(rawValue:defaults.string(forKey:"displayMode") ?? "") ?? .shore
            if let saved = defaults.string(forKey:"alphabet"), (try? AddressBook(alphabet:saved)) != nil {
                value.selection.alphabet = saved
                let hand = [HandPreset.right,.left,.both].first { $0.alphabet == saved }
                value.selection.hand = hand ?? .custom; value.selection.baseHand = hand ?? (saved == "asdfwercvq" ? .left : .right)
            }
            let index = min(2,max(0,defaults.integer(forKey:"shortcut")))
            value.activation.modifiers = Shortcut.choices[index].1.modifiers.rawValue
        }
        document = value
        if value.rememberSearchChoices && !readOnly {
            let data = defaults.data(forKey: Self.searchMemoryKey)
            // Reject unexpectedly large/corrupt state independently of settings.
            if let data, data.count <= 64_000, let decoded = try? JSONDecoder().decode(SearchMemory.self, from: data) {
                searchMemory = decoded
                if let bounded = try? JSONEncoder().encode(decoded) { defaults.set(bounded, forKey: Self.searchMemoryKey) }
            } else {
                searchMemory = SearchMemory(); defaults.removeObject(forKey: Self.searchMemoryKey)
            }
        } else if !readOnly { defaults.removeObject(forKey: Self.searchMemoryKey) }
        if let loadError { message = loadError + " Saved data is preserved; settings are read-only." }
    }
    @discardableResult func commit(_ candidate: SettingsDocument, message: String = "Saved", forceCheckpoint: Bool = false) -> Bool {
        guard !readOnly else { return false }
        do {
            let checked = try candidate.validated()
            if checked == document && !forceCheckpoint { return true }
            let data = try JSONEncoder().encode(checked)
            let old = document
            try prepareCommit?(checked,old)
            undoStack.append((old,captureRuntime?())); if undoStack.count > 20 { undoStack.removeFirst() }
            defaults.set(data,forKey:"settingsDocument.v1")
            document = checked; canUndo = true; self.message = message
            applySearchConsent()
            onChange?(checked,old)
            return true
        } catch { self.message = error.localizedDescription; return false }
    }
    func undo() {
        guard !readOnly, let (old,restore) = undoStack.last, let data = try? JSONEncoder().encode(old) else { return }
        do { try prepareCommit?(old,document) } catch { message = error.localizedDescription; return }
        undoStack.removeLast()
        let current = document; defaults.set(data,forKey:"settingsDocument.v1"); document = old
        applySearchConsent()
        onChange?(old,current); restore?(); canUndo = !undoStack.isEmpty
        message = "Undone. Labels restored for identities still present."
    }
    func report(_ value: String) { message = value }
}

/// AX handles are immutable after their timeout has been configured. Public AX
/// calls may overlap between bounded discovery and focus lanes; timeout settings
/// are never changed on a shared handle. CFEqual is used only within a lifetime.
final class AXHandle: @unchecked Sendable {
    let element: AXUIElement
    convenience init(_ element: AXUIElement) { self.init(element, timeout: 0.08) }
    init(_ element: AXUIElement, timeout: Float) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, timeout)
    }
}
struct ProcessInfo: Sendable {
    let token: UUID
    let pid: pid_t
    let name: String
    let app: AXHandle
    /// A second handle on the same app for the focus lane. Discovery keeps its short timeout so
    /// a busy app cannot stall the catalogue; confirming a switch the user asked for can wait
    /// a little longer for that same busy app to answer.
    let focusApp: AXHandle
    let launchDate: Date?
    init(token: UUID, pid: pid_t, name: String, app: AXHandle, launchDate: Date? = nil) {
        self.token = token; self.pid = pid; self.name = name; self.app = app; self.launchDate = launchDate
        focusApp = AXHandle(AXUIElementCreateApplication(pid), timeout: 0.25)
    }
}
struct WindowRecord: Sendable {
    let id: TargetID
    let handle: AXHandle
    var title: String
    var minimized: Bool
    var available: Bool
    var bounds: CGRect? = nil
    /// Still answering, but absent from its app's window list: on another Space or full screen.
    var elsewhere = false
}
func axValue(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
    let interval = Trace.signposter.beginInterval("axCall")
    defer { Trace.signposter.endInterval("axCall", interval) }
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return (error, value)
}
func axElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}
