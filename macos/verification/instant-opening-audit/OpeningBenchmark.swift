import AppKit
import QuartzCore
import TabnaxCore

@MainActor enum OpeningAudit {
    static var stages: [String: Double] = [:]
    static var rowConstructions = 0
    static var frameSizes: [[Double]] = []
}

@main @MainActor struct OpeningBenchmark {
    static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        let mode = DisplayMode(rawValue: args[1])!
        let count = Int(args[2])!
        let appIDs = (0..<10).map { _ in UUID() }
        let apps = appIDs.enumerated().map { index, id in
            Target(id: .init(process: id), app: "App \(index)", title: "App \(index)")
        }
        let windows = (0..<count).map { index in
            Target(id: .init(process: appIDs[index % 10], window: UUID()), app: "App \(index % 10)", title: "Window \(index) — example document", bounds: .init(x: Double(index%4)*100, y: Double(index%3)*100, width: 800, height: 600))
        }
        var selection = SelectionPreferences(); selection.alphabet = "abcdefghijklmnopqrstuvwxyz"
        var labels = LabelSession(selection: selection)
        var source = CatalogueSnapshot(windows: windows, apps: apps)
        source.history.observe(windows[1].id); source.history.observe(windows[0].id)
        var snapshot = labels.map(source)
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot)
        let presenter = SwitcherPresenter(); presenter.previewOnly = true
        var settings = SettingsDocument(); settings.mode = mode; settings.selection = selection
        settings.appearance.preset = args.contains("--glass") ? .liquidGlass : .graphite; settings.appearance.source = .dark
        presenter.settings = settings
        var icons: [UUID: NSImage] = [:]
        for symbol in ["rectangle.on.rectangle", "gearshape", "arrow.clockwise", "hand.raised"] { _ = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        for id in appIDs { icons[id] = NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app") }
        let beforePreparation = CACurrentMediaTime()
        if args.contains("--prepare") { await presenter.prepare(snapshot, icons: icons)?.value }
        // Laboratory approximation of a fully prepared scene, NOT a safe production prewarm API.
        // previewOnly prevents window ordering, but present() still has session/monitor side effects.
        if args.contains("--prime-scene") {
            state.open(); presenter.present(state, icons: icons, status: "")
            presenter.embeddedView.layoutSubtreeIfNeeded()
            state.cancel(); presenter.dismiss()
        }
        if args.contains("--churn") {
            for index in 0..<12 {
                snapshot.windows[0].title = "Changing title \(index)"
                presenter.prepare(snapshot, icons: icons)
                try? await Task.sleep(for: .milliseconds(16))
            }
            state.update(snapshot)
        }
        let preparationMS = (CACurrentMediaTime()-beforePreparation)*1000
        let rowsPrepared = OpeningAudit.rowConstructions
        var samples: [[String: Any]] = []
        for iteration in 0..<12 {
            if iteration > 0, args.contains("--prepare-between") { await presenter.prepare(snapshot, icons: icons)?.value }
            state.open()
            let beforeRows = OpeningAudit.rowConstructions
            let start = CACurrentMediaTime()
            presenter.present(state, icons: icons, status: "")
            let presented = CACurrentMediaTime()
            presenter.embeddedView.layoutSubtreeIfNeeded()
            let laidOut = CACurrentMediaTime()
            var drawMS = 0.0
            if args.contains("--draw") {
                let view = presenter.embeddedView
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    let beforeDraw = CACurrentMediaTime()
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    drawMS = (CACurrentMediaTime()-beforeDraw)*1000
                }
            }
            func countViews(_ view: NSView) -> Int { 1 + view.subviews.reduce(0) { $0 + countViews($1) } }
            samples.append(["present_ms": (presented-start)*1000, "layout_ms": (laidOut-presented)*1000,
                            "draw_ms": drawMS, "stages_ms": OpeningAudit.stages,
                            "new_rows": OpeningAudit.rowConstructions-beforeRows, "frame_sizes": OpeningAudit.frameSizes, "views": countViews(presenter.embeddedView)])
            state.cancel(); presenter.dismiss()
        }
        let output: [String: Any] = ["mode": mode.rawValue, "windows": count, "preparation_ms": preparationMS,
                                    "rows_prepared": rowsPrepared, "arguments": Array(args.dropFirst()), "samples": samples,
                                    "scope": "Optimized synthetic AppKit fixture; previewOnly, no panel ordering, AX, input tap or compositor. Optional bitmap drawing is offscreen CPU rendering, not visible-frame evidence."]
        print(String(data: try! JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
