import AppKit
import ApplicationServices
import TabnaxCore

/// One definition drives native menu hints and both keyboard input paths.
struct WindowActionShortcut {
    let keyCode: UInt16
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
    let label: String

    func matches(code: UInt16, flags: CGEventFlags, activation: CGEventFlags) -> Bool {
        let required = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        return code == keyCode && flags.contains(required)
            && flags.intersection(Shortcut.relevant).subtracting(activation.union(required)).isEmpty
    }

    static func action(code: UInt16, flags: CGEventFlags, activation: CGEventFlags) -> SwitcherAction? {
        // Hide and unhide share a chord; resolve the live variant from the target/menu.
        SwitcherAction.allCases.first { $0 != .unhideApplication && $0.shortcut.matches(code: code, flags: flags, activation: activation) }
    }
}

extension SwitcherAction {
    var shortcut: WindowActionShortcut {
        switch self {
        case .closeWindow: .init(keyCode: 13, keyEquivalent: "w", modifiers: .command, label: "⌘W")
        case .minimizeWindow: .init(keyCode: 46, keyEquivalent: "m", modifiers: .command, label: "⌘M")
        case .restoreWindow: .init(keyCode: 15, keyEquivalent: "r", modifiers: .command, label: "⌘R")
        case .hideApplication, .unhideApplication: .init(keyCode: 4, keyEquivalent: "h", modifiers: .command, label: "⌘H")
        case .zoomWindow: .init(keyCode: 6, keyEquivalent: "z", modifiers: [.control, .command], label: "⌃⌘Z")
        case .toggleFullscreen: .init(keyCode: 3, keyEquivalent: "f", modifiers: [.control, .command], label: "⌃⌘F")
        case .quitApplication: .init(keyCode: 12, keyEquivalent: "q", modifiers: .command, label: "⌘Q")
        }
    }
}

extension NSMenu {
    /// Use the captured command, including its capability check, while tracking.
    /// Disabled shortcuts are handled without falling through to the app/search editor.
    @MainActor func performWindowActionShortcut(_ action: SwitcherAction) {
        let variants: [SwitcherAction] = action == .hideApplication ? [.hideApplication, .unhideApplication] : [action]
        guard let index = items.firstIndex(where: { item in variants.contains { item.identifier?.rawValue == "action-\($0.rawValue)" } }),
              items[index].isEnabled else { return }
        cancelTracking()
        performActionForItem(at: index)
    }
}

/// All access is bound to one already-identified AX window. The injectable boundary also
/// lets tests verify unsupported controls and live state changes without OS permissions.
struct WindowActionAccess {
    var minimized: () -> Bool?
    var canSetMinimized: () -> Bool
    var canPress: (String) -> Bool
    var setMinimized: (Bool) -> AXError
    var press: (String) -> AXError

    init(window: AXUIElement) {
        minimized = { axValue(window, kAXMinimizedAttribute).1 as? Bool }
        canSetMinimized = {
            var settable = DarwinBoolean(false)
            return AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
        }
        func button(_ attribute: String) -> AXUIElement? {
            guard let button = axElement(axValue(window, attribute).1),
                  axValue(button, kAXEnabledAttribute).1 as? Bool == true else { return nil }
            var actions: CFArray?
            guard AXUIElementCopyActionNames(button, &actions) == .success,
                  (actions as? [String])?.contains(kAXPressAction) == true else { return nil }
            return button
        }
        canPress = { button($0) != nil }
        setMinimized = { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, $0 ? kCFBooleanTrue : kCFBooleanFalse) }
        press = { attribute in
            guard let button = button(attribute) else { return .actionUnsupported }
            return AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }
    init(minimized: @escaping () -> Bool?, canSetMinimized: @escaping () -> Bool,
         canPress: @escaping (String) -> Bool, setMinimized: @escaping (Bool) -> AXError,
         press: @escaping (String) -> AXError) {
        self.minimized = minimized; self.canSetMinimized = canSetMinimized
        self.canPress = canPress; self.setMinimized = setMinimized; self.press = press
    }
    func disabledReason(for action: SwitcherAction, hidden: Bool) -> String? {
        switch action {
        case .minimizeWindow, .restoreWindow:
            guard let minimized = minimized() else { return "Window state is unavailable" }
            if action == .minimizeWindow && minimized { return "Window is already minimized" }
            if action == .restoreWindow && !minimized { return "Window is already restored" }
            return canSetMinimized() ? nil : "App does not support changing minimized state"
        case .closeWindow: return canPress(kAXCloseButtonAttribute) ? nil : "Window has no enabled close control"
        case .zoomWindow, .toggleFullscreen:
            if hidden { return "Unhide the app first" }
            guard let minimized = minimized() else { return "Window state is unavailable" }
            if minimized { return "Restore the window first" }
            let attribute = action == .zoomWindow ? kAXZoomButtonAttribute : kAXFullScreenButtonAttribute
            return canPress(attribute) ? nil : (action == .zoomWindow ? "Window has no enabled zoom control" : "Window has no enabled full-screen control")
        default: return "Highlight an individual window"
        }
    }
    func perform(_ action: SwitcherAction, hidden: Bool) -> (Bool, String) {
        // Restore remains idempotent for the existing Option shortcut.
        if action == .restoreWindow && minimized() == false { return (true, "Window already restored.") }
        guard let reason = disabledReason(for: action, hidden: hidden) else {
            let error: AXError
            switch action {
            case .restoreWindow: error = setMinimized(false)
            case .minimizeWindow: error = setMinimized(true)
            case .closeWindow: error = press(kAXCloseButtonAttribute)
            case .zoomWindow: error = press(kAXZoomButtonAttribute)
            case .toggleFullscreen: error = press(kAXFullScreenButtonAttribute)
            default: return (false, "Unsupported window action.")
            }
            return error == .success ? (true, "\(action.title) requested. The app may ask for confirmation.")
                : (false, "\(action.title) failed (AX \(error.rawValue)).")
        }
        return (false, reason)
    }
}

/// NSMenu retains these through representedObject; requests carry frozen target IDs.
@MainActor final class SwitcherMenuCommand: NSObject {
    let invoke: () -> Void
    init(_ invoke: @escaping () -> Void) { self.invoke = invoke }
    @objc func invokeAction(_ sender: Any?) { invoke() }
}
