#if DEBUG
import AppKit
import Darwin
import ApplicationServices
import TabnaxCore

/// Development-only, opt-in fixture verification. No TCC mutation or event posting.
/// The fixture's independent NSWindow report is the success ground truth.
@MainActor enum VerificationHarness {
    /// Selects only this app's Settings through the real router and focus coordinator.
    /// Unlike a UI driver, this also reproduces the race with panel dismissal reliably.
    static func runOwnSelection(window: NSWindow, outputPath: String,
                                snapshot: () -> CatalogueSnapshot, refresh: () -> Void,
                                open: () -> Void, choose: (TargetID) -> Void) async {
        var results: [[String: Any]] = []
        for attempt in 0..<10 {
            window.makeKeyAndOrderFront(nil)
            refresh()
            try? await Task.sleep(for: .seconds(2))
            guard let target = snapshot().windows.first(where: { $0.app == "Tabnax" && $0.title == window.title }) else {
                results.append(["attempt": attempt, "passed": false, "reason": "Settings missing from catalogue"])
                break
            }
            open()
            try? await Task.sleep(for: .milliseconds(300))
            choose(target.id)
            try? await Task.sleep(for: .seconds(1))
            results.append(["attempt": attempt, "passed": window.isKeyWindow && window.isVisible,
                            "keyWindow": window.isKeyWindow, "visible": window.isVisible])
        }
        let passed = results.count == 10 && results.allSatisfy { $0["passed"] as? Bool == true }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["passed": passed, "results": results], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        } catch { print("Own selection report failed: \(error)"); exit(1) }
        exit(passed ? 0 : 1)
    }
    static func run(fixturePath: String, outputPath: String) async {
        var results: [[String: Any]] = []
        let trusted = AXIsProcessTrusted()
        defer {
            let result: [String: Any] = ["accessibilityTrusted": trusted, "launchContext": "direct executable", "results": results]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: outputPath)); print(String(decoding: data, as: UTF8.self))
            }
            Darwin.exit(trusted && !results.isEmpty && results.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
        }
        guard trusted else { results.append(["name": "exact focus", "status": "skipped: Accessibility unavailable"]); return }
        let report = FileManager.default.temporaryDirectory.appendingPathComponent("tabnax-ground-truth-\(UUID()).json")
        let fixture = Process(); fixture.executableURL = URL(fileURLWithPath: fixturePath); fixture.arguments = ["--report", report.path]
        do { try fixture.run() } catch { results.append(["error": error.localizedDescription]); return }
        defer { if fixture.isRunning { fixture.terminate() }; try? FileManager.default.removeItem(at: report) }
        for _ in 0..<60 {
            if let data = try? Data(contentsOf: report),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["windows"] as? [[String: Any]], rows.count == 3 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let app = AXHandle(AXUIElementCreateApplication(fixture.processIdentifier))
        let windows: [AXHandle] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let (_, value) = axValue(app.element, kAXWindowsAttribute)
                continuation.resume(returning: (value as? [AXUIElement] ?? []).map(AXHandle.init))
            }
        }
        results.append(["name": "three duplicate-title windows discovered", "passed": windows.count == 3, "count": windows.count])
        guard windows.count == 3 else { return }
        var identified: [String: AXHandle] = [:]
        for window in windows {
            let identifier: String? = await withCheckedContinuation { continuation in
                DispatchQueue.global().async { continuation.resume(returning: axValue(window.element, kAXIdentifierAttribute).1 as? String) }
            }
            if let identifier { identified[identifier] = window }
        }
        let info = ProcessInfo(token: UUID(), pid: fixture.processIdentifier, name: "Tabnax fixture", app: app,
                               launchDate: NSRunningApplication(processIdentifier: fixture.processIdentifier)?.launchDate)
        let focus = FocusCoordinator()
        let ids = (0..<3).map { _ in TargetID(process: info.token, window: UUID()) }
        func registry(minimized: Int? = nil) -> [TargetID: FocusTarget] {
            var values: [TargetID: FocusTarget] = [:]
            for i in 0..<3 {
                if let handle = identified["fixture-\(i)"] {
                    values[ids[i]] = FocusTarget(process: info, window: WindowRecord(id: ids[i], handle: handle,
                        title: "Tabnax duplicate fixture", minimized: minimized == i, available: true))
                }
            }
            return values
        }
        focus.update(registry())
        // Cover an exact fixture window with a different process's normal window.
        // Check window-server stacking, rather than inferring visibility from AX success.
        if let target = identified["fixture-0"] {
            let frame: CGRect? = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    let (_, p) = axValue(target.element, kAXPositionAttribute)
                    let (_, s) = axValue(target.element, kAXSizeAttribute)
                    var point = CGPoint.zero; var size = CGSize.zero
                    guard let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
                          AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else {
                        continuation.resume(returning: nil); return
                    }
                    continuation.resume(returning: CGRect(origin: point, size: size))
                }
            }
            if let frame {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let cover = NSWindow(contentRect: CGRect(x: frame.minX, y: top-frame.maxY, width: frame.width, height: frame.height),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
                cover.isReleasedWhenClosed = false; cover.backgroundColor = .darkGray
                cover.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(100))
                func fixtureIsAboveCover() -> Bool? {
                    guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
                          let coverIndex = rows.firstIndex(where: { ($0[kCGWindowNumber as String] as? Int) == cover.windowNumber }),
                          let fixtureIndex = rows.firstIndex(where: { row in
                              guard row[kCGWindowOwnerPID as String] as? Int32 == fixture.processIdentifier,
                                    let raw = row[kCGWindowBounds as String] as? NSDictionary,
                                    let rect = CGRect(dictionaryRepresentation: raw) else { return false }
                              return abs(rect.minX-frame.minX) < 2 && abs(rect.minY-frame.minY) < 2 && abs(rect.width-frame.width) < 2 && abs(rect.height-frame.height) < 2
                          }) else { return nil }
                    return fixtureIndex < coverIndex
                }
                let coveredBefore = fixtureIsAboveCover() == false
                var raised = false
                var dismissed = false, committed = false
                focus.onWillActivate = { dismissed = true }
                focus.onOutcome = { _ in committed = true }
                focus.onPreviewRaised = { id in raised = id == ids[0] }
                focus.preview(ids[0])
                for _ in 0..<40 {
                    if raised && fixtureIsAboveCover() == true { break }
                    try? await Task.sleep(for: .milliseconds(25))
                }
                results.append(["name": "highlight raises exact window above another app",
                                "passed": coveredBefore && raised && fixtureIsAboveCover() == true && !dismissed && !committed,
                                "coveredBefore": coveredBefore, "raised": raised, "aboveCover": fixtureIsAboveCover() == true,
                                "switcherDismissed": dismissed, "selectionCommitted": committed])
                focus.cancel(); focus.onPreviewRaised = nil; focus.onWillActivate = nil; focus.onOutcome = nil; cover.close()
            } else { results.append(["name": "preview fixture geometry", "passed": false]) }
        }
        func groundTruth() -> String? {
            guard let data = try? Data(contentsOf: report), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let windows = json["windows"] as? [[String: Any]] else { return nil }
            return windows.first { $0["key"] as? Bool == true }?["id"] as? String
        }
        func select(_ index: Int, name: String) async {
            let start = ContinuousClock.now
            var observation: FocusOutcome?
            focus.onOutcome = { observation = $0 }
            focus.submit(ids[index])
            for _ in 0..<50 {
                if observation != nil { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            for _ in 0..<10 {
                if groundTruth() == "fixture-\(index)" { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let duration = start.duration(to: .now)
            let milliseconds = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
            results.append(["name": name, "passed": observation?.observed == true && groundTruth() == "fixture-\(index)",
                            "AXObserved": observation?.observed ?? false, "fixtureKeyWindow": groundTruth() ?? "none",
                            "sampleElapsedMilliseconds": milliseconds, "message": observation?.message ?? "No result before fixture deadline"])
        }
        for i in [0, 1, 2, 0, 2, 1] { await select(i, name: "same-app exact window \(i)") }
        if let window = identified["fixture-0"] {
            let error: AXError = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(returning: AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue))
                }
            }
            if error == .success { focus.update(registry(minimized: 0)); await select(0, name: "minimized restoration") }
            else { results.append(["name": "minimized fixture setup", "AXError": error.rawValue]) }
        }
        focus.update(registry())
        _ = NSRunningApplication(processIdentifier: fixture.processIdentifier)?.hide()
        await select(1, name: "hidden application restoration")
        focus.cancel()
        // Exercise the production event-driven catalogue, confined to this fixture.
        let catalogue = WindowCatalogue(alphabet: AddressBook.rightHand, includeProcess: { $0.processIdentifier == fixture.processIdentifier })
        var catalogueRegistry: [TargetID: FocusTarget] = [:]
        catalogue.onChange = { _, registry in catalogueRegistry = registry }
        func catalogueID(_ index: Int) -> TargetID? {
            guard let expected = identified["fixture-\(index)"] else { return nil }
            return catalogueRegistry.first { _, target in target.window.map { CFEqual($0.handle.element, expected.element) } ?? false }?.key
        }
        catalogue.setMode(.beacons)
        catalogue.start()
        for _ in 0..<50 {
            if catalogue.snapshot.windows.count == 3 { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        let before = Dictionary(uniqueKeysWithValues: catalogue.snapshot.windows.map { ($0.id, $0.address) })
        results.append(["name": "production catalogue admitted three windows", "passed": before.count == 3])
        let foldBefore = Dictionary(uniqueKeysWithValues: catalogue.snapshot.windows.map { ($0.id, $0.foldAddress) })
        results.append(["name": "Fold production addresses include app and local window stages", "passed": foldBefore.count == 3 && foldBefore.values.allSatisfy { $0.count >= 2 } && Set(foldBefore.values).count == 3])
        results.append(["name": "Beacons obtains native AX bounds without screen capture", "passed": catalogue.snapshot.windows.count == 3 && catalogue.snapshot.windows.allSatisfy { $0.bounds != nil }])
        catalogue.refresh()
        try? await Task.sleep(for: .milliseconds(200))
        let after = Dictionary(uniqueKeysWithValues: catalogue.snapshot.windows.map { ($0.id, $0.address) })
        results.append(["name": "AX reconciliation preserved live addresses", "passed": before == after && before.count == 3])
        await select(0, name: "focus while catalogue is observing")
        for _ in 0..<40 {
            if catalogue.snapshot.history.current == catalogueID(0) { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        results.append(["name": "Relay observes focus performed outside its router", "passed": catalogueID(0) != nil && catalogue.snapshot.history.current == catalogueID(0) && catalogue.snapshot.history.previous == catalogueID(1)])
        for mode in DisplayMode.allCases { catalogue.setMode(mode) }
        catalogue.refresh()
        try? await Task.sleep(for: .milliseconds(250))
        results.append(["name": "All six mode changes preserve flat and Fold addresses", "passed": catalogue.snapshot.windows.count == 3 && catalogue.snapshot.windows.allSatisfy { before[$0.id] == $0.address && foldBefore[$0.id] == $0.foldAddress }])
        if let window = identified["fixture-0"] {
            let closed: Bool = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    let (_, value) = axValue(window.element, kAXCloseButtonAttribute)
                    guard let button = axElement(value) else { continuation.resume(returning: false); return }
                    let handle = AXHandle(button)
                    continuation.resume(returning: AXUIElementPerformAction(handle.element, kAXPressAction as CFString) == .success)
                }
            }
            for _ in 0..<40 {
                if catalogue.snapshot.windows.count == 2 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            let survivors = catalogue.snapshot.windows
            results.append(["name": "Invalid AX handle retired only the closed window", "passed": closed && survivors.count == 2 && survivors.allSatisfy { before[$0.id] == $0.address }, "closeActionSucceeded": closed, "remaining": survivors.count, "unavailable": survivors.filter { !$0.available }.count, "notifications": catalogue.notificationCounts])
        }
        await select(2, name: "remaining window stays focusable")
        if let window = identified["fixture-1"] {
            let closed: Bool = await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    let (_, value) = axValue(window.element, kAXCloseButtonAttribute)
                    guard let button = axElement(value) else { continuation.resume(returning: false); return }
                    let handle = AXHandle(button)
                    continuation.resume(returning: AXUIElementPerformAction(handle.element, kAXPressAction as CFString) == .success)
                }
            }
            // AXPress acceptance can precede AppKit closing the window. Wait for
            // independent fixture evidence before testing subsequent reconciliation.
            for _ in 0..<40 {
                if let data = try? Data(contentsOf: report), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let states = json["windows"] as? [[String: Any]],
                   states.first(where: { $0["id"] as? String == "fixture-1" })?["visible"] as? Bool == false { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            catalogue.refresh() // The same explicit reconciliation used after activation.
            for _ in 0..<40 {
                if catalogue.snapshot.windows.count == 1 { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
            results.append(["name": "background close reconciled without a destruction notification", "passed": closed && catalogue.snapshot.windows.count == 1 && catalogue.snapshot.windows.allSatisfy { before[$0.id] == $0.address }, "closeActionSucceeded": closed, "remaining": catalogue.snapshot.windows.count])
        }
        catalogue.stop()
        // Creation alone is a capability check, not a physical-key/no-leak test.
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                   eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }, userInfo: nil)
        results.append(["name": "consuming event tap creation under existing AX access", "passed": tap != nil])
        if let tap { CFMachPortInvalidate(tap) }
    }
}
#endif
