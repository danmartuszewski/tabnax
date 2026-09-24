import Foundation

@inline(never) func opening(_ state: inout SelectionState, snapshot: CatalogueSnapshot, update: Bool) -> Int {
    if update { state.update(snapshot) }
    let found = state.open()
    return state.targets.count + state.cursor + (found ? 1 : 0)
}

@main struct Bench {
    static func main() {
        var checksum = 0
        print("mode,targets,path,p50_ms,p95_ms")
        for count in [20, 100, 500] {
            let owners = (0..<min(20, max(2, count / 5))).map { _ in UUID() }
            let apps = owners.enumerated().map { index, owner in Target(id: TargetID(process: owner), app: "App \(index)", title: "App \(index)") }
            let windows = (0..<count).map { i in
                Target(id: TargetID(process: owners[i % owners.count], window: UUID()), app: "App \(i % owners.count)", title: "Window \(i)", bounds: CGRect(x: i % 3 * 400, y: i % 5 * 160, width: 500, height: 400), onScreen: i < 10)
            }
            var history = FocusHistory()
            history.observe(windows[1].id); history.observe(windows[0].id)
            var selection = SelectionPreferences(); selection.alphabet = "abcdefghijklmnopqrstuvwxyz"; selection.policy = .stable
            var labels = LabelSession(selection: selection)
            let snapshot = labels.map(CatalogueSnapshot(revision: 1, windows: windows, apps: apps, history: history))
            for mode in DisplayMode.allCases {
                for update in [true, false] {
                    var state = SelectionState(); state.configure(mode: mode); state.update(snapshot)
                    var samples: [Double] = []
                    for i in 0..<90 {
                        state.cancel()
                        let start = DispatchTime.now().uptimeNanoseconds
                        checksum &+= opening(&state, snapshot: snapshot, update: update)
                        let elapsed = DispatchTime.now().uptimeNanoseconds - start
                        if i >= 10 { samples.append(Double(elapsed) / 1_000_000) }
                    }
                    samples.sort()
                    let row = [mode.rawValue, "\(count)", update ? "update_then_open" : "open_only", String(format: "%.4f", samples[samples.count/2]), String(format: "%.4f", samples[Int(Double(samples.count-1)*0.95)])]
                    print(row.joined(separator: ","))
                }
            }
        }
        print("checksum=\(checksum)")
    }
}
