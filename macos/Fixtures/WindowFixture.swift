import AppKit

/// Independent ground truth: the fixture reports NSWindow.isKeyWindow, not AX.
@main @MainActor final class WindowFixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow] = []
    private var sequence = 0
    private var quitRequests = 0
    private var closeRequests: [String: Int] = [:]
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = WindowFixture(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        for i in 0..<3 {
            let window = NSWindow(contentRect: NSRect(x: 140 + i * 100, y: 180 + i * 70, width: 450, height: 270),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Tabnax duplicate fixture"
            window.identifier = NSUserInterfaceItemIdentifier("fixture-\(i)"); window.setAccessibilityIdentifier("fixture-\(i)")
            window.delegate = self; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            let text = NSTextField(labelWithString: "Window \(i) · same title, separate identity")
            text.frame = NSRect(x: 25, y: 175, width: 400, height: 30)
            let input = NSTextField(frame: NSRect(x: 25, y: 115, width: 390, height: 28)); input.placeholderString = "Leak check: selection letters must not appear here"
            input.identifier = NSUserInterfaceItemIdentifier("input-\(i)")
            window.contentView?.addSubview(text); window.contentView?.addSubview(input)
            windows.append(window); window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(); report()
    }
    // Record the resulting state after AppKit finishes handling the notification.
    private func scheduleReport() { DispatchQueue.main.async { [weak self] in self?.report() } }
    func windowDidBecomeKey(_ notification: Notification) { scheduleReport() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitRequests += 1; report()
        return CommandLine.arguments.contains("--cancel-first-quit") && quitRequests == 1 ? .terminateCancel : .terminateNow
    }
    func windowDidMiniaturize(_ notification: Notification) { scheduleReport() }
    func windowDidDeminiaturize(_ notification: Notification) { scheduleReport() }
    func windowDidResize(_ notification: Notification) { scheduleReport() }
    func windowDidEnterFullScreen(_ notification: Notification) { scheduleReport() }
    func windowDidExitFullScreen(_ notification: Notification) { scheduleReport() }
    func applicationDidHide(_ notification: Notification) { scheduleReport() }
    func applicationDidUnhide(_ notification: Notification) { scheduleReport() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let id = sender.identifier?.rawValue ?? ""
        closeRequests[id, default: 0] += 1; report()
        return !(CommandLine.arguments.contains("--cancel-first-close") && closeRequests[id] == 1)
    }
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.report() }
    }
    private func report() {
        sequence += 1
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--report"), args.indices.contains(i + 1) else { return }
        let rows = windows.map { ["id": $0.identifier?.rawValue ?? "", "key": $0.isKeyWindow, "minimized": $0.isMiniaturized, "visible": $0.isVisible, "zoomed": $0.isZoomed, "fullscreen": $0.styleMask.contains(.fullScreen)] as [String: Any] }
        let value: [String: Any] = ["sequence": sequence, "windows": rows, "quitRequests": quitRequests, "closeRequests": closeRequests, "hidden": NSApp.isHidden]
        if let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: args[i + 1]), options: .atomic)
        }
    }
}
