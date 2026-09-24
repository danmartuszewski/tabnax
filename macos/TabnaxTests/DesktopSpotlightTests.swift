import AppKit
import ApplicationServices
import QuartzCore
import XCTest
import TabnaxCore
@testable import Tabnax

final class DesktopSpotlightTests: XCTestCase {
    @MainActor func testSwitcherOnlyDimsEveryDisplayWithoutAWindowTargetOrCutout() throws {
        let spotlight = DesktopSpotlight(); defer { spotlight.dismiss() }
        var preferences = DesktopSpotlightPreferences(); preferences.mode = .switcherOnly
        let screens = [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: -800, y: 0, width: 800, height: 600)]
        var state = opened(.init(apps: [fixture().apps[0]]))
        spotlight.present(state, preferences: preferences, accent: .blue, strong: false, screens: screens, ready: false)
        XCTAssertEqual(spotlight.panels.count, 2)
        for panel in spotlight.panels {
            XCTAssertTrue(panel.isVisible)
            let view = try XCTUnwrap(panel.contentView as? DesktopSpotlightView)
            XCTAssertFalse(view.revealed); XCTAssertEqual(view.opacity, 0.75)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide/2, y: bitmap.pixelsHigh/2)).alphaComponent, 0.75, accuracy: 0.01)
        }
        state.cancel()
        spotlight.present(state, preferences: preferences, accent: .blue, strong: false, screens: screens)
        XCTAssertTrue(spotlight.panels.allSatisfy { !$0.isVisible })
    }

    func testSwitcherOnlyNeverPreviewsWindowsButStillCommitsSelection() {
        var settings = SettingsDocument(); settings.appearance.desktopSpotlight.mode = .switcherOnly
        let raised = Locked<[TargetID]>([]), selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {},
                                 onPreview: { id in if let id { raised.withValue { $0.append(id) } } }, onHealth: { _ in })
        func event(_ code: UInt16, flags: CGEventFlags = []) -> (CGEventType, CGEvent) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags; return (.keyDown, event)
        }
        _ = router.replayForTesting(snapshot: fixture(), settings: settings, events: [
            event(settings.activation.keyCode, flags: CGEventFlags(rawValue: settings.activation.modifiers)), event(48), event(36)
        ])
        XCTAssertTrue(raised.withValue { $0.isEmpty })
        XCTAssertEqual(selected.withValue { $0.count }, 1)
    }
    @MainActor func testWindowRevealAnimationCancelsOnRapidChangesAndDismissal() throws {
        let spotlight = DesktopSpotlight(); defer { spotlight.dismiss() }
        let snapshot = fixture()
        var state = opened(snapshot)
        _ = state.handle(.highlight(.target(snapshot.windows[0].id)))
        var preferences = DesktopSpotlightPreferences(); preferences.animationDuration = 0.4
        let screens = [CGRect(x: 0, y: 0, width: 900, height: 700)]
        func present(_ ready: Bool, reduceMotion: Bool = false) {
            spotlight.present(state, preferences: preferences, accent: .blue, strong: false, screens: screens, ready: ready, reduceMotion: reduceMotion)
        }
        present(false)
        let panel = try XCTUnwrap(spotlight.panels.first)
        let view = try XCTUnwrap(panel.contentView as? DesktopSpotlightView)
        XCTAssertTrue(panel.isVisible); XCTAssertFalse(view.revealed)
        present(true)
        XCTAssertTrue(view.revealed)
        XCTAssertEqual(view.revealCover.animation(forKey: "windowReveal")?.duration, 0.4)
        _ = state.handle(.highlight(.target(snapshot.windows[1].id)))
        present(false)
        XCTAssertTrue(panel.isVisible); XCTAssertFalse(view.revealed)
        XCTAssertNil(view.revealCover.animation(forKey: "windowReveal"))
        present(true)
        XCTAssertEqual(view.revealCover.animationKeys(), ["windowReveal"])
        spotlight.dismiss()
        XCTAssertFalse(panel.isVisible); XCTAssertNil(view.revealCover.animation(forKey: "windowReveal"))
        present(true, reduceMotion: true)
        XCTAssertTrue(view.revealed); XCTAssertNil(view.revealCover.animation(forKey: "windowReveal"))
        present(false); preferences.animationEnabled = false; present(true)
        XCTAssertTrue(view.revealed); XCTAssertNil(view.revealCover.animation(forKey: "windowReveal"))
    }
    private func fixture() -> CatalogueSnapshot {
        let owner = UUID()
        var snapshot = CatalogueSnapshot(windows: [
            Target(id: .init(process: owner, window: UUID()), app: "Example", title: "First", address: "j", foldAddress: "ij",
                   bounds: CGRect(x: 30, y: 40, width: 280, height: 210), onScreen: true),
            Target(id: .init(process: owner, window: UUID()), app: "Example", title: "Second", address: "k", foldAddress: "ik",
                   bounds: CGRect(x: 370, y: 60, width: 300, height: 240), onScreen: true)
        ], apps: [Target(id: .init(process: owner), app: "Example", title: "Example", address: "i", foldAddress: "i")])
        snapshot.history.observe(snapshot.windows[1].id); snapshot.history.observe(snapshot.windows[0].id)
        return snapshot
    }
    private func opened(_ snapshot: CatalogueSnapshot, mode: DisplayMode = .shore) -> SelectionState {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        return state
    }

    @MainActor func testRejectsNonWindowAndInvisibleOrInvalidTargets() {
        let original = fixture().windows[0]
        let mutations: [(inout Target) -> Void] = [
            { $0.onScreen = false }, { $0.minimized = true }, { $0.hidden = true }, { $0.elsewhere = true },
            { $0.available = false }, { $0.isRunning = false }, { $0.bounds = nil },
            { $0.bounds = .zero }, { $0.bounds = CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100) }
        ]
        for mutate in mutations {
            var target = original; mutate(&target)
            let state = opened(.init(windows: [target]))
            XCTAssertNil(DesktopSpotlight.windowFrame(for: state, primaryTop: 900))
        }
        for snapshot in [CatalogueSnapshot(tabs: [original]), CatalogueSnapshot(apps: [original])] {
            XCTAssertNil(DesktopSpotlight.windowFrame(for: opened(snapshot), primaryTop: 900))
        }
        XCTAssertNil(DesktopSpotlight.windowFrame(for: opened(fixture(), mode: .fold), primaryTop: 900), "An app family has no single selected window.")
        var state = opened(.init(windows: [original])); state.cancel()
        XCTAssertNil(DesktopSpotlight.windowFrame(for: state, primaryTop: 900))
    }

    @MainActor func testPanelReuseCoordinatesAndDisplayRemovalWithoutTakingInput() throws {
        let spotlight = DesktopSpotlight(); defer { spotlight.dismiss() }
        var settings = DesktopSpotlightPreferences(); settings.dimmingOpacity = 0
        var snapshot = fixture()
        snapshot.windows[0].bounds = CGRect(x: -80, y: -120, width: 400, height: 300)
        var state = opened(snapshot); _ = state.handle(.highlight(.target(snapshot.windows[0].id)))
        let screens = [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: -640, y: 120, width: 640, height: 600)]
        spotlight.present(state, preferences: settings, accent: .blue, strong: false, screens: screens)
        XCTAssertEqual(spotlight.panels.count, 2)
        let panels = spotlight.panels
        for (index, panel) in panels.enumerated() {
            XCTAssertTrue(panel.isVisible); XCTAssertTrue(panel.ignoresMouseEvents)
            XCTAssertFalse(panel.canBecomeKey); XCTAssertFalse(panel.canBecomeMain)
            XCTAssertFalse(panel.hasShadow)
            XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.normal.rawValue)
            XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.floating.rawValue)
            let view = try XCTUnwrap(panel.contentView as? DesktopSpotlightView)
            let expected = CGRect(x: -80, y: 420, width: 400, height: 300).offsetBy(dx: -screens[index].minX, dy: -screens[index].minY)
            XCTAssertEqual(view.windowFrame, expected)
            XCTAssertEqual(view.opacity, 0)
        }
        _ = state.handle(.next); settings.dimmingOpacity = 0.75
        spotlight.present(state, preferences: settings, accent: .red, strong: true, screens: screens)
        XCTAssertTrue(spotlight.panels[0] === panels[0])
        XCTAssertEqual((panels[0].contentView as? DesktopSpotlightView)?.windowFrame, CGRect(x: 370, y: 300, width: 300, height: 240))
        XCTAssertEqual((panels[0].contentView as? DesktopSpotlightView)?.opacity, 0.75)
        spotlight.present(state, preferences: settings, accent: .red, strong: false, screens: [screens[0]])
        XCTAssertEqual(spotlight.panels.count, 1); XCTAssertFalse(panels[1].isVisible)
        spotlight.dismiss(); XCTAssertFalse(panels[0].isVisible)
        spotlight.present(state, preferences: settings, accent: .red, strong: false, screens: [screens[0]])
        XCTAssertTrue(panels[0].isVisible)
        settings.enabled = false
        spotlight.present(state, preferences: settings, accent: .red, strong: false, screens: screens)
        XCTAssertTrue(spotlight.panels.allSatisfy { !$0.isVisible })
    }

    @MainActor func testPresenterFollowsKeyboardSelectionAndDismissalAcrossLayouts() throws {
        for mode in DisplayMode.allCases {
            let presenter = SwitcherPresenter(); defer { presenter.dismiss() }
            presenter.settings.appearance.desktopSpotlight.dimmingOpacity = 0
            let snapshot = fixture()
            var state = opened(snapshot, mode: mode)
            if mode == .fold { _ = state.handle(.prefix("i")) }
            _ = state.handle(.highlight(.target(snapshot.windows[0].id)))
            presenter.present(state, icons: [:], status: "")
            let panel = try XCTUnwrap(presenter.desktopSpotlight.panels.first, mode.rawValue)
            XCTAssertTrue(panel.isVisible, mode.rawValue)
            let initial = try XCTUnwrap(panel.contentView as? DesktopSpotlightView).windowFrame
            _ = state.handle(.next)
            presenter.present(state, icons: [:], status: "")
            XCTAssertNotEqual((panel.contentView as? DesktopSpotlightView)?.windowFrame, initial, mode.rawValue)
            _ = state.handle(.enter)
            presenter.present(state, icons: [:], status: "")
            XCTAssertFalse(panel.isVisible, mode.rawValue)
            state.open(); presenter.present(state, icons: [:], status: "")
            _ = state.handle(.dismiss); presenter.present(state, icons: [:], status: "")
            XCTAssertTrue(presenter.desktopSpotlight.panels.allSatisfy { !$0.isVisible })
        }
    }

    @MainActor func testSelectionMovesBetweenThreeDisplaysWithoutDismissingSpotlight() throws {
        let screens = [CGRect(x: 0, y: 0, width: 3840, height: 2160),
                       CGRect(x: -1728, y: 538, width: 1728, height: 1117),
                       CGRect(x: 3840, y: 270, width: 3360, height: 1890)]
        let primaryTop = screens[0].maxY
        let targets = screens.enumerated().map { index, screen in
            Target(id: .init(process: UUID(), window: UUID()), app: "Example", title: "Window \(index)", address: ["j", "k", "l"][index],
                   bounds: CGRect(x: screen.minX+100, y: primaryTop-screen.maxY+100, width: 800, height: 600), onScreen: true)
        }
        var state = opened(.init(windows: targets))
        let spotlight = DesktopSpotlight(); defer { spotlight.dismiss() }
        for selected in [1, 0, 2, 0] {
            _ = state.handle(.highlight(.target(targets[selected].id)))
            spotlight.present(state, preferences: DesktopSpotlightPreferences(), accent: .blue, strong: false, screens: screens)
            XCTAssertEqual(spotlight.panels.count, 3)
            for (index, panel) in spotlight.panels.enumerated() {
                XCTAssertTrue(panel.isVisible)
                let view = try XCTUnwrap(panel.contentView as? DesktopSpotlightView)
                XCTAssertEqual(view.windowFrame.intersects(CGRect(origin: .zero, size: screens[index].size)), index == selected)
                XCTAssertEqual(view.opacity, 0.75)
            }
        }
    }

    @MainActor func testPreviewsAndDemoNeverCreateDesktopOverlays() {
        for (embedded, previewOnly, allowed) in [(true, false, true), (false, true, true), (false, false, false)] {
            let presenter = SwitcherPresenter(); defer { presenter.dismiss() }
            presenter.embedded = embedded; presenter.previewOnly = previewOnly; presenter.allowsDesktopSpotlight = allowed
            presenter.present(opened(fixture()), icons: [:], status: "")
            XCTAssertTrue(presenter.desktopSpotlight.panels.isEmpty)
        }
    }

    func testCoveredWindowsQualifyForRaisingButHiddenAndNonWindowTargetsDoNot() {
        var target = fixture().windows[0]; target.onScreen = false
        XCTAssertEqual(InputRouter.previewTarget(in: opened(.init(windows: [target])), enabled: true), target.id)
        XCTAssertNil(InputRouter.previewTarget(in: opened(.init(windows: [target])), enabled: false))
        for mutate: (inout Target) -> Void in [
            { $0.minimized = true }, { $0.hidden = true }, { $0.elsewhere = true }, { $0.available = false }, { $0.bounds = nil }
        ] {
            var excluded = target; mutate(&excluded)
            XCTAssertNil(InputRouter.previewTarget(in: opened(.init(windows: [excluded])), enabled: true))
        }
        XCTAssertNil(InputRouter.previewTarget(in: opened(.init(apps: [target])), enabled: true))
        XCTAssertNil(InputRouter.previewTarget(in: opened(.init(tabs: [target])), enabled: true))
    }

    @MainActor func testSpotlightWaitsForRaiseBeforeHighlightingOldScreenContents() {
        let presenter = SwitcherPresenter(); defer { presenter.dismiss() }
        presenter.desktopSpotlightReady = false
        let snapshot = fixture()
        var state = opened(snapshot)
        _ = state.handle(.highlight(.target(snapshot.windows[0].id)))
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(presenter.desktopSpotlight.panels.contains(where: \.isVisible))
        XCTAssertTrue(presenter.desktopSpotlight.panels.allSatisfy { ($0.contentView as? DesktopSpotlightView)?.revealed == false })
        presenter.desktopSpotlightReady = true
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(presenter.desktopSpotlight.panels.contains(where: \.isVisible))
        presenter.desktopSpotlightReady = false
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(presenter.desktopSpotlight.panels.allSatisfy { ($0.contentView as? DesktopSpotlightView)?.revealed == false })
    }

    func testRouterEndsWindowPreviewOnCommitCancelAndDisabledSetting() {
        for enabled in [true, false] {
            for key: UInt16 in [36, 53] { // Enter and Escape.
                let events = Locked<[String]>([])
                let restored = Locked<[TargetID]>([])
                var settings = SettingsDocument(); settings.appearance.desktopSpotlight.enabled = enabled
                let router = InputRouter(onState: { _ in }, onSelect: { _ in events.withValue { $0.append("selected") } },
                    onCancel: { events.withValue { $0.append("cancelled") } },
                    onPreview: { id in events.withValue { $0.append(id == nil ? "preview ended" : "preview window") } },
                    onRestorePreview: { id in restored.withValue { $0.append(id) } }, onHealth: { _ in })
                func event(_ code: UInt16, flags: CGEventFlags = []) -> (CGEventType, CGEvent) {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
                    event.flags = flags; return (.keyDown, event)
                }
                let snapshot = fixture()
                _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: [
                    event(settings.activation.keyCode, flags: CGEventFlags(rawValue: settings.activation.modifiers)), event(key)
                ])
                let recorded = events.withValue { $0 }
                XCTAssertEqual(recorded.contains("preview window"), enabled)
                XCTAssertEqual(recorded.suffix(2), [key == 36 ? "selected" : "cancelled", "preview ended"])
                XCTAssertEqual(restored.withValue { $0 }, enabled && key == 53 ? [snapshot.history.current!] : [])
            }
        }
    }

    func testCancellingOrSelectingInvalidatesPendingWindowRaise() {
        let focus = FocusCoordinator()
        let owner = UUID(), pid: pid_t = 2_000_000_000
        let process = ProcessInfo(token: owner, pid: pid, name: "Absent fixture", app: AXHandle(AXUIElementCreateApplication(pid)))
        let ids = (0..<2).map { _ in TargetID(process: owner, window: UUID()) }
        focus.update(Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, FocusTarget(process: process, window: WindowRecord(id: id, handle: process.app, title: "Fixture", minimized: false, available: true)))
        }))
        focus.preview(ids[0]); XCTAssertTrue(focus.hasWindowPreview)
        focus.preview(ids[1]); XCTAssertTrue(focus.isPreviewActivation(pid))
        focus.preview(nil); XCTAssertFalse(focus.hasWindowPreview); XCTAssertNil(focus.previewedID)
        focus.preview(ids[0]); focus.submit(ids[1])
        XCTAssertFalse(focus.hasWindowPreview)
        XCTAssertTrue(focus.hasPendingFocus)
        focus.preview(nil) // An inactive presentation must not cancel the committed selection.
        XCTAssertTrue(focus.hasPendingFocus)
        focus.cancel(); XCTAssertFalse(focus.hasPendingFocus); XCTAssertNil(focus.previewedID)
    }

    @MainActor func testOpacityChangesOnlyPixelsOutsideWindowAndOldHoleIsCleared() throws {
        let view = DesktopSpotlightView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let first = CGRect(x: 30, y: 30, width: 100, height: 120)
        func bitmap(_ opacity: Double, frame: CGRect) throws -> NSBitmapImageRep {
            view.configure(windowFrame: frame, opacity: opacity, accent: .blue, strong: false)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        func alpha(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> CGFloat {
            let scale = CGFloat(bitmap.pixelsWide)/view.bounds.width
            return try XCTUnwrap(bitmap.colorAt(x: Int(x*scale), y: Int(y*scale))).alphaComponent
        }
        for opacity in [0.0, 0.35, 1.0] {
            let image = try bitmap(opacity, frame: first)
            XCTAssertEqual(try alpha(image, x: 10, y: 100), opacity, accuracy: 0.01)
            XCTAssertEqual(try alpha(image, x: 80, y: 100), 0, accuracy: 0.01)
        }
        let moved = try bitmap(0.5, frame: CGRect(x: 180, y: 30, width: 100, height: 120))
        XCTAssertEqual(try alpha(moved, x: 80, y: 100), 0.5, accuracy: 0.01)
        XCTAssertEqual(try alpha(moved, x: 230, y: 100), 0, accuracy: 0.01)
    }

    @MainActor func testSettingsPersistenceAndUndoPreserveSpotlightPreferences() throws {
        let domain = "pl.tabnax.tests.spotlight.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        var changed = preferences.document
        changed.appearance.desktopSpotlight.dimmingOpacity = 0.7
        XCTAssertTrue(preferences.commit(changed))
        changed.appearance.desktopSpotlight.enabled = false
        XCTAssertTrue(preferences.commit(changed))
        XCTAssertEqual(Preferences(defaults: defaults).document.appearance.desktopSpotlight, changed.appearance.desktopSpotlight)
        preferences.undo()
        XCTAssertTrue(preferences.document.appearance.desktopSpotlight.enabled)
        XCTAssertEqual(preferences.document.appearance.desktopSpotlight.dimmingOpacity, 0.7)
    }

    @MainActor func testSettingsExamplePreservesWindowContentInsideTheSpotlight() throws {
        let view = DesktopSpotlightSampleView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        var preferences = DesktopSpotlightPreferences()
        for opacity in [0.0, 0.35, 1.0] {
            preferences.dimmingOpacity = opacity
            view.configure(preferences: preferences, accent: .blue)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide)/view.bounds.width
            let selected = try XCTUnwrap(bitmap.colorAt(x: Int(240*scale), y: Int(100*scale))?.usingColorSpace(.sRGB))
            let background = try XCTUnwrap(bitmap.colorAt(x: Int(10*scale), y: Int(100*scale))?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(selected.redComponent, 0.9, "Dimming must leave sample window content visible.")
            XCTAssertEqual(background.redComponent, 0.44*(1-opacity), accuracy: 0.02)
        }
    }
}
