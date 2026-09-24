import AppKit
import QuartzCore
import TabnaxCore

@main @MainActor struct PresenterBenchmark {
    static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let mode = DisplayMode(rawValue: CommandLine.arguments[1])!
        let count = Int(CommandLine.arguments[2])!
        let appIDs = (0..<10).map { _ in UUID() }
        let apps = appIDs.enumerated().map { index, id in
            Target(id: .init(process: id), app: "App \(index)", title: "App \(index)", address: "", foldAddress: "")
        }
        let windows = (0..<count).map { index in
            Target(id: .init(process: appIDs[index % 10], window: UUID()), app: "App \(index % 10)", title: "Window \(index) — example document", address: "", foldAddress: "", bounds: .init(x: Double(index%4)*100, y: Double(index%3)*100, width: 800, height: 600))
        }
        var selection = SelectionPreferences(); selection.alphabet = "abcdefghijklmnopqrstuvwxyz"
        var labels = LabelSession(selection: selection)
        var source = CatalogueSnapshot(windows: windows, apps: apps)
        if let id = windows.first?.id { source.history.observe(id) }
        let snapshot = labels.map(source)
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot)
        let presenter = SwitcherPresenter(); presenter.previewOnly = true
        var settings = SettingsDocument(); settings.mode = mode; settings.selection = selection; presenter.settings = settings
        let warmedAssets = CommandLine.arguments.contains("--warm-assets")
        var icons: [UUID: NSImage] = [:]
        if warmedAssets {
            for symbol in ["rectangle.on.rectangle", "gearshape", "arrow.clockwise", "hand.raised"] { _ = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            for id in appIDs { icons[id] = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app") }
        }
        let prepareStart = CACurrentMediaTime()
        if CommandLine.arguments.contains("--prepare") {
            await presenter.prepare(snapshot, icons: icons)?.value
        }
        let preparationMS = (CACurrentMediaTime()-prepareStart)*1000
        var values: [[String: Double]] = []
        for _ in 0..<12 {
            state.open()
            let start = CACurrentMediaTime()
            presenter.present(state, icons: icons, status: "")
            let presented = CACurrentMediaTime()
            presenter.embeddedView.layoutSubtreeIfNeeded()
            let laidOut = CACurrentMediaTime()
            values.append(["present_ms": (presented-start)*1000, "layout_ms": (laidOut-presented)*1000])
            state.cancel(); presenter.dismiss()
        }
        let output: [String: Any] = ["mode": mode.rawValue, "windows": count, "preparation_ms": preparationMS, "prepared": CommandLine.arguments.contains("--prepare"), "warmed_assets": warmedAssets, "samples": values, "scope": "previewOnly; present and forced layout only, no WindowServer order or physical key"]
        let data = try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
