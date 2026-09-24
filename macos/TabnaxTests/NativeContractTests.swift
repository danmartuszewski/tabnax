import XCTest
import ServiceManagement
import AppKit
import Darwin
import Carbon
import ApplicationServices
@testable import Tabnax
import TabnaxCore

final class ThemeMaterialTests: XCTestCase {
    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor func testNativeActionMenuKeepsExactCommandsAndDisabledExplanations() {
        let presenter = SwitcherPresenter()
        let first = TargetID(process: UUID(), window: UUID()), second = TargetID(process: UUID(), window: UUID())
        var received: [(SwitcherAction, TargetID, UInt64)] = []
        presenter.onMenuAction = { received.append(($0, $1, $2)) }
        let menu = presenter.makeActionMenu([
            .init(action: .closeWindow, target: first),
            .init(action: .minimizeWindow, target: second),
            .init(action: .zoomWindow, target: nil, disabledReason: "Highlight an individual window")
        ], title: "Same title", session: 17)
        XCTAssertEqual(menu.items.count, 5)
        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertTrue(menu.items[2].isEnabled)
        XCTAssertFalse(menu.items[4].isEnabled)
        XCTAssertTrue(menu.items[4].title.contains("Highlight an individual window"))
        XCTAssertNil(menu.items[4].action)
        menu.performActionForItem(at: 3); menu.performActionForItem(at: 2)
        XCTAssertEqual(received.map { $0.0 }, [.minimizeWindow, .closeWindow])
        XCTAssertEqual(received.map { $0.1 }, [second, first])
        XCTAssertEqual(received.map { $0.2 }, [17, 17])
        presenter.previewOnly = true
        menu.performActionForItem(at: 2)
        XCTAssertEqual(received.count, 2, "Previews cannot run real actions")
    }
    @MainActor func testBeaconsSeparatesTabsAndAppsFromWindowGeometryFailures() {
        var labels = LabelSession(), state = SelectionState()
        state.configure(mode: .beacons)
        state.update(labels.map(SettingsModel.samples())); state.open()
        let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
        presenter.previewSize = CGSize(width: 750, height: 650)
        presenter.present(state, icons: [:], status: "")
        defer { presenter.dismiss() }
        let headings = descendants(presenter.embeddedView).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(headings.contains { $0.hasPrefix("BROWSER TABS") })
        XCTAssertTrue(headings.contains { $0.hasPrefix("APPS") })
        XCTAssertTrue(headings.contains { $0.hasPrefix("WINDOWS") })
        XCTAssertFalse(headings.contains { $0.hasPrefix("WINDOW POSITION UNAVAILABLE") })
    }

    @MainActor func testChangingThemesPreservesEveryLayoutAndRestoresLiveMaterialAfterExport() throws {
        var labels = LabelSession()
        let snapshot = labels.map(SettingsModel.samples())
        for mode in DisplayMode.allCases {
            let presenter = SwitcherPresenter()
            presenter.previewOnly = true; presenter.embedded = true
            presenter.previewSize = CGSize(width: 620, height: 460)
            presenter.settings.appearance.source = .light
            var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
            defer { presenter.dismiss() }
            var originalTargets: Set<String>?
            // Finish on a solid theme to cover removing/reparenting both material hosts.
            for preset in ThemePreset.allCases + [.graphite] {
                presenter.settings.appearance.preset = preset
                presenter.present(state, icons: [:], status: "")
                let host = try XCTUnwrap(presenter.embeddedView as? ThemeSurfaceView)
                host.layoutSubtreeIfNeeded()
                let targets = Set(descendants(host).compactMap { ($0 as? NSButton)?.accessibilityIdentifier() }.filter { $0.hasPrefix("target-") })
                XCTAssertFalse(targets.isEmpty, "\(mode) / \(preset)")
                if let originalTargets { XCTAssertEqual(targets, originalTargets) } else { originalTargets = targets }
                XCTAssertEqual(host.contents.bounds.size, host.bounds.size)
                let liveStyle = host.activeStyle
                withThemeSnapshotFallback(in: host) {
                    XCTAssertEqual(host.activeStyle, .solid)
                    XCTAssertFalse(descendants(host).compactMap { $0 as? NSButton }.isEmpty)
                }
                XCTAssertEqual(host.activeStyle, liveStyle)
                XCTAssertNotNil(host.contents.superview)
            }
        }
    }

    @MainActor func testLiquidGlassOwnViewExportContainsRenderedContent() throws {
        let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
        presenter.previewSize = CGSize(width: 410, height: 460)
        presenter.settings.appearance.preset = .liquidGlass
        presenter.settings.appearance.source = .light
        var labels = LabelSession(), state = SelectionState()
        state.update(labels.map(SettingsModel.samples())); state.open()
        presenter.present(state, icons: [:], status: "")
        defer { presenter.dismiss() }
        let view = presenter.embeddedView
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        withThemeSnapshotFallback(in: view) { view.cacheDisplay(in: view.bounds, to: bitmap) }
        var colors = Set<String>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 9) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 9) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) { colors.insert(color.rgb.hex) }
            }
        }
        XCTAssertGreaterThan(colors.count, 12, "An export must contain controls and text, not a blank compositor layer.")
    }
}

final class FilteringLayoutTests: XCTestCase {
    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    private func fixture() -> CatalogueSnapshot {
        let a = UUID(), b = UUID()
        let windows = [
            Target(id: .init(process: a, window: UUID()), app: "Alpha", title: "Other", address: "j", foldAddress: "ij"),
            Target(id: .init(process: b, window: UUID()), app: "Beta", title: "Needle Beta", address: "k", foldAddress: "oj"),
            Target(id: .init(process: a, window: UUID()), app: "Alpha", title: "Needle Alpha", address: "l", foldAddress: "ik")
        ]
        let tab = Target(id: .init(process: UUID(), window: UUID()), app: "Alpha", title: "Needle tab", address: "uu", foldAddress: "il", owner: a)
        let apps = [Target(id: .init(process: a), app: "Alpha", title: "Alpha", address: "i", foldAddress: "i"),
                    Target(id: .init(process: b), app: "Beta", title: "Beta", address: "o", foldAddress: "o")]
        var history = FocusHistory(); history.observe(windows[1].id); history.observe(windows[0].id)
        return .init(windows: windows, apps: apps, allocated: Set((windows + [tab] + apps).map(\.address)), tabs: [tab], history: history)
    }
    @MainActor func testSearchKeepsEachNativeLayoutThroughTypingClearingAndEscape() throws {
        let snapshot = fixture()
        for mode in DisplayMode.allCases {
            let presenter = SwitcherPresenter(); presenter.previewOnly = true
            var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
            presenter.present(state, icons: [:], status: "")
            defer { presenter.dismiss() }
            let width = presenter.embeddedView.frame.width
            func rows() -> [NSButton] {
                descendants(presenter.embeddedView).compactMap { $0 as? NSButton }.filter { $0.accessibilityIdentifier().hasPrefix("target-") == true }
            }
            func labels() -> [String] {
                descendants(presenter.embeddedView).compactMap { $0 as? NSTextField }.map(\.stringValue)
            }
            func assertLayout() throws {
                XCTAssertEqual(presenter.embeddedView.frame.width, width, mode.rawValue)
                switch mode {
                case .shore:
                    XCTAssertEqual(Set(rows().map { $0.frame.minX }).count, 1)
                    let expected = state.query == "needle" ? ["l", "uu", "k"] : ["j", "l", "uu", "i", "k", "o"]
                    XCTAssertEqual(rows().sorted { $0.frame.minY < $1.frame.minY }.map { $0.accessibilityIdentifier() }, expected.map { "target-" + $0 })
                case .canopy:
                    let alpha = try XCTUnwrap(rows().first { $0.accessibilityIdentifier() == "target-ik" })
                    let beta = try XCTUnwrap(rows().first { $0.accessibilityIdentifier() == "target-oj" })
                    let tab = try XCTUnwrap(rows().first { $0.accessibilityIdentifier() == "target-il" })
                    XCTAssertLessThan(alpha.frame.minX, beta.frame.minX)
                    XCTAssertEqual(alpha.frame.minX, tab.frame.minX)
                    XCTAssertTrue(labels().contains("Alpha") && labels().contains("Beta"))
                case .lattice:
                    XCTAssertTrue(rows().allSatisfy { $0.frame.height >= 100 })
                    XCTAssertGreaterThan(Set(rows().map { $0.frame.minX }).count, 1)
                    let expected = state.query == "needle" ? ["l", "uu", "k"] : ["j", "l", "uu", "i", "k", "o"]
                    XCTAssertEqual(rows().sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map { $0.accessibilityIdentifier() }, expected.map { "target-" + $0 })
                case .fold:
                    let family = try XCTUnwrap(descendants(presenter.embeddedView).first { $0.accessibilityIdentifier() == "family-i" })
                    XCTAssertTrue(rows().allSatisfy { $0.frame.minX > family.frame.maxX })
                    XCTAssertTrue(labels().contains("APPS"))
                case .relay:
                    XCTAssertFalse(labels().contains("CURRENT WINDOW"))
                    XCTAssertFalse(labels().contains("Not in search results"))
                    XCTAssertEqual(rows().count, state.displayMatches.count)
                    XCTAssertGreaterThan(Set(rows().map { $0.frame.minX }).count, 1)
                case .beacons:
                    XCTAssertTrue(labels().contains { $0.hasPrefix(state.hasSearchTerms ? "TARGETS" : "WINDOWS") })
                    XCTAssertGreaterThan(Set(rows().map { $0.frame.minX }).count, 1)
                }
            }
            _ = state.handle(.beginSearch)
            for query in ["", "needle", "", "no-such-result", "needle"] {
                _ = state.handle(.query(query)); presenter.present(state, icons: [:], status: "")
                let search = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSSearchField }.first)
                XCTAssertFalse(search.isHidden); XCTAssertEqual(search.stringValue, query)
                if state.matches.isEmpty {
                    XCTAssertTrue(rows().isEmpty, mode.rawValue)
                    XCTAssertTrue(labels().contains { $0.hasPrefix("No matching") }, mode.rawValue)
                    XCTAssertEqual(presenter.embeddedView.frame.width, width, mode.rawValue)
                } else {
                    try assertLayout()
                    if query == "needle" {
                        XCTAssertTrue(rows().allSatisfy { $0.accessibilityLabel()?.contains("Needle") == true }, mode.rawValue)
                    }
                }
            }
            _ = state.handle(.escape); presenter.present(state, icons: [:], status: "")
            XCTAssertEqual(presenter.embeddedView.frame.width, width, mode.rawValue)
            XCTAssertTrue(descendants(presenter.embeddedView).compactMap { $0 as? NSSearchField }.allSatisfy(\.isHidden))
            XCTAssertEqual(state.mode, mode)
        }
    }
    @MainActor func testFoldSearchAppButtonsNavigateOnlyToAvailableMatches() throws {
        var snapshot = fixture()
        snapshot.windows[1].available = false
        snapshot.windows.append(Target(id: .init(process: snapshot.apps[1].id.process, window: UUID()),
                                       app: "Beta", title: "Other available window", address: "m", foldAddress: "ok"))
        let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
        defer { presenter.dismiss() }
        var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
        _ = state.handle(.beginSearch); _ = state.handle(.query("needle"))
        var key: SelectionKey?
        presenter.onKey = { value, _ in key = value }
        presenter.present(state, icons: [:], status: "")
        let buttons = descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
        let alpha = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier() == "family-i" })
        let beta = try XCTUnwrap(buttons.first { $0.accessibilityIdentifier() == "family-o" })
        XCTAssertFalse(beta.isEnabled); XCTAssertFalse(beta.accessibilityPerformPress()); XCTAssertNil(key)
        XCTAssertTrue(alpha.accessibilityPerformPress())
        XCTAssertEqual(key, .highlight(.target(snapshot.windows[2].id)))
        XCTAssertEqual(state.query, "needle")
    }
    @MainActor func testFoldShowsImpliedChildKeysAndCompleteSearchAddresses() throws {
        let snapshot = fixture()
        let presenter = SwitcherPresenter(); presenter.previewOnly = true
        defer { presenter.dismiss() }
        var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
        _ = state.handle(.highlight(.branch("i")))
        func childKey() throws -> (NSButton, NSTextField) {
            let row = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "target-ik" })
            let key = try XCTUnwrap(descendants(row).compactMap { $0 as? NSTextField }.first { $0.alignment == .center })
            return (row, key)
        }
        // The root highlight implies the family head, making its displayed suffix actionable.
        XCTAssertTrue(state.prefix.isEmpty)
        presenter.present(state, icons: [:], status: "")
        XCTAssertEqual(try childKey().1.stringValue, "K")
        var directSelection = state
        XCTAssertEqual(directSelection.handle(.letter("k")), .selected(snapshot.windows[2].id))

        _ = state.handle(.enter)
        XCTAssertEqual(state.prefix, "i")
        presenter.present(state, icons: [:], status: "")
        let (row, key) = try childKey()
        XCTAssertEqual(key.stringValue, "K")
        XCTAssertTrue(row.accessibilityLabel()?.hasPrefix("IK,") == true)

        _ = state.handle(.beginSearch); _ = state.handle(.query("Needle Alpha"))
        presenter.present(state, icons: [:], status: "")
        XCTAssertEqual(try childKey().1.stringValue, "IK")
        XCTAssertEqual(state.handle(.enter), .selected(snapshot.windows[2].id))
    }
    @MainActor func testRelayStacksItsPairWithinANarrowPreview() throws {
        let snapshot = fixture()
        let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
        presenter.previewSize = CGSize(width: 350, height: 600)
        defer { presenter.dismiss() }
        var state = SelectionState(); state.configure(mode: .relay); state.update(snapshot); state.open()
        presenter.present(state, icons: [:], status: "")
        presenter.embeddedView.layoutSubtreeIfNeeded()
        let rows = descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
        let current = try XCTUnwrap(rows.first { $0.accessibilityIdentifier() == "target-j" })
        let previous = try XCTUnwrap(rows.first { $0.accessibilityIdentifier() == "target-k" })
        XCTAssertEqual(current.frame.minX, previous.frame.minX)
        XCTAssertGreaterThan(previous.frame.minY, current.frame.maxY)
        XCTAssertEqual(current.frame.width, previous.frame.width)
        for row in [current, previous] {
            let body = try XCTUnwrap(row.superview)
            XCTAssertGreaterThanOrEqual(row.frame.minX, 0)
            XCTAssertLessThanOrEqual(row.frame.maxX, body.bounds.width)
            for label in row.subviews.compactMap({ $0 as? NSTextField }) {
                XCTAssertGreaterThanOrEqual(label.frame.minX, 0)
                XCTAssertLessThanOrEqual(label.frame.maxX, row.bounds.width)
            }
        }
        // Rearranging the two cards must not change Return's destination.
        XCTAssertEqual(state.handle(.enter), .selected(snapshot.windows[1].id))
    }
    @MainActor func testFoldCompactLargeFamiliesKeepNamesKeysAndIconsSeparate() throws {
        for familyAddress in ["i", "iiii"] {
            var snapshot = fixture()
            snapshot.apps[0].foldAddress = familyAddress
            for index in snapshot.windows.indices where snapshot.windows[index].groupOwner == snapshot.apps[0].id.process {
                snapshot.windows[index].foldAddress = familyAddress + String(snapshot.windows[index].foldAddress.suffix(1))
            }
            snapshot.tabs[0].foldAddress = familyAddress + "l"
            let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
            presenter.previewSize = CGSize(width: 306, height: 272)
            presenter.settings.appearance.scale = .extraLarge
            defer { presenter.dismiss() }
            var state = SelectionState(); state.configure(mode: .fold); state.update(snapshot); state.open()
            _ = state.handle(.highlight(.branch(familyAddress)))
            presenter.present(state, icons: [:], status: "")
            presenter.embeddedView.layoutSubtreeIfNeeded()
            let family = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "family-\(familyAddress)" })
            let fields = family.subviews.compactMap { $0 as? NSTextField }
            let name = try XCTUnwrap(fields.first { $0.stringValue == "Alpha" })
            let key = try XCTUnwrap(fields.first { $0.stringValue == familyAddress.uppercased() })
            XCTAssertFalse(name.frame.intersects(key.frame))
            XCTAssertGreaterThanOrEqual(name.frame.width, name.intrinsicContentSize.width)
            let visibleParts = family.subviews.filter { ($0 is NSTextField || $0 is NSImageView) && !$0.isHidden }
            for part in visibleParts {
                XCTAssertGreaterThanOrEqual(part.frame.minX, 0)
                XCTAssertGreaterThanOrEqual(part.frame.minY, 0)
                XCTAssertLessThanOrEqual(part.frame.maxX, family.bounds.width)
                XCTAssertLessThanOrEqual(part.frame.maxY, family.bounds.height)
            }
            for icon in family.subviews.compactMap({ $0 as? NSImageView }).filter({ !$0.isHidden }) {
                XCTAssertFalse(icon.frame.intersects(name.frame))
                XCTAssertFalse(icon.frame.intersects(key.frame))
            }
            let body = try XCTUnwrap(family.superview)
            for caption in body.subviews.compactMap({ $0 as? NSTextField }).filter({ $0.frame.minY == 0 }) {
                XCTAssertLessThanOrEqual(caption.frame.maxY, family.frame.minY)
                let font = caption.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                XCTAssertLessThanOrEqual(try XCTUnwrap(font).pointSize, 11)
            }
        }
    }
}

final class NativeContractTests: XCTestCase {
    func testSuggestedShortcutsRequireTwoModifiersAndNeverOrdinaryTyping() {
        for (_, shortcut) in Shortcut.choices {
            XCTAssertEqual(shortcut.keyCode, 49)
            XCTAssertFalse(shortcut.modifiers.isEmpty)
            XCTAssertEqual(shortcut.modifiers.rawValue.nonzeroBitCount, 2)
        }
    }
    func testPhysicalAddressMapHasEveryLetterExactlyOnce() {
        XCTAssertEqual(InputRouter.letters.count, 26)
        XCTAssertEqual(Set(InputRouter.letters.values).count, 26)
        XCTAssertEqual(InputRouter.letters[38], "j")
        XCTAssertNil(InputRouter.letters[49])
    }
    private func event(_ code: UInt16, _ down: Bool = true, flags: CGEventFlags = [], repeatKey: Bool = false) -> (CGEventType, CGEvent) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return (down ? .keyDown : .keyUp, event)
    }
    private func modifierEvent(_ code: UInt16, flags: CGEventFlags) -> (CGEventType, CGEvent) {
        let e = event(code, flags: flags).1; e.type = .flagsChanged
        return (.flagsChanged, e)
    }
    func testActionMenuDisarmsReleaseAcrossAllModesAndBehaviorsAndHandsKeysToAppKit() {
        for mode in DisplayMode.allCases { for hold in [true, false] { for searching in [true, false] {
            var settings = SettingsDocument(); settings.activation.useCommandTab()
            settings.activation.behavior = hold ? .hold : .latch
            let window = Target(id: .init(process: UUID(), window: UUID()), app: "Fixture", title: "Document", address: "j", foldAddress: "aj")
            let app = Target(id: .init(process: window.id.process), app: "Fixture", title: "Fixture", address: "k", foldAddress: "a")
            let router = InputRouter(onState: { _ in }, onSelect: { _ in XCTFail("Menu must not select") }, onCancel: {},
                onAction: { _, _ in XCTFail("Menu keys and Option must not run switcher actions") }, onHealth: { _ in })
            var events = [event(48, flags: .maskCommand), event(48, false, flags: .maskCommand)]
            if searching { events += [event(44, flags: .maskCommand), event(44, false, flags: .maskCommand)] }
            events += [event(47, flags: .maskCommand), event(47, flags: .maskCommand, repeatKey: true),
                modifierEvent(55, flags: []), event(47, false), event(38), event(38, false),
                event(125), event(36), modifierEvent(58, flags: .maskAlternate), event(53)]
            let consumed = router.replayForTesting(snapshot: .init(windows: [window], apps: [app]), mode: mode, settings: settings, events: events)
            XCTAssertEqual(Array(consumed.suffix(10)), [true, true, false, true, true, true, true, true, false, true])
            // Finish releasing pre-menu keys, then hand off new keys only when NSMenu is ready.
            _ = router.replayForTesting(snapshot: .init(windows: [window], apps: [app]), mode: mode, settings: settings,
                events: [event(125, false), event(36, false), event(53, false)])
            router.setMenuReady(session: 1)
            XCTAssertEqual(router.replayForTesting(snapshot: .init(windows: [window], apps: [app]), mode: mode, settings: settings,
                events: [event(125), event(125, false), event(38), event(38, false)]), [false, false, false, false])
            router.setMenuTracking(false, session: 1)
            let after = router.replayForTesting(snapshot: .init(windows: [window], apps: [app]), mode: mode, settings: settings,
                events: [modifierEvent(55, flags: []), event(44), event(44, false), event(38)])
            // Search text passes through after release: the held switcher stayed open.
            XCTAssertFalse(after.last!)
        } } }
    }
    func testPointerMenuGateDisarmsBeforeQueuedWorkAndDoesNotCaptureClosedTyping() {
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
        let snapshot = CatalogueSnapshot(windows: [Target(id: .init(process: UUID(), window: UUID()), app: "App", title: "Doc", address: "j")])
        let router = InputRouter(onState: { _ in }, onSelect: { _ in XCTFail("Pointer menu must not select on release") }, onCancel: {}, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: [event(48, flags: .maskCommand), event(48, false, flags: .maskCommand)])
        router.setMenuTracking(true, session: 1)
        router.setMenuTracking(false, session: 1) // Includes a menu cancelled before any next event.
        XCTAssertEqual(router.replayForTesting(snapshot: snapshot, settings: settings, events: [modifierEvent(55, flags: []), event(44), event(44, false), event(38)]), [false, true, true, false])
        settings.windowActionsEnabled = false
        let disabled = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: {}, onHealth: { _ in })
        XCTAssertEqual(disabled.replayForTesting(snapshot: snapshot, settings: settings, events: [event(47, flags: .maskCommand)]), [false])
        XCTAssertFalse(InputRouter.isActionMenuShortcut(code: 47, flags: [], activation: .maskCommand))
        XCTAssertFalse(InputRouter.isActionMenuShortcut(code: 47, flags: [.maskCommand, .maskShift], activation: .maskCommand))
    }
    func testStaleMenuCannotDisarmTheCurrentSession() {
        var settings = SettingsDocument(); settings.activation.useCommandTab()
        let window = Target(id: .init(process: UUID(), window: UUID()), app: "App", title: "Window", address: "j")
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: .init(windows: [window]), settings: settings,
            events: [event(48, flags: .maskCommand), event(48, false, flags: .maskCommand)])
        router.setMenuTracking(true, session: 999)
        _ = router.replayForTesting(snapshot: .init(windows: [window]), settings: settings, events: [modifierEvent(55, flags: [])])
        XCTAssertEqual(selected.withValue { $0 }, [window.id])
    }
    @MainActor func testMenuActionUsesFrozenIDAfterHighlightMovesAndRejectsStaleSession() {
        let first = Target(id: .init(process: UUID(), window: UUID()), app: "First", title: "Same", address: "j")
        let second = Target(id: .init(process: UUID(), window: UUID()), app: "Second", title: "Same", address: "k")
        let snapshot = CatalogueSnapshot(windows: [first, second])
        let actions = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { _ in XCTFail("Menu must not select") }, onCancel: {},
            onAction: { _, target in actions.withValue { $0.append(target) } }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: snapshot, events: [event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(125), event(125, false)])
        router.markRunningForTesting()
        defer { router.clearRunningForTesting() }
        router.menuAction(.minimizeWindow, target: first.id, session: 1)
        router.menuAction(.closeWindow, target: second.id, session: 999)
        CFRunLoopRunInMode(.defaultMode, 0.01, false)
        XCTAssertEqual(actions.withValue { $0 }, [first.id])
        router.menuAction(.closeWindow, target: first.id, session: 1)
        CFRunLoopRunInMode(.defaultMode, 0.01, false)
        XCTAssertEqual(actions.withValue { $0 }, [first.id, first.id])
    }
    func testWindowActionDriverChecksLiveSupportAndUsesOnlyExactControls() {
        var minimized = false, supported = true, writes: [String] = []
        let access = WindowActionAccess(minimized: { minimized }, canSetMinimized: { supported }, canPress: { _ in supported },
            setMinimized: { value in minimized = value; writes.append("minimized=\(value)"); return .success },
            press: { attribute in writes.append(attribute); return .success })
        XCTAssertTrue(access.perform(.minimizeWindow, hidden: false).0)
        XCTAssertFalse(access.perform(.minimizeWindow, hidden: false).0)
        XCTAssertFalse(access.perform(.zoomWindow, hidden: false).0)
        XCTAssertFalse(access.perform(.toggleFullscreen, hidden: false).0)
        XCTAssertTrue(access.perform(.restoreWindow, hidden: false).0)
        XCTAssertTrue(access.perform(.restoreWindow, hidden: false).0)
        XCTAssertFalse(access.perform(.zoomWindow, hidden: true).0)
        for action: SwitcherAction in [.closeWindow, .zoomWindow, .toggleFullscreen] { XCTAssertTrue(access.perform(action, hidden: false).0) }
        XCTAssertEqual(writes, ["minimized=true", "minimized=false", kAXCloseButtonAttribute, kAXZoomButtonAttribute, kAXFullScreenButtonAttribute])
        supported = false
        for action: SwitcherAction in [.closeWindow, .minimizeWindow, .zoomWindow, .toggleFullscreen] {
            XCTAssertNotNil(access.disabledReason(for: action, hidden: false))
            XCTAssertFalse(access.perform(action, hidden: false).0)
        }
        XCTAssertEqual(writes.count, 5)
    }
    func testCommandQQuitsHighlightInsteadOfSelectingItsLetterAndOwnsRepeatAndRelease() {
        for commandTab in [false, true] {
            for held in [false, true] {
                var settings = SettingsDocument()
                if commandTab { settings.activation.useCommandTab() }
                settings.activation.behavior = held ? .hold : .latch
                let activation = CGEventFlags(rawValue: settings.activation.modifiers)
                let id = TargetID(process: UUID(), window: UUID())
                let actions = Locked<[TargetID]>([])
                let router = InputRouter(onState: { _ in }, onSelect: { _ in XCTFail("An action must not select") }, onCancel: {},
                    onAction: { action, id in XCTAssertEqual(action, .quitApplication); actions.withValue { $0.append(id) } }, onHealth: { _ in })
                let snapshot = CatalogueSnapshot(windows: [Target(id: id, app: "Fixture", title: "Window", address: "q")])
                let consumed = router.replayForTesting(snapshot: snapshot, settings: settings, events: [
                    event(settings.activation.keyCode, flags: activation), event(settings.activation.keyCode, false, flags: activation),
                    event(48, flags: activation), event(48, false, flags: activation),
                    event(12, flags: activation.union(.maskCommand)), event(12, flags: activation.union(.maskCommand), repeatKey: true),
                    modifierEvent(55, flags: []), event(12, false)
                ])
                XCTAssertEqual(consumed, [true, true, true, true, true, true, false, true])
                XCTAssertEqual(actions.withValue { $0 }, [TargetID(process: id.process)])
            }
        }
    }
    func testCommandQWorksInSearchButPlainQRemainsTextAndClosedSwitcherPassesThrough() {
        let id = TargetID(process: UUID(), window: UUID()), actions = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { _ in XCTFail("Search must not select") }, onCancel: {},
            onAction: { _, id in actions.withValue { $0.append(id) } }, onHealth: { _ in })
        let consumed = router.replayForTesting(snapshot: .init(windows: [Target(id: id, app: "Fixture", title: "Window", address: "q")]), events: [
            event(12, flags: .maskCommand), event(12, false),
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(44), event(44, false),
            event(12), event(12, false), event(12, flags: .maskCommand), event(12, false)
        ])
        XCTAssertEqual(consumed, [false, false, true, true, true, true, false, false, true, true])
        XCTAssertEqual(actions.withValue { $0 }, [TargetID(process: id.process)])
    }
    func testOptionRestoresOncePerPressAndCommandReleaseSelectsIt() {
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
        let id = TargetID(process: UUID(), window: UUID()), actions = Locked<[TargetID]>([]), selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {},
            onAction: { action, id in XCTAssertEqual(action, .restoreWindow); actions.withValue { $0.append(id) } }, onHealth: { _ in })
        let snapshot = CatalogueSnapshot(windows: [Target(id: id, app: "Fixture", title: "Window", address: "j", minimized: true)])
        _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: [
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
            modifierEvent(58, flags: [.maskCommand, .maskAlternate]),
            modifierEvent(61, flags: [.maskCommand, .maskAlternate]),
            modifierEvent(58, flags: .maskCommand), modifierEvent(55, flags: [])
        ])
        XCTAssertEqual(actions.withValue { $0 }, [id])
        XCTAssertEqual(selected.withValue { $0 }, [id])
    }
    func testDefaultActivationDoesNotRestoreAndSearchOptionDoesNotAct() {
        let id = TargetID(process: UUID(), window: UUID()), actions = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: {},
            onAction: { _, id in actions.withValue { $0.append(id) } }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: .init(windows: [Target(id: id, app: "Fixture", title: "Window", address: "j", minimized: true)]), events: [
            modifierEvent(58, flags: [.maskControl, .maskAlternate]),
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false, flags: [.maskControl, .maskAlternate]),
            modifierEvent(59, flags: .maskAlternate), modifierEvent(58, flags: []),
            modifierEvent(61, flags: .maskAlternate), modifierEvent(61, flags: []),
            event(44), event(44, false), modifierEvent(58, flags: .maskAlternate)
        ])
        XCTAssertEqual(actions.withValue { $0 }, [id])
    }
    func testOptionOnVisibleWindowDoesNothingAndPreservesReleaseSelection() {
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
        let id = TargetID(process: UUID(), window: UUID()), selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {},
            onAction: { _, _ in XCTFail("A visible window must not receive a window action") }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: .init(windows: [Target(id: id, app: "App", title: "Visible", address: "j")]), settings: settings, events: [
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
            modifierEvent(61, flags: [.maskCommand, .maskAlternate]), modifierEvent(55, flags: .maskAlternate)
        ])
        XCTAssertEqual(selected.withValue { $0 }, [id])
    }
    func testOptionRestoresFoldChildAndReleaseSelectsThatExactWindow() {
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
        let owner = UUID()
        let id = TargetID(process: owner, window: UUID()), selected = Locked<[TargetID]>([]), actions = Locked<[TargetID]>([])
        let visible = Target(id: .init(process: owner, window: UUID()), app: "App", title: "Visible", address: "j", foldAddress: "aj")
        let minimized = Target(id: id, app: "App", title: "Minimized", address: "k", minimized: true, foldAddress: "ak")
        let app = Target(id: .init(process: owner), app: "App", title: "App", address: "a", foldAddress: "a")
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {},
            onAction: { action, id in XCTAssertEqual(action, .restoreWindow); actions.withValue { $0.append(id) } }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: .init(windows: [visible, minimized], apps: [app]), mode: .fold, settings: settings, events: [
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
            modifierEvent(58, flags: [.maskCommand, .maskAlternate]), modifierEvent(55, flags: .maskAlternate)
        ])
        XCTAssertEqual(actions.withValue { $0 }, [id]); XCTAssertEqual(selected.withValue { $0 }, [id])
    }
    func testNavigationAfterRestoreDoesNotSelectTheOldWindowOnRelease() {
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
        let first = Target(id: .init(process: UUID(), window: UUID()), app: "A", title: "Minimized", address: "j", minimized: true)
        let next = Target(id: .init(process: UUID(), window: UUID()), app: "B", title: "Visible", address: "k")
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {},
            onAction: { _, id in XCTAssertEqual(id, first.id) }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: .init(windows: [first, next]), settings: settings, events: [
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
            modifierEvent(58, flags: [.maskCommand, .maskAlternate]), modifierEvent(58, flags: .maskCommand),
            event(48, flags: .maskCommand), event(48, false, flags: .maskCommand), modifierEvent(55, flags: [])
        ])
        XCTAssertEqual(selected.withValue { $0 }, [next.id])
    }
    func testPlainQStillSelectsAndUnrelatedModifiedQNeverQuits() {
        let id = TargetID(process: UUID(), window: UUID()), selected = Locked<[TargetID]>([])
        let snapshot = CatalogueSnapshot(windows: [Target(id: id, app: "Fixture", title: "Window", address: "q")])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {},
            onAction: { _, _ in XCTFail("No quit shortcut") }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: snapshot, events: [event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(12), event(12, false)])
        XCTAssertEqual(selected.withValue { $0 }, [id])
        let consumed = router.replayForTesting(snapshot: snapshot, events: [
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(12, flags: [.maskCommand, .maskShift]), event(12, false)
        ])
        XCTAssertEqual(consumed, [true, true, false, false])
    }
    func testRealRouterAcceptsTwoKeysWithoutAFrameAndConsumesFinalKeyup() throws {
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        let id = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [Target(id: id, app: "Fixture", title: "Same title", address: "pj")])
        let consumed = router.replayForTesting(snapshot: snapshot, events: [
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false),
            event(35), event(35, false), event(38), event(38, repeatKey: true), event(38, false), event(0), event(0, false)
        ])
        XCTAssertEqual(consumed, [true, true, true, true, true, true, true, false, false])
        XCTAssertEqual(selected.withValue { $0 }, [id])
    }
    func testShiftTabIsNavigationUnderTheDefaultShortcut() {
        let selected = Locked<[TargetID]>([])
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID())
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        let snapshot = CatalogueSnapshot(windows: [Target(id: a, app: "A", title: "A", address: "j"), Target(id: b, app: "B", title: "B", address: "k")])
        let consumed = router.replayForTesting(snapshot: snapshot, events: [
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(48, flags: [.maskShift]), event(48, false), event(36), event(36, false)
        ])
        XCTAssertTrue(consumed.allSatisfy { $0 }); XCTAssertEqual(selected.withValue { $0 }, [b])
    }
    func testEveryModeRoutesItsAddressBeforeAnyPresentation() {
        for mode in DisplayMode.allCases {
            let selected = Locked<[TargetID]>([])
            let id = TargetID(process: UUID(), window: UUID())
            let app = Target(id: TargetID(process: id.process), app: "Fixture", title: "Fixture", address: "j")
            let snapshot = CatalogueSnapshot(windows: [Target(id: id, app: "Fixture", title: "Same title", address: "j", foldAddress: "jj")], apps: [app])
            let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
            var events = [event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(38), event(38, false)]
            // Fold and Canopy address a window by its app-prefixed code, so both need the second key.
            if mode == .fold || mode == .canopy { events += [event(38), event(38, false)] }
            let consumed = router.replayForTesting(snapshot: snapshot, mode: mode, events: events)
            XCTAssertTrue(consumed.allSatisfy { $0 }, mode.rawValue)
            XCTAssertEqual(selected.withValue { $0 }, [id], mode.rawValue)
        }
    }
    func testSearchTextIsPassedToNativeFieldEditorRatherThanSelected() {
        let selected = Locked<[TargetID]>([])
        let id = TargetID(process: UUID(), window: UUID())
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        let consumed = router.replayForTesting(snapshot: CatalogueSnapshot(windows: [Target(id: id, app: "Fixture", title: "Title", address: "j")]), events: [
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(44), event(44, false),
            event(38), event(38, false), event(0, flags: [.maskCommand]), event(0, false), event(36), event(36, false)
        ])
        XCTAssertEqual(consumed, [true, true, true, true, false, false, false, false, false, false])
        XCTAssertTrue(selected.withValue { $0.isEmpty })
    }
    func testRelayEnterRoutesOnlyAnObservedPreviousWindow() {
        let selected = Locked<[TargetID]>([])
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID())
        var history = FocusHistory(); history.observe(a); history.observe(b)
        let snapshot = CatalogueSnapshot(windows: [Target(id: a, app: "A", title: "A", address: "j"), Target(id: b, app: "B", title: "B", address: "k")], history: history)
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        let consumed = router.replayForTesting(snapshot: snapshot, mode: .relay, events: [event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(36), event(36, false)])
        XCTAssertTrue(consumed.allSatisfy { $0 }); XCTAssertEqual(selected.withValue { $0 }, [a])
    }
    func testRealRouterCancellationAndModifiedTypingPassThrough() {
        let selected = Locked(0)
        let router = InputRouter(onState: { _ in }, onSelect: { _ in selected.withValue { $0 += 1 } }, onCancel: {}, onHealth: { _ in })
        let consumed = router.replayForTesting(snapshot: CatalogueSnapshot(), events: [
            event(49), event(49, false), // ordinary Space is never an activation
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false),
            event(53), event(53, false), event(38), event(38, false),
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(38, flags: [.maskCommand])
        ])
        XCTAssertEqual(consumed, [false, false, true, true, true, true, false, false, true, true, false])
        XCTAssertEqual(selected.withValue { $0 }, 0)
    }
    func testCommandTabActivatesAndSelectsInEveryMode() {
        for mode in DisplayMode.allCases {
            let selected = Locked<[TargetID]>([])
            let id = TargetID(process:UUID(),window:UUID())
            let router = InputRouter(onState:{_ in},onSelect:{ id in selected.withValue { $0.append(id) } },onCancel:{},onHealth:{_ in})
            var settings = SettingsDocument(); settings.activation.useCommandTab()
            let snapshot = CatalogueSnapshot(windows:[Target(id:id,app:"Fixture",title:"Exact window",address:"j",foldAddress:"jj")],apps:[Target(id:TargetID(process:id.process),app:"Fixture",title:"Fixture",address:"j")])
            var events = [event(48,flags:.maskCommand),event(48,flags:.maskCommand,repeatKey:true),event(48,false),event(38,flags:.maskCommand),event(38,false)]
            if mode == .fold || mode == .canopy { events += [event(38),event(38,false)] }
            XCTAssertTrue(router.replayForTesting(snapshot:snapshot,mode:mode,settings:settings,events:events).allSatisfy { $0 },mode.rawValue)
            XCTAssertEqual(selected.withValue { $0 },[id],mode.rawValue)
        }
    }
    func testSingleCommandTabSwitchesBackAndForthInEveryModeAndBehavior() {
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID())
        let windows = [Target(id: a, app: "A", title: "A", address: "j", foldAddress: "jj"),
                       Target(id: b, app: "B", title: "B", address: "k", foldAddress: "kk")]
        let apps = [Target(id: TargetID(process: a.process), app: "A", title: "A", address: "j", foldAddress: "j"),
                    Target(id: TargetID(process: b.process), app: "B", title: "B", address: "k", foldAddress: "k")]
        for mode in DisplayMode.allCases {
            for behavior in ActivationBehavior.allCases {
                for commandReleasedFirst in [false, true] {
                    let selected = Locked<[TargetID]>([])
                    let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
                    var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = behavior
                    var history = FocusHistory(); history.observe(a); history.observe(b)
                    let release = commandReleasedFirst
                        ? [modifiers([]), event(48, false)]
                        : [event(48, false), modifiers([])]
                    for target in [a, b, a, b] {
                        let consumed = router.replayForTesting(snapshot: .init(windows: windows, apps: apps, history: history), mode: mode, settings: settings,
                            events: [event(48, flags: .maskCommand)] + release + [event(0), event(0, false)])
                        XCTAssertEqual(selected.withValue { $0.last }, target, "\(mode) / \(behavior)")
                        XCTAssertEqual(Array(consumed.suffix(2)), [false, false], "Selection closes the switcher and restores normal typing")
                        history.observe(target)
                    }
                    XCTAssertEqual(selected.withValue { $0 }, [a, b, a, b])
                }
            }
        }
    }
    func testCommandTabSecondTapWhileHeldCyclesRatherThanClosingInLatchMode() {
        let cancelCount = Locked<Int>(0)
        let router = InputRouter(onState: { _ in },
                                  onSelect: { _ in XCTFail("A second Tab tap while Command is held must cycle, not select") },
                                  onCancel: { cancelCount.withValue { $0 += 1 } }, onHealth: { _ in })
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .latch
        let a = TargetID(process: UUID(), window: UUID())
        let b = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [
            Target(id: a, app: "Fixture", title: "A", address: "j"),
            Target(id: b, app: "Fixture", title: "B", address: "k")
        ])
        let events = [
            event(48, flags: .maskCommand),   // Command+Tab down: opens the panel
            event(48, false),                 // Tab released, Command still held
            event(48, flags: .maskCommand),   // Second Tab tap while Command is still held: must cycle, not close
            event(48, false)
        ]
        let consumed = router.replayForTesting(snapshot: snapshot, settings: settings, events: events)
        XCTAssertTrue(consumed.allSatisfy { $0 })
        XCTAssertEqual(cancelCount.withValue { $0 }, 1, "Only the initial open should invoke onCancel; the second Tab tap must not close the panel")
    }
    private func modifiers(_ flags: CGEventFlags) -> (CGEventType, CGEvent) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: !flags.isEmpty)!
        event.flags = flags
        return (.flagsChanged, event)
    }
    func testReleasingCommandAfterCyclingSwitchesUnlessSomethingWasTypedSince() {
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID()), c = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [
            Target(id: a, app: "Fixture", title: "A", address: "j"),
            Target(id: b, app: "Fixture", title: "B", address: "pk"),
            Target(id: c, app: "Fixture", title: "C", address: "pl")
        ])
        let open = [event(48, flags: .maskCommand), event(48, false)]
        let cycle = [event(48, flags: .maskCommand), event(48, false)]
        let cases: [(String, ActivationBehavior, [(CGEventType, CGEvent)], [TargetID])] = [
            ("cycle then release switches", .latch, open + cycle + [modifiers([])], [b]),
            ("hold behavior switches too instead of cancelling", .hold, open + cycle + [modifiers([])], [b]),
            ("releasing Shift alone keeps the session", .latch, open + [event(48, flags: [.maskCommand, .maskShift]), event(48, false), modifiers(.maskCommand)], []),
            ("opening press selects on release without further cycling", .latch, open + [modifiers([])], [a]),
            ("typing after cycling keeps the partial address", .latch, open + cycle + [event(35, flags: .maskCommand), event(35, false), modifiers([])], []),
            ("cycling again after typing switches", .latch, open + [event(35, flags: .maskCommand), event(35, false)] + cycle + [modifiers([])], [c]),
        ]
        for (name, behavior, events, expected) in cases {
            let selected = Locked<[TargetID]>([])
            let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
            var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = behavior
            _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: events)
            XCTAssertEqual(selected.withValue { $0 }, expected, name)
        }
    }
    func testHoldingTabAutorepeatsThroughEachCandidateInTurn() {
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .latch
        let a = TargetID(process: UUID(), window: UUID())
        let b = TargetID(process: UUID(), window: UUID())
        let c = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [
            Target(id: a, app: "Fixture", title: "A", address: "j"),
            Target(id: b, app: "Fixture", title: "B", address: "k"),
            Target(id: c, app: "Fixture", title: "C", address: "l")
        ])
        let events = [
            event(48, flags: .maskCommand),                       // Command+Tab down: opens, highlights A
            event(48, flags: .maskCommand, repeatKey: true),       // held: advance to B
            event(48, flags: .maskCommand, repeatKey: true),       // held: advance to C
            event(48, false),                                     // release Tab
            event(36)                                              // Enter picks whatever is currently highlighted
        ]
        XCTAssertTrue(router.replayForTesting(snapshot: snapshot, settings: settings, events: events).allSatisfy { $0 })
        XCTAssertEqual(selected.withValue { $0 }, [c], "Holding Tab down must keep cycling to the next candidate, like the system switcher")
    }
    func testHoldReturnsToThePreviousWindowOnAQuickTapAndSurvivesReleasingTheTriggerKey() {
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID())
        let windows = [Target(id: a, app: "A", title: "A", address: "j"), Target(id: b, app: "B", title: "B", address: "k")]
        var history = FocusHistory(); history.observe(a); history.observe(b)
        let chord: CGEventFlags = [.maskControl, .maskAlternate]
        let tap = [event(49, flags: chord), event(49, false)]
        let cases: [(String, CatalogueSnapshot, [(CGEventType, CGEvent)], [TargetID])] = [
            ("quick tap and release returns to the previous window", .init(windows: windows, history: history), tap + [modifiers([])], [a]),
            ("with no earlier window the release just closes", .init(windows: windows), tap + [modifiers([])], []),
            ("the trigger key can be let go while the modifiers stay down", .init(windows: windows), tap + [event(40, flags: chord), event(40, false)], [b]),
            ("tapping the trigger again cycles, and the release commits", .init(windows: windows), tap + tap + [modifiers([])], [b]),
            ("typing an unknown address after opening keeps the release a plain close", .init(windows: windows, history: history), tap + [event(35, flags: chord), event(35, false), modifiers([])], []),
        ]
        for (name, snapshot, events, expected) in cases {
            let selected = Locked<[TargetID]>([])
            let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
            var settings = SettingsDocument(); settings.activation.behavior = .hold
            _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: events)
            XCTAssertEqual(selected.withValue { $0 }, expected, name)
        }
    }
    func testQuietReturnSuppressesThePanelOnTheInitialTapButNotByDefaultAndStillSwaps() {
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID())
        let windows = [Target(id: a, app: "A", title: "A", address: "j"), Target(id: b, app: "B", title: "B", address: "k")]
        var history = FocusHistory(); history.observe(a); history.observe(b)
        let snapshot = CatalogueSnapshot(windows: windows, history: history)
        for (quiet, expectPending) in [(true, false), (false, true)] {
            let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: {}, onHealth: { _ in })
            var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
            settings.activation.quietReturn = quiet
            _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: [event(48, flags: .maskCommand)])
            XCTAssertEqual(router.presentationPendingForTesting, expectPending, quiet
                ? "quietReturn must suppress the panel when reopening onto a known previous window"
                : "the panel must still be scheduled when quietReturn is off")
        }
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        var settings = SettingsDocument(); settings.activation.useCommandTab(); settings.activation.behavior = .hold
        settings.activation.quietReturn = true
        _ = router.replayForTesting(snapshot: snapshot, settings: settings, events: [
            event(48, flags: .maskCommand), event(48, false), modifiers([])
        ])
        XCTAssertEqual(selected.withValue { $0 }, [a], "quietReturn must only hide the panel, never change which window is selected")
    }
    func testLatchedTriggerCyclesWhileModifiersStayDownAndTogglesClosedAfterTheyWereReleased() {
        let a = TargetID(process: UUID(), window: UUID()), b = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [Target(id: a, app: "A", title: "A", address: "j"), Target(id: b, app: "B", title: "B", address: "k")])
        let chord: CGEventFlags = [.maskControl, .maskAlternate]
        let tap = [event(49, flags: chord), event(49, false)]
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: snapshot, events: tap + tap + [modifiers([])])
        XCTAssertEqual(selected.withValue { $0 }, [b], "A second trigger tap with the modifiers still held cycles; the release commits")
        let closing = router.replayForTesting(snapshot: snapshot, events: tap + [modifiers([])] + tap + [event(38), event(38, false)])
        XCTAssertEqual(closing, [true, true, false, true, true, false, false], "After the modifiers were let go, the chord closes the latch and typing passes through")
        XCTAssertEqual(selected.withValue { $0 }, [b])
    }
    func testArrowsAndStrayKeysNeitherCloseTheSwitcherNorLeak() {
        let a = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [Target(id: a, app: "A", title: "A", address: "j")])
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        let consumed = router.replayForTesting(snapshot: snapshot, events: [
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false),
            event(124), event(124, false), event(123), event(123, false), // arrows
            event(50), event(50, false),                                  // a key with no meaning here
            event(122), event(122, false),                                // F1 still reaches the system
            event(38), event(38, false)])
        XCTAssertEqual(consumed, [true, true, true, true, true, true, true, true, false, false, true, true])
        XCTAssertEqual(selected.withValue { $0 }, [a], "The session must still be open after arrows and a stray key")
    }
    func testTypingAfterASwitchOnlyDisarmsTheRepairAndNeverCancelsTheSwitch() {
        let cancels = Locked(0), passive = Locked(0)
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: { cancels.withValue { $0 += 1 } },
                                 onPassiveKey: { passive.withValue { $0 += 1 } }, onHealth: { _ in })
        let consumed = router.replayForTesting(snapshot: .init(), events: [event(38), event(38, false), event(0)])
        XCTAssertEqual(consumed, [false, false, false])
        XCTAssertEqual(cancels.withValue { $0 }, 0); XCTAssertEqual(passive.withValue { $0 }, 2)
    }
    func testASingleTapLossReArmsCaptureInsteadOfStoppingIt() {
        let a = TargetID(process: UUID(), window: UUID())
        let snapshot = CatalogueSnapshot(windows: [Target(id: a, app: "A", title: "A", address: "j")])
        let selected = Locked<[TargetID]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
        let lost: (CGEventType, CGEvent) = (.tapDisabledByTimeout, CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!)
        let consumed = router.replayForTesting(snapshot: snapshot, events: [
            event(49, flags: [.maskControl, .maskAlternate]), lost, // closes the open session, keeps routing
            event(49, flags: [.maskControl, .maskAlternate]), event(49, false), event(38), event(38, false)])
        XCTAssertEqual(consumed, [true, false, true, true, true, true]); XCTAssertEqual(selected.withValue { $0 }, [a])
    }
    func testRecorderCapturesSystemChordWithoutOpeningAndOwnsReleaseAfterStop() {
        let captured = Locked<[Shortcut]>([])
        let router = InputRouter(onState:{_ in},onSelect:{_ in XCTFail("Recording must never select")},onCancel:{},onHealth:{_ in})
        router.recordShortcut { chord in captured.withValue { $0.append(chord) } }
        XCTAssertEqual(router.replayForTesting(snapshot:.init(),events:[event(48,flags:[.maskCommand,.maskAlphaShift]),event(48,flags:.maskCommand,repeatKey:true)]),[true,true])
        XCTAssertEqual(captured.withValue { $0 },[Shortcut(keyCode:48,modifiers:.maskCommand)])
        router.recordShortcut(using:nil)
        XCTAssertEqual(router.replayForTesting(snapshot:.init(),events:[event(48,flags:.maskCommand,repeatKey:true),event(48,false),event(48,flags:.maskCommand),event(48,false)]),[true,true,false,false])
        // Default activation resumes immediately after the recorder stops.
        XCTAssertEqual(router.replayForTesting(snapshot:.init(),events:[event(49,flags:[.maskControl,.maskAlternate]),event(49,false)]),[true,true])
    }
}

final class ExactWindowIntegrationTests: XCTestCase {
    @MainActor func testRetryingRunningCapturePreservesPendingSelection() async {
        let cancellations = Locked(0)
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: { cancellations.withValue { $0 += 1 } }, onHealth: { _ in })
        _ = router.replayForTesting(snapshot: .init(), mode: .canopy, events: [])
        router.markRunningForTesting()
        defer { router.clearRunningForTesting() }
        router.start(snapshot: .init(), mode: .canopy)
        // Drain the scheduled capture work on this test's run loop.
        let drained = expectation(description: "Capture retry drained")
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { drained.fulfill() }
        CFRunLoopWakeUp(CFRunLoopGetMain())
        await fulfillment(of: [drained], timeout: 3)
        XCTAssertEqual(cancellations.withValue { $0 }, 0)
    }

    @MainActor func testActionsRejectMissingTargetsAndReusedProcessIDs() async {
        let coordinator = FocusCoordinator(), missing = TargetID(process: UUID()), stale = TargetID(process: UUID())
        let pid = Foundation.ProcessInfo.processInfo.processIdentifier
        let process = Tabnax.ProcessInfo(token: stale.process, pid: pid, name: "Wrong lifetime", app: AXHandle(AXUIElementCreateApplication(pid)), launchDate: .distantPast)
        coordinator.update([stale: FocusTarget(process: process, window: nil)])
        let rejected = expectation(description: "Both stale requests rejected"); rejected.expectedFulfillmentCount = SwitcherAction.allCases.count * 2
        coordinator.onActionOutcome = { _, _, success, _ in XCTAssertFalse(success); rejected.fulfill() }
        for action in SwitcherAction.allCases {
            coordinator.perform(action, on: missing); coordinator.perform(action, on: stale)
        }
        await fulfillment(of: [rejected], timeout: 3)
    }
    @MainActor func testDuplicateTitleFixtureAgainstIndependentKeyWindowReport() async throws {
        try XCTSkipUnless(AXIsProcessTrusted(), "Tabnax test host needs user-granted Accessibility for the controlled cross-app fixture.")
        let host = Bundle.main.bundleURL.deletingLastPathComponent()
        let fixture = host.appendingPathComponent("TabnaxFixture.app/Contents/MacOS/TabnaxFixture")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixture.path), "Build the TabnaxFixture scheme first.")
        let report = FileManager.default.temporaryDirectory.appendingPathComponent("tabnax-fixture-\(UUID()).json")
        let process = Process(); process.executableURL = fixture; process.arguments = ["--report", report.path, "--cancel-first-quit", "--cancel-first-close"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; try? FileManager.default.removeItem(at: report) }
        // Bounded fixture-only readiness wait; never used by the production catalogue.
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: report),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["windows"] as? [[String: Any]], rows.count == 3 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let app = AXHandle(AXUIElementCreateApplication(process.processIdentifier))
        let (_, raw) = axValue(app.element, kAXWindowsAttribute)
        let windows = try XCTUnwrap(raw as? [AXUIElement])
        XCTAssertEqual(windows.count, 3)
        let chosen = try XCTUnwrap(windows.first { element in
            let (_, value) = axValue(element, kAXIdentifierAttribute)
            return value as? String == "fixture-0"
        })
        let info = Tabnax.ProcessInfo(token: UUID(), pid: process.processIdentifier, name: "Fixture", app: app)
        let id = TargetID(process: info.token, window: UUID())
        let record = WindowRecord(id: id, handle: AXHandle(chosen), title: "Tabnax duplicate fixture", minimized: false, available: true)
        let focus = FocusCoordinator()
        focus.update([id: FocusTarget(process: info, window: record)])
        let observed = expectation(description: "Exact AX focus observed")
        focus.onOutcome = { outcome in XCTAssertTrue(outcome.observed, outcome.message); observed.fulfill() }
        focus.submit(id)
        await fulfillment(of: [observed], timeout: 3)
        // AX focus can be observed before the fixture's main loop writes its report.
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: report),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["windows"] as? [[String: Any]],
               rows.first(where: { $0["key"] as? Bool == true })?["id"] as? String == "fixture-0" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let data = try Data(contentsOf: report)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let states = try XCTUnwrap(json["windows"] as? [[String: Any]])
        XCTAssertEqual(states.first { $0["key"] as? Bool == true }?["id"] as? String, "fixture-0")
        focus.cancel()

        let other = try XCTUnwrap(windows.first { element in
            let (_, value) = axValue(element, kAXIdentifierAttribute)
            return value as? String == "fixture-1"
        })
        let otherID = TargetID(process: info.token, window: UUID()), appID = TargetID(process: info.token)
        let otherRecord = WindowRecord(id: otherID, handle: AXHandle(other), title: record.title, minimized: false, available: true)
        focus.update([id: FocusTarget(process: info, window: record), otherID: FocusTarget(process: info, window: otherRecord), appID: FocusTarget(process: info, window: nil)])
        // Minimize only controlled fixture windows, then exercise the explicit restore
        // action against exact handles whose cached state deliberately still says visible.
        XCTAssertEqual(AXUIElementSetAttributeValue(chosen, kAXMinimizedAttribute as CFString, kCFBooleanTrue), .success)
        XCTAssertEqual(AXUIElementSetAttributeValue(other, kAXMinimizedAttribute as CFString, kCFBooleanTrue), .success)
        func fixtureReport() -> [String: Any] {
            guard let data = try? Data(contentsOf: report) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        for _ in 0..<150 {
            if (fixtureReport()["windows"] as? [[String: Any]])?.filter({ $0["minimized"] as? Bool == true }).count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual((fixtureReport()["windows"] as? [[String: Any]])?.filter { $0["minimized"] as? Bool == true }.count, 2)
        let restored = expectation(description: "Explicit restore requests completed")
        restored.expectedFulfillmentCount = 3
        focus.onActionOutcome = { action, _, success, message in
            XCTAssertEqual(action, .restoreWindow); XCTAssertTrue(success, message); restored.fulfill()
        }
        focus.perform(.restoreWindow, on: id); focus.perform(.restoreWindow, on: otherID)
        focus.perform(.restoreWindow, on: id) // Repeating restore must never toggle back.
        await fulfillment(of: [restored], timeout: 3)
        for _ in 0..<150 {
            if (fixtureReport()["windows"] as? [[String: Any]])?.allSatisfy({ $0["minimized"] as? Bool == false }) == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual((fixtureReport()["windows"] as? [[String: Any]])?.count, 3)
        XCTAssertTrue((fixtureReport()["windows"] as? [[String: Any]])?.allSatisfy { $0["minimized"] as? Bool == false } == true)

        func request(_ action: SwitcherAction, _ target: TargetID) async {
            let done = expectation(description: action.title)
            focus.onActionOutcome = { received, receivedID, success, message in
                XCTAssertEqual(received, action); XCTAssertEqual(receivedID, target)
                XCTAssertTrue(success, message); done.fulfill()
            }
            focus.perform(action, on: target)
            await fulfillment(of: [done], timeout: 4)
        }
        func waitForReport(_ check: ([String: Any]) -> Bool) async {
            for _ in 0..<150 {
                if check(fixtureReport()) { return }
                try? await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(check(fixtureReport()), "Fixture state did not change as requested")
        }
        func row(_ report: [String: Any], _ number: Int) -> [String: Any] {
            (report["windows"] as? [[String: Any]])?.first { $0["id"] as? String == "fixture-\(number)" } ?? [:]
        }
        await request(.minimizeWindow, id)
        await waitForReport { row($0, 0)["minimized"] as? Bool == true }
        XCTAssertEqual(row(fixtureReport(), 1)["minimized"] as? Bool, false)
        await request(.restoreWindow, id)
        await waitForReport { row($0, 0)["minimized"] as? Bool == false }
        await request(.hideApplication, appID)
        await waitForReport { $0["hidden"] as? Bool == true }
        await request(.unhideApplication, appID)
        await waitForReport { $0["hidden"] as? Bool == false }
        await request(.zoomWindow, id)
        await waitForReport { row($0, 0)["zoomed"] as? Bool == true }
        XCTAssertEqual(row(fixtureReport(), 1)["zoomed"] as? Bool, false)
        await request(.zoomWindow, id)
        await waitForReport { row($0, 0)["zoomed"] as? Bool == false }
        // The SDK's dedicated full-screen control handles both directions; no global key.
        await request(.toggleFullscreen, id)
        await waitForReport { row($0, 0)["fullscreen"] as? Bool == true }
        XCTAssertEqual(row(fixtureReport(), 1)["fullscreen"] as? Bool, false)
        await request(.toggleFullscreen, id)
        await waitForReport { row($0, 0)["fullscreen"] as? Bool == false }
        await request(.closeWindow, id)
        await waitForReport { ($0["closeRequests"] as? [String: Int])?["fixture-0"] == 1 }
        XCTAssertEqual(row(fixtureReport(), 0)["visible"] as? Bool, true, "The fixture cancelled the first normal close")
        await request(.closeWindow, id)
        await waitForReport { row($0, 0)["visible"] as? Bool == false }
        XCTAssertEqual(row(fixtureReport(), 1)["visible"] as? Bool, true, "The duplicate-title neighbor stays open")

        // A cancelled normal quit must leave the app alive and available for a later request.
        for count in 1...2 {
            let requested = expectation(description: "Normal quit requested")
            focus.onActionOutcome = { action, target, success, message in
                XCTAssertEqual(action, .quitApplication); XCTAssertEqual(target, appID)
                XCTAssertTrue(success, message); requested.fulfill()
            }
            focus.perform(.quitApplication, on: appID)
            await fulfillment(of: [requested], timeout: 3)
            for _ in 0..<50 {
                if fixtureReport()["quitRequests"] as? Int == count { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(fixtureReport()["quitRequests"] as? Int, count)
            if count == 1 { XCTAssertTrue(process.isRunning, "The fixture refused its first quit request") }
        }
        for _ in 0..<50 {
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(process.isRunning)
    }
}

final class SettingsContractTests: XCTestCase {
    @MainActor func testInvalidLetterEditKeepsLastValidPreviewConfiguration() {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        model.draft.choose(.left); model.stage()
        let valid = model.draft
        model.draft.alphabet = "aaaaaa"; model.stage()
        XCTAssertTrue(model.labelError.contains("6–26"))
        XCTAssertEqual(model.previewDocument.selection,valid)
        XCTAssertEqual(model.previewState.snapshot.alphabet,valid.alphabet)
        model.apply()
        XCTAssertEqual(preferences.document.selection,SelectionPreferences())
    }
    @MainActor func testUnappliedLettersFollowCatalogueChangesWithoutSaving() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        var source = SettingsModel.samples().resolvingTabOwners()
        var session = LabelSession(); _ = session.map(source)
        model.receive(source,session:session)
        model.draft.choose(.left); model.stage()
        let saved = preferences.document
        let extra = Target(id:TargetID(process:source.windows[0].id.process,window:UUID()),app:source.windows[0].app,title:"New window during draft",address:"")
        source.windows.append(extra); _ = session.map(source)
        model.receive(source,session:session)
        XCTAssertTrue(model.dirty)
        XCTAssertEqual(model.draft.alphabet,HandPreset.left.alphabet)
        XCTAssertEqual(preferences.document,saved)
        XCTAssertTrue(model.previewState.snapshot.windows.contains { $0.id == extra.id })
        XCTAssertEqual(model.previewState.snapshot.alphabet,HandPreset.left.alphabet)
        source.windows.removeAll { $0.id == extra.id }; _ = session.map(source)
        model.receive(source,session:session)
        XCTAssertFalse(model.previewState.snapshot.windows.contains { $0.id == extra.id })
    }
    @MainActor func testCleanDraftTracksSelectionChangedOutsideSettings() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        var changed = preferences.document; changed.selection.choose(.left)
        XCTAssertTrue(preferences.commit(changed))
        var session = LabelSession(selection:changed.selection)
        let source = SettingsModel.samples(); _ = session.map(source)
        model.receive(source,session:session)
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.draft,changed.selection)
        XCTAssertEqual(model.previewState.snapshot.alphabet,changed.selection.alphabet)
    }
    @MainActor func testAppPickerFailureDoesNotInvalidateValidLetters() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        model.draft.choose(.left); model.stage()
        model.addApplication(at:URL(fileURLWithPath:"/tmp/tabnax-missing-\(UUID()).app"))
        XCTAssertFalse(model.appError.isEmpty)
        XCTAssertTrue(model.labelError.isEmpty)
        XCTAssertTrue(model.dirty)
        model.apply()
        XCTAssertEqual(preferences.document.selection.alphabet,HandPreset.left.alphabet)
        XCTAssertFalse(model.dirty)
    }
    @MainActor func testLetterChangeCountUsesCurrentLayoutNamespace() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        for mode in [DisplayMode.shore,.fold,.canopy] {
            model.discard(); model.change { $0.mode = mode }
            model.draft.choose(.left); model.stage()
            var before = model.liveSession, after = model.candidate
            let old = before.map(model.raw), new = after.map(model.raw)
            let oldTargets = old.windows + old.tabs + old.apps
            let newTargets = new.windows + new.tabs + new.apps
            let grouped = mode == .fold || mode == .canopy
            let expected = newTargets.filter { target in
                guard let previous = oldTargets.first(where:{$0.id == target.id}) else { return true }
                return grouped ? previous.foldAddress != target.foldAddress : previous.address != target.address
            }.count
            XCTAssertEqual(model.changedLabels,expected,mode.rawValue)
            XCTAssertLessThanOrEqual(model.changedLabels,newTargets.count)
        }
    }
    @MainActor func testPersistenceUndoMigrationAndRecovery() throws {
        let name = "pl.tabnax.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        defaults.set("qwertyuiop",forKey:"alphabet")
        let preferences = Preferences(defaults:defaults)
        XCTAssertEqual(preferences.alphabet,"qwertyuiop")
        var d = preferences.document; d.selection.baseHand = .left; d.appearance.preset = .tabnax; d.mouse = .clickAndWheel
        XCTAssertTrue(preferences.commit(d))
        XCTAssertEqual(Preferences(defaults:defaults).document,d)
        preferences.undo(); XCTAssertEqual(preferences.document.mouse,.click)
        let bytes = Data("future or damaged file".utf8); defaults.set(bytes,forKey:"settingsDocument.v1")
        let damaged = Preferences(defaults:defaults)
        XCTAssertTrue(damaged.readOnly); XCTAssertFalse(damaged.commit(SettingsDocument()))
        XCTAssertEqual(defaults.data(forKey:"settingsDocument.v1"),bytes)
    }
    @MainActor func testPreviewDoesNotCommitDraftOrChangeRealWindows() throws {
        let name = "pl.tabnax.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:Preferences(defaults:defaults))
        model.draft.choose(.left); model.stage()
        XCTAssertTrue(model.dirty); XCTAssertEqual(preferences.alphabet,HandPreset.right.alphabet)
        XCTAssertEqual(model.previewState.snapshot.alphabet,HandPreset.left.alphabet)
        model.discard(); XCTAssertFalse(model.dirty)
        model.draft.alphabet = "jjjjjj"; model.stage(); XCTAssertFalse(model.labelError.isEmpty)
        model.draft.restoreOrder(); model.stage(); XCTAssertTrue(model.labelError.isEmpty)
    }
    func testHoldAndModifierSidesInActualRouter() {
        let selected = Locked<[TargetID]>([])
        let id = TargetID(process:UUID(),window:UUID())
        let snapshot = CatalogueSnapshot(windows:[Target(id:id,app:"A",title:"A",address:"j")])
        func event(_ code:UInt16,_ down:Bool=true,flags:CGEventFlags = []) -> (CGEventType,CGEvent) {
            let e = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!; e.flags=flags; return (down ? .keyDown : .keyUp,e)
        }
        var p = SettingsDocument(); p.activation.behavior = .hold
        let router = InputRouter(onState:{_ in},onSelect:{id in selected.withValue{$0.append(id)}},onCancel:{},onHealth:{_ in})
        let consumed = router.replayForTesting(snapshot:snapshot,settings:p,events:[event(49,flags:[.maskControl,.maskAlternate]),event(49,false),event(38),event(38,false)])
        XCTAssertEqual(consumed,[true,true,false,false]); XCTAssertTrue(selected.withValue{$0.isEmpty})
        p.activation.behavior = .latch; p.activation.side = .right
        let right = CGEventFlags(rawValue:CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x2000 | 0x40)
        let left = CGEventFlags(rawValue:CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | 0x1 | 0x20)
        let routed = router.replayForTesting(snapshot:snapshot,settings:p,events:[event(49,flags:left),event(49,false),event(49,flags:right),event(49,false),event(38),event(38,false)])
        XCTAssertEqual(routed,[false,false,true,true,true,true]); XCTAssertEqual(selected.withValue{$0},[id])
    }
    func testBrowserWireRejectsOversizedFrameAndHandlesFragmentation() throws {
        var fds:[Int32] = [0,0]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,&fds),0)
        defer { Darwin.close(fds[0]); Darwin.close(fds[1]) }
        let data = Data("{\"message\":\"hello\"}".utf8)
        XCTAssertTrue(BrowserWire.write(data,to:fds[0])); XCTAssertEqual(BrowserWire.read(from:fds[1]),data)
        var huge = UInt32(1_048_577).littleEndian
        _ = withUnsafeBytes(of:&huge) { Darwin.write(fds[0],$0.baseAddress!,4) }
        XCTAssertNil(BrowserWire.read(from:fds[1]))
    }
    func testBrowserPeerPreservesOrderAndClosesAStalledConnection() throws {
        var fds:[Int32] = [0,0]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,&fds),0)
        let peer = BrowserPeer(fds[0]); defer { peer.close(); Darwin.close(fds[1]) }
        peer.send(["sequence":1]); peer.send(["sequence":2])
        for sequence in 1...2 {
            let data = try XCTUnwrap(BrowserWire.read(from:fds[1]))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Int])
            XCTAssertEqual(object["sequence"],sequence)
        }
        // The receiver stops reading. Writes remain off the calling thread;
        // backpressure disconnects rather than retaining an unlimited backlog.
        let payload = String(repeating:"x",count:900_000)
        for _ in 0..<12 { peer.send(["payload":payload]) }
        peer.close()
        var timeout = timeval(tv_sec:2,tv_usec:0)
        setsockopt(fds[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
        var bytes = [UInt8](repeating:0,count:8192), read: Int = 0
        repeat { read = Darwin.read(fds[1],&bytes,bytes.count) } while read > 0
        XCTAssertEqual(read,0)
    }
}

extension SettingsContractTests {
    @MainActor func testMouseOffRetainsAccessibleTargetActionAcrossSixModes() {
        let id = TargetID(process:UUID(),window:UUID())
        let app = Target(id:TargetID(process:id.process),app:"A",title:"A",address:"j")
        let snapshot = CatalogueSnapshot(windows:[Target(id:id,app:"A",title:"Exact target",address:"j",foldAddress:"jj")],apps:[app])
        for mode in DisplayMode.allCases {
            let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true; presenter.previewSize = CGSize(width:620,height:460); presenter.settings.mouse = .off
            var state = SelectionState(); state.configure(mode:mode); state.update(snapshot); state.open()
            if mode == .fold { _ = state.handle(.prefix("j")) }
            var selected:TargetID?; presenter.onChoose = { value,_ in selected = value }
            presenter.present(state,icons:[:],status:"Test")
            func find(_ view:NSView) -> NSButton? {
                if let button = view as? NSButton,button.accessibilityIdentifier() == (mode == .fold || mode == .canopy ? "target-jj" : "target-j") { return button }
                return view.subviews.lazy.compactMap(find).first
            }
            let button = find(presenter.embeddedView)
            XCTAssertNotNil(button,mode.rawValue); XCTAssertTrue(button?.accessibilityPerformPress() == true); XCTAssertEqual(selected,id)
            presenter.dismiss()
        }
    }
}

extension SettingsContractTests {
    @MainActor func testInstalledBrowserScriptsCompileWithoutReadingTabs() throws {
        for browser in [BrowserID.arc,.chrome,.edge,.brave] {
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier:browser.bundleID) != nil else { continue }
            let tab = BrowserTabRecord(id:"identity-with-\"quote",window:"123",title:"Unused")
            for source in [BrowserCatalogue.queryScript(browser),BrowserCatalogue.focusScript(browser,tab:tab)] {
                let script = try XCTUnwrap(NSAppleScript(source:source)); var error:NSDictionary?
                XCTAssertTrue(script.compileAndReturnError(&error),"\(browser.title): \(String(describing:error))")
            }
        }
    }
    @MainActor func testFailedRuntimeChangePreservesWorkingPreferences() {
        let name = "pl.tabnax.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let preferences = Preferences(defaults:defaults); let before = preferences.document
        preferences.prepareCommit = { _,_ in throw SettingsError.invalid("Registration failed") }
        var candidate = before; candidate.launchAtLogin = true
        XCTAssertFalse(preferences.commit(candidate)); XCTAssertEqual(preferences.document,before); XCTAssertFalse(preferences.canUndo)
    }
}

extension SettingsContractTests {
    @MainActor func testAppearanceChoiceUpdatesSettingsWindowAndSystemRestoresInheritance() {
        let domain = "pl.tabnax.tests.\(UUID())"
        // A dedicated suite keeps the user's appearance unchanged.
        let isolated = UserDefaults(suiteName:domain)!
        defer { isolated.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:isolated)
        // Observe the same preferences used by the window.
        let window = SettingsController(preferences:preferences)
        var value = preferences.document; value.appearance.source = .dark
        XCTAssertTrue(preferences.commit(value)); XCTAssertEqual(window.window?.appearance?.name,.darkAqua)
        value.appearance.source = .light
        XCTAssertTrue(preferences.commit(value)); XCTAssertEqual(window.window?.appearance?.name,.aqua)
        value.appearance.source = .system
        XCTAssertTrue(preferences.commit(value)); XCTAssertNil(window.window?.appearance)
    }
    @MainActor func testRecordedCommandTabSavesAndCancelledRecordingsCannotOverwrite() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        // Use one isolated domain for both the write and the restart read.
        let isolated = UserDefaults(suiteName:domain)!
        defer { isolated.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:isolated), model = SettingsModel(preferences:preferences)
        model.recordShortcut(); let oldSession = try XCTUnwrap(model.recordingSession)
        model.acceptRecordedShortcut(.init(keyCode:0,modifiers:[]),session:oldSession)
        XCTAssertTrue(model.recording); XCTAssertEqual(preferences.document.activation,ActivationPreferences())
        model.acceptRecordedShortcut(.init(keyCode:48,modifiers:.maskCommand),session:oldSession)
        XCTAssertFalse(model.recording); XCTAssertTrue(preferences.document.activation.isCommandTab)
        XCTAssertEqual(shortcutTitle(preferences.document.activation),"⌘ Tab")
        XCTAssertTrue(Preferences(defaults:isolated).document.activation.isCommandTab)
        model.recordShortcut(); let newSession = try XCTUnwrap(model.recordingSession)
        model.acceptRecordedShortcut(.init(),session:oldSession)
        XCTAssertTrue(model.recording); XCTAssertTrue(preferences.document.activation.isCommandTab)
        model.acceptRecordedShortcut(.init(keyCode:53,modifiers:[]),session:newSession)
        XCTAssertFalse(model.recording)
        model.acceptRecordedShortcut(.init(),session:newSession)
        XCTAssertTrue(preferences.document.activation.isCommandTab)
        preferences.undo(); XCTAssertEqual(preferences.document.activation,ActivationPreferences())
    }
    func testShortcutRecorderSuspendsGlobalActivation() {
        let router = InputRouter(onState:{_ in},onSelect:{_ in XCTFail("Recorder must not select")},onCancel:{},onHealth:{_ in})
        let down = CGEvent(keyboardEventSource:nil,virtualKey:49,keyDown:true)!,up = CGEvent(keyboardEventSource:nil,virtualKey:49,keyDown:false)!
        down.flags = [.maskControl,.maskAlternate]
        router.suspendActivation(true)
        XCTAssertEqual(router.replayForTesting(snapshot:.init(),events:[(.keyDown,down),(.keyUp,up)]),[false,false])
        router.suspendActivation(false)
        XCTAssertEqual(router.replayForTesting(snapshot:.init(),events:[(.keyDown,down),(.keyUp,up)]),[true,true])
    }
}

extension SettingsContractTests {
    @MainActor func testLivePinDraftApplyAndPoolRecovery() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        let p = UUID(), w = TargetID(process:p,window:UUID()), t = TargetID(process:UUID(),window:UUID())
        let source = CatalogueSnapshot(windows:[Target(id:w,app:"A",title:"Window")],apps:[Target(id:TargetID(process:p),app:"A",title:"A")],tabs:[Target(id:t,app:"Arc",title:"Tab")])
        var session = LabelSession(); _ = session.map(source); try session.pin(w,code:"h")
        model.receive(source,session:session)
        // Under the default stable policy a two-key label starts with the hidden overflow letter.
        let code = try XCTUnwrap(AddressBook.overflowLetter(alphabet:session.selection.alphabet,policy:session.selection.policy)) + "k"
        model.pinTarget = t; model.pinCode = code; model.pin()
        XCTAssertTrue(model.dirty); XCTAssertTrue(model.labelError.isEmpty)
        // Windows and tabs now share the same pool namespace, so both pins live in `pins`.
        XCTAssertEqual(model.candidate.pins[w],"h"); XCTAssertEqual(model.candidate.pins[t],code)
        // A subsequent compatible edit keeps the staged pin.
        model.draft.interpretation = .characters; model.stage(); XCTAssertEqual(model.candidate.pins[t],code)
        var applied: LabelSession?; model.onApply = { applied = $0 }; model.apply()
        XCTAssertEqual(applied?.pins[t],code); XCTAssertFalse(model.dirty)
        model.resetLabels(); XCTAssertTrue(model.candidate.pins.isEmpty)
        // Moving into Apps and editing there must not retarget a staged pool reset.
        model.selectPane(.apps); model.draft.appShortcuts.enabled = true; model.stageApps()
        XCTAssertEqual(model.resetNamespace,.pool)
        XCTAssertTrue(model.candidate.pins.isEmpty)
        model.selectPane(.letters)
        model.discard(); XCTAssertEqual(model.liveSession.pins[t],code)
        var filtered = source; filtered.tabs[0].excluded = true
        model.receive(filtered,session:model.liveSession)
        XCTAssertTrue(model.previewState.snapshot.tabs.isEmpty)
    }
}

final class AppShortcutContractTests: XCTestCase {
    @MainActor func testApplyingFixedLetterUpdatesLiveAndPreviewAssignmentsInEveryNamespace() throws {
        for mode in [DisplayMode.shore, .fold, .canopy] {
            let domain = "pl.tabnax.tests.\(UUID())"
            let defaults = UserDefaults(suiteName:domain)!
            defer { defaults.removePersistentDomain(forName:domain) }
            let preferences = Preferences(defaults:defaults)
            var document = preferences.document
            document.mode = mode; document.selection.choose(.all); document.selection.policy = .mnemonic
            XCTAssertTrue(preferences.commit(document))
            let model = SettingsModel(preferences:preferences)
            let garageBand = Target(id:.init(process:UUID()),app:"GarageBand",title:"GarageBand",bundleID:"test.GarageBand")
            let ghostty = Target(id:.init(process:UUID()),app:"Ghostty",title:"Ghostty",bundleID:"test.Ghostty")
            let source = CatalogueSnapshot(windows:[garageBand,ghostty].map { app in
                Target(id:.init(process:app.id.process,window:UUID()),app:app.app,title:app.app + " window",bundleID:app.bundleID)
            },apps:[garageBand,ghostty])
            var session = LabelSession(selection:document.selection)
            let before = session.map(source)
            XCTAssertEqual(before.apps[0].foldAddress,"g")
            model.receive(source,session:session)
            model.draft.appShortcuts.enabled = true; model.draft.appShortcuts.launchClosedApps = true
            model.draft.appShortcuts.assignments = [.init(bundleID:ghostty.bundleID,name:ghostty.app,path:"/Applications/Ghostty.app",letter:"g")]
            model.stageApps()
            XCTAssertTrue(model.labelError.isEmpty)
            XCTAssertEqual(model.liveSession.map(source).apps[0].foldAddress,"g")
            XCTAssertNotEqual(model.previewState.snapshot.apps[0].foldAddress,"g")
            XCTAssertEqual(model.previewState.snapshot.apps[1].foldAddress,"g")
            model.previewKey(.letter("g"))
            XCTAssertTrue(model.previewMessage.contains("Ghostty"))
            var applied: LabelSession?; model.onApply = { applied = $0 }
            model.apply()
            XCTAssertTrue(model.labelError.isEmpty); XCTAssertFalse(model.dirty)
            var live = try XCTUnwrap(applied)
            let after = live.map(source)
            XCTAssertEqual(after.apps[1].address,"g"); XCTAssertEqual(after.apps[1].foldAddress,"g")
            XCTAssertNotEqual(after.apps[0].address,"g"); XCTAssertNotEqual(after.apps[0].foldAddress,"g")
            let saved = Preferences(defaults:defaults).document.selection
            var restarted = LabelSession(selection:saved)
            XCTAssertEqual(restarted.map(source).apps.map(\.foldAddress),after.apps.map(\.foldAddress))
            model.resetLabels(); model.apply()
            XCTAssertTrue(model.labelError.isEmpty)
            let reset = model.liveSession.map(source)
            XCTAssertEqual(reset.apps[1].address,"g"); XCTAssertEqual(reset.apps[1].foldAddress,"g")
            XCTAssertNotEqual(reset.apps[0].address,"g"); XCTAssertNotEqual(reset.apps[0].foldAddress,"g")
        }
    }
    @MainActor func testAssignmentDraftApplyDiscardPersistenceAndDisable() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        model.draft.appShortcuts.enabled = true; model.draft.appShortcuts.launchClosedApps = true
        model.addApplication(at:URL(fileURLWithPath:"/System/Applications/TextEdit.app"))
        XCTAssertTrue(model.labelError.isEmpty)
        XCTAssertTrue(preferences.document.selection.appShortcuts.assignments.isEmpty)
        let assignment = try XCTUnwrap(model.draft.appShortcuts.assignments.first)
        XCTAssertTrue(model.previewState.targets.contains { $0.bundleID == assignment.bundleID && !$0.isRunning })
        model.previewKey(.letter(assignment.letter))
        XCTAssertTrue(model.previewMessage.contains("Preview selected"))
        model.apply()
        XCTAssertEqual(Preferences(defaults:defaults).document.selection.appShortcuts.assignments,[assignment])
        model.draft.appShortcuts.assignments[0].letter = "c"; model.stageApps(); model.discard()
        XCTAssertEqual(model.draft.appShortcuts.assignments,[assignment])
        model.draft.appShortcuts.enabled = false; model.stageApps(); model.apply()
        XCTAssertFalse(preferences.document.selection.appShortcuts.enabled)
        XCTAssertEqual(preferences.document.selection.appShortcuts.assignments,[assignment])
        XCTAssertFalse(model.previewState.targets.contains { $0.bundleID == assignment.bundleID })
    }
    @MainActor func testClosedAppsRequireBothSwitchesAndMissingAppsRemainUnavailable() throws {
        let app = try ApplicationShortcuts.assignment(at:URL(fileURLWithPath:"/System/Applications/TextEdit.app"),letter:"t")
        let missing = AppAssignment(bundleID:"pl.tabnax.tests.missing",name:"Missing",path:"/missing.app",letter:"m")
        var p = AppShortcutPreferences(); p.assignments = [app,missing]
        XCTAssertTrue(ApplicationShortcuts.includingClosedApps(.init(),preferences:p).apps.isEmpty)
        p.enabled = true
        XCTAssertTrue(ApplicationShortcuts.includingClosedApps(.init(),preferences:p).apps.isEmpty)
        p.launchClosedApps = true
        let source = ApplicationShortcuts.includingClosedApps(.init(),preferences:p)
        XCTAssertEqual(source.apps.count,2); XCTAssertTrue(source.apps[0].available); XCTAssertFalse(source.apps[1].available)
        let running = Target(id:.init(process:UUID()),app:app.name,title:app.name,bundleID:app.bundleID)
        XCTAssertEqual(ApplicationShortcuts.includingClosedApps(.init(apps:[running]),preferences:p).apps.filter{$0.bundleID == app.bundleID}.count,1)
        var wrongPath = missing; wrongPath.path = app.path
        XCTAssertNil(ApplicationShortcuts.resolve(wrongPath))
    }
    func testAppsAreReachableWithBrowsersDisabledAndConsumesLaunchKeyup() {
        var settings = SettingsDocument(); settings.browsers.enabled = false
        let id = TargetID(process:UUID()), selected = Locked<[TargetID]>([])
        let router = InputRouter(onState:{_ in},onSelect:{ id in selected.withValue{$0.append(id)} },onCancel:{},onHealth:{_ in})
        func event(_ code:UInt16,_ down:Bool=true,flags:CGEventFlags = []) -> (CGEventType,CGEvent) {
            let e = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down)!; e.flags = flags; return (down ? .keyDown : .keyUp,e)
        }
        let result = router.replayForTesting(snapshot:.init(apps:[Target(id:id,app:"Calculator",title:"Calculator",address:"c",isRunning:false)]),settings:settings,events:[event(49,flags:[.maskControl,.maskAlternate]),event(49,false),event(8),event(8,false)])
        XCTAssertEqual(result,[true,true,true,true]); XCTAssertEqual(selected.withValue{$0},[id])
    }
    @MainActor func testLauncherCancellationAndRealFixtureLaunchThenActivation() async throws {
        let fixtureURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("TabnaxFixture.app")
        let assignment = try ApplicationShortcuts.assignment(at:fixtureURL,letter:"f")
        try XCTSkipUnless(NSRunningApplication.runningApplications(withBundleIdentifier:assignment.bundleID).isEmpty,"Do not interfere with an existing fixture process.")
        let launcher = ApplicationLauncher(), messages = Locked<[String]>([])
        launcher.onOutcome = { message in messages.withValue{$0.append(message)} }
        launcher.update([assignment.targetID:assignment]); XCTAssertTrue(launcher.submit(assignment.targetID)); launcher.cancel()
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier:assignment.bundleID).isEmpty)
        XCTAssertTrue(messages.withValue{$0.isEmpty})
        launcher.update([:]); XCTAssertFalse(launcher.submit(assignment.targetID))
        launcher.update([assignment.targetID:assignment]); XCTAssertTrue(launcher.submit(assignment.targetID))
        for _ in 0..<100 {
            if messages.withValue({!$0.isEmpty}) { break }
            try await Task.sleep(for:.milliseconds(50))
        }
        let running = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier:assignment.bundleID).first)
        defer { running.terminate() }
        XCTAssertEqual(messages.withValue{$0.first},"Opened \(assignment.name).")
        // Launch Services can return before the fixture finishes registration.
        // Test activation only once its running instance is ready to activate.
        for _ in 0..<100 {
            if running.isFinishedLaunching { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertTrue(running.isFinishedLaunching)
        let pid = running.processIdentifier
        XCTAssertTrue(launcher.submit(assignment.targetID))
        for _ in 0..<50 {
            if messages.withValue({$0.count > 1}) { break }
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier:assignment.bundleID).map(\.processIdentifier),[pid])
        XCTAssertEqual(messages.withValue{$0.last},"Activated \(assignment.name).")
    }
}

extension NativeContractTests {
    func testTypedCharactersSelectFixedLettersAndOverflowOutsideAlphabet() throws {
        var settings = SettingsDocument(); settings.selection.interpretation = .characters
        settings.selection.appShortcuts.enabled = true
        let fixed = AppAssignment(bundleID:"test.editor",name:"Editor",path:"/Applications/Editor.app",letter:"e")
        settings.selection.appShortcuts.assignments = [fixed]
        let app = Target(id:fixed.targetID,app:"Editor",title:"Editor",bundleID:fixed.bundleID)
        let windows = (0..<20).map { Target(id:.init(process:app.id.process,window:UUID()),app:"Editor",title:"Document \($0)") }
        var session = LabelSession(selection:settings.selection)
        let snapshot = session.map(.init(windows:windows,apps:[app]))
        let overflow = try XCTUnwrap(snapshot.windows.first { $0.address.count > 1 })
        for target in [snapshot.apps[0],overflow] {
            let selected = Locked<[TargetID]>([])
            let router = InputRouter(onState:{ _ in },onSelect:{ id in selected.withValue { $0.append(id) } },onCancel:{},onHealth:{ _ in })
            var events = [event(49,flags:[.maskControl,.maskAlternate]),event(49,false)]
            for character in target.address {
                let key = try XCTUnwrap(InputRouter.letters.first { $0.value == String(character) }?.key)
                let down = event(key)
                let text = Array(String(character).utf16)
                text.withUnsafeBufferPointer { down.1.keyboardSetUnicodeString(stringLength:text.count,unicodeString:$0.baseAddress!) }
                events += [down,event(key,false)]
            }
            XCTAssertTrue(router.replayForTesting(snapshot:snapshot,settings:settings,events:events).allSatisfy { $0 })
            XCTAssertEqual(selected.withValue { $0 },[target.id])
        }
    }
}

extension SettingsContractTests {
    @MainActor func testEveryImmediatePreferencePersistsAndUndoRestoresIt() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        let changes: [(inout SettingsDocument) -> Void] = [
            { $0.activation.behavior = .hold }, { $0.activation.side = .right },
            { $0.mouse = .off }, { $0.mouse = .clickAndWheel },
            { $0.includeMinimized = false }, { $0.includeHidden = false },
            { $0.display = .pointer }, { $0.positions["shore"] = { var p = Placement(); p.anchor = .bottomLeft; p.inset = 64; return p }() },
            { $0.appearance.source = .dark }, { $0.appearance.preset = .iris },
            { $0.appearance.scale = .extraLarge }, { $0.appearance.strongOutlines = true },
            { $0.appearance.setColor("#123456",token:"keyBg",dark:false) },
            { $0.appearance.setColor("#abcdef",token:"selection",dark:true) },
            { $0.browsers.enabled = false }, { $0.browsers.automatic = false },
            { $0.browsers.selected = [.arc] }, { $0.browsers.range = .activeWindow },
            { $0.mode = .canopy }
        ]
        for change in changes {
            let before = preferences.document
            model.change(change)
            XCTAssertNotEqual(preferences.document,before)
            XCTAssertEqual(Preferences(defaults:defaults).document,preferences.document)
            preferences.undo(); model.discard()
            XCTAssertEqual(preferences.document,before)
            XCTAssertEqual(Preferences(defaults:defaults).document,before)
        }
    }
    @MainActor func testPreviewFiltersKeepLabelsAndGroupedBrowserOwners() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let model = SettingsModel(preferences:Preferences(defaults:defaults))
        let original = model.previewState.snapshot
        model.change { $0.includeMinimized = false; $0.includeHidden = false }
        XCTAssertTrue(model.previewState.snapshot.windows.allSatisfy { !$0.hidden && !$0.minimized })
        model.change { $0.includeMinimized = true; $0.includeHidden = true }
        XCTAssertEqual(model.previewState.snapshot.windows.map(\.address),original.windows.map(\.address))
        model.change { $0.browsers.automatic = false; $0.browsers.selected = [.arc] }
        XCTAssertTrue(model.previewState.snapshot.tabs.allSatisfy { $0.app == "Arc" })
        XCTAssertFalse(model.previewState.snapshot.tabs.isEmpty)
        model.change { $0.browsers.enabled = false }
        XCTAssertTrue(model.previewState.snapshot.tabs.isEmpty)
        model.change { $0.browsers.enabled = true; $0.browsers.automatic = true }
        for mode in [DisplayMode.canopy,.fold] {
            model.change { $0.mode = mode }
            XCTAssertTrue(model.previewState.snapshot.tabs.allSatisfy { !$0.foldAddress.isEmpty && $0.owner != nil })
        }
        var session = LabelSession()
        let source = SettingsModel.samples()
        _ = session.map(source.resolvingTabOwners())
        model.receive(source,session:session)
        XCTAssertTrue(model.previewState.snapshot.tabs.allSatisfy { !$0.foldAddress.isEmpty })
    }
    @MainActor func testCanopyResetUsesGroupedLettersAndAppearanceUndoRestoresPreviewTone() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults), model = SettingsModel(preferences:preferences)
        model.change { $0.mode = .canopy }
        let source = SettingsModel.samples().resolvingTabOwners()
        var session = LabelSession(); let mapped = session.map(source)
        let window = mapped.windows[0], head = try XCTUnwrap(mapped.apps.first { $0.id.process == window.id.process }?.foldAddress)
        try session.pin(window.id,code:head + "h",fold:true)
        model.receive(source,session:session); model.resetLabels()
        XCTAssertEqual(model.resetNamespace,.fold); XCTAssertTrue(model.candidate.foldPins.isEmpty)
        XCTAssertFalse(model.liveSession.foldPins.isEmpty)
        model.discard(); XCTAssertFalse(model.candidate.foldPins.isEmpty)
        model.change { $0.appearance.source = .light }; model.change { $0.appearance.source = .dark }
        XCTAssertTrue(model.colorToneDark)
        preferences.undo(); model.discard()
        XCTAssertFalse(model.colorToneDark)
        model.selectPane(.appearance); XCTAssertEqual(model.previewDocument.appearance.source,.light)
    }
    @MainActor func testBrowserRangeDisableAndApprovalChangesPublishImmediately() throws {
        let gate = Locked<UInt64>(0), catalogue = BrowserCatalogue(focusGate:gate,observesSystem:false)
        let tabs = [BrowserTabRecord(id:"1",window:"1",title:"Current",focusedWindow:true),
                    BrowserTabRecord(id:"2",window:"2",title:"Other"),
                    BrowserTabRecord(id:"3",window:"3",title:"Private",incognito:true)]
        catalogue.seedForTesting(.chrome,tabs:tabs)
        XCTAssertEqual(catalogue.targets.count,2)
        let identities = catalogue.targets.map(\.id)
        var preferences = BrowserPreferences(); preferences.range = .activeBrowser
        catalogue.configure(preferences)
        XCTAssertTrue(catalogue.targets.allSatisfy(\.excluded))
        catalogue.select(identities[0]); XCTAssertEqual(gate.withValue { $0 },0)
        catalogue.activeBrowser = .chrome; preferences.range = .activeWindow; catalogue.configure(preferences)
        XCTAssertEqual(catalogue.targets.filter { !$0.excluded }.map(\.title),["Current"])
        preferences.enabled = false; catalogue.configure(preferences)
        XCTAssertTrue(catalogue.targets.allSatisfy { $0.excluded && !$0.available })
        preferences.enabled = true; preferences.range = .all; catalogue.configure(preferences)
        XCTAssertEqual(catalogue.targets.map(\.id),identities)
        var publications = 0, statusChanges = 0
        catalogue.onChange = { publications += 1 }
        catalogue.onStatusChange = { statusChanges += 1 }
        catalogue.permissionForTesting(-1743,browser:.chrome)
        XCTAssertEqual(publications,1); XCTAssertTrue(catalogue.targets.allSatisfy { !$0.available })
        XCTAssertEqual(catalogue.status[.chrome],"Automation approval required")
        catalogue.permissionForTesting(0,browser:.chrome)
        XCTAssertEqual(publications,1); XCTAssertEqual(statusChanges,2)
        XCTAssertEqual(catalogue.status[.chrome],"Available")
        // Approval alone is not a fresh successful browser read.
        XCTAssertTrue(catalogue.targets.allSatisfy { !$0.available })
    }
}

extension FilteringLayoutTests {
    @MainActor func testSearchAndBackControlsRouteToTheCurrentSession() throws {
        let presenter = SwitcherPresenter(); presenter.previewOnly = true
        defer { presenter.dismiss() }
        var state = SelectionState(); state.update(fixture()); state.open()
        var received: [SelectionKey] = [], sessions: [UInt64] = []
        presenter.onKey = { received.append($0); sessions.append($1) }
        presenter.present(state, icons: [:], status: "")
        let searchButton = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "begin-search" })
        XCTAssertTrue(searchButton.accessibilityPerformPress())
        XCTAssertEqual(received, [.beginSearch]); XCTAssertEqual(sessions, [state.session])
        _ = state.handle(.prefix("u")); presenter.present(state, icons: [:], status: "")
        let back = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "back-prefix" })
        XCTAssertFalse(back.isHidden); XCTAssertTrue(back.accessibilityPerformPress())
        XCTAssertEqual(received.last, .backspace)
        _ = state.handle(.beginSearch); presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(searchButton.isEnabled); XCTAssertTrue(back.isHidden)
        XCTAssertTrue(searchButton.accessibilityPerformPress()); XCTAssertEqual(received.last, .escape)
        XCTAssertFalse(try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSSearchField }.first).isHidden)
    }

    @MainActor func testKeyboardNavigationRevealsFoldAndLatticeBranches() throws {
        let apps = Array("abcdefghijklmnopqrstuvwxyz").map { letter in
            Target(id: .init(process: UUID()), app: "App \(letter)", title: "App \(letter)", address: String(letter), foldAddress: String(letter))
        }
        let windows = apps.flatMap { app in
            ["j", "k"].map { suffix in
                Target(id: .init(process: app.id.process, window: UUID()), app: app.app, title: "Window \(suffix)", address: app.address+suffix, foldAddress: app.address+suffix)
            }
        }
        for mode in [DisplayMode.fold, .lattice] {
            let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
            presenter.previewSize = CGSize(width: 620, height: 220)
            // Settings reparents this view into its preview host. Detach it here too,
            // so the unused switcher panel cannot clip the wider embedded fixture.
            presenter.embeddedView.removeFromSuperview()
            defer { presenter.dismiss() }
            let snapshot = CatalogueSnapshot(windows: windows, apps: mode == .fold ? apps : [], allocated: Set(windows.map(\.address)))
            var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
            presenter.present(state, icons: [:], status: "")
            let scroll = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSScrollView }.first)
            let document = try XCTUnwrap(scroll.documentView)
            let initialY = scroll.contentView.bounds.minY
            _ = state.handle(.highlight(.branch("z")))
            presenter.present(state, icons: [:], status: ""); presenter.embeddedView.layoutSubtreeIfNeeded()
            let branch = try XCTUnwrap(descendants(document).first { $0.accessibilityIdentifier() == (mode == .fold ? "family-z" : "cell-z") })
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, initialY, mode.rawValue)
            // Embedded previews are reparented by Settings; this test uses the scroll viewport
            // because the unused presenter panel still has its initial narrow frame.
            XCTAssertTrue(scroll.documentVisibleRect.contains(branch.frame), "Highlighted \(mode) branch must fit the scroll viewport")
        }
    }
}

final class LoginItemContractTests: XCTestCase {
    @MainActor func testMissingRegistrationIsRepairedAndVerified() throws {
        var state = SMAppService.Status.notFound
        var calls: [String] = []
        let service = LoginItemService(status:{ state }, register:{ calls.append("register"); state = .enabled }, unregister:{ calls.append("unregister"); state = .notRegistered }, repairRegistration:{ calls.append("repair") })
        try service.setEnabled(true)
        XCTAssertEqual(calls,["repair","register"])
        try service.setEnabled(true)
        XCTAssertEqual(calls,["repair","register"])
        try service.setEnabled(false)
        XCTAssertEqual(state,.notRegistered)
        try service.setEnabled(false)
        XCTAssertEqual(calls,["repair","register","unregister"])
    }

    @MainActor func testUnconfirmedRegistrationFailsAndApprovalIsRetained() throws {
        var state = SMAppService.Status.notRegistered
        var calls = 0
        var service = LoginItemService(status:{ state }, register:{ calls += 1 }, unregister:{}, repairRegistration:{})
        XCTAssertThrowsError(try service.setEnabled(true))
        service.register = { state = .requiresApproval; throw SettingsError.invalid("Approval needed") }
        try service.setEnabled(true)
        try service.setEnabled(true)
        XCTAssertEqual(state,.requiresApproval)
        XCTAssertEqual(calls,1)
        XCTAssertThrowsError(try service.setEnabled(false))
    }

    @MainActor func testCheckboxTracksSystemAndRetriesStaleSavedPreference() {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults)
        var document = preferences.document; document.launchAtLogin = true
        XCTAssertTrue(preferences.commit(document))
        var state = SMAppService.Status.notRegistered
        var registrations = 0
        let service = LoginItemService(status:{ state }, register:{ registrations += 1; state = .enabled }, unregister:{ state = .notRegistered }, repairRegistration:{})
        let model = SettingsModel(preferences:preferences,loginService:service)
        XCTAssertFalse(model.loginEnabled)
        model.login(true)
        XCTAssertEqual(registrations,1)
        XCTAssertTrue(model.loginEnabled)
        state = .notRegistered
        model.refreshLogin()
        XCTAssertFalse(model.loginEnabled)
        state = .enabled
        model.refreshLogin()
        model.login(false)
        XCTAssertFalse(model.loginEnabled)
        XCTAssertFalse(preferences.document.launchAtLogin)
    }

    @MainActor func testRegistrationFailurePreservesPreferenceAndShowsError() {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults)
        let service = LoginItemService(status:{ .notFound }, register:{ XCTFail("Must repair first") }, unregister:{}, repairRegistration:{ throw SettingsError.invalid("Repair failed") })
        let model = SettingsModel(preferences:preferences,loginService:service)
        model.login(true)
        XCTAssertFalse(model.loginEnabled)
        XCTAssertFalse(preferences.document.launchAtLogin)
        XCTAssertFalse(preferences.canUndo)
        XCTAssertTrue(model.loginError.contains("Repair failed"))
    }
}

final class BeaconVisibilityTests: XCTestCase {
    private let appPID: pid_t = 101
    private let overlayPID: pid_t = 202
    private let bounds = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func window(_ pid: pid_t, _ frame: CGRect, layer: Int = 0) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid,
         kCGWindowBounds as String: frame.dictionaryRepresentation,
         kCGWindowAlpha as String: 1.0,
         kCGWindowLayer as String: layer]
    }

    func testBeaconSurvivesGeometryRefreshWithItsOwnPlaqueOnTop() {
        let id = TargetID(process: UUID(), window: UUID())
        let candidate = GeometryCandidate(id: id, pid: appPID, bounds: bounds)
        let desktop = [window(appPID, bounds)]
        let plaque = window(overlayPID, CGRect(x: 112, y: 108, width: 330, height: 66), layer: 3)
        XCTAssertEqual(visibleGeometry([candidate], rows: desktop, overlayPID: overlayPID), [id])
        for _ in 0..<3 {
            XCTAssertEqual(visibleGeometry([candidate], rows: [plaque] + desktop, overlayPID: overlayPID), [id])
        }
    }

    func testNormalWindowsStillOccludeIncludingOurSettings() {
        let id = TargetID(process: UUID(), window: UUID())
        let candidate = GeometryCandidate(id: id, pid: appPID, bounds: bounds)
        for pid: pid_t in [overlayPID, 303] {
            let rows = [window(pid, bounds), window(appPID, bounds)]
            XCTAssertTrue(visibleGeometry([candidate], rows: rows, overlayPID: overlayPID).isEmpty)
        }
    }

    func testNotificationCenterDesktopContainerDoesNotHideWindowsOnAnyDisplay() {
        let notificationPID: pid_t = 404
        // Quartz points from a primary display plus displays to its left and right.
        let displays = [CGRect(x: 0, y: 0, width: 3840, height: 2160),
                        CGRect(x: -1728, y: 505, width: 1728, height: 1117),
                        CGRect(x: 3840, y: 0, width: 3360, height: 1890)]
        let candidates = displays.map { display in
            GeometryCandidate(id: .init(process: UUID(), window: UUID()), pid: appPID,
                              bounds: CGRect(x: display.minX+100, y: display.minY+100, width: 800, height: 600))
        }
        let appWindows = candidates.map { window($0.pid, $0.bounds) }
        for display in displays {
            let rows = [window(notificationPID, display, layer: 21)] + appWindows
            XCTAssertEqual(visibleGeometry(candidates, rows: rows, overlayPID: overlayPID,
                                           notificationCenterPIDs: [notificationPID], displayBounds: displays),
                           Set(candidates.map(\.id)))
        }
    }

    func testNotificationBannersAndOtherFullDisplayWindowsStillOcclude() {
        let notificationPID: pid_t = 404
        let display = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let candidate = GeometryCandidate(id: .init(process: UUID(), window: UUID()), pid: appPID, bounds: bounds)
        let obstructions = [
            window(notificationPID, CGRect(x: 100, y: 100, width: 350, height: 100), layer: 21),
            window(notificationPID, display, layer: 0),
            window(505, display, layer: 21),
            window(505, display, layer: 0)
        ]
        for obstruction in obstructions {
            XCTAssertTrue(visibleGeometry([candidate], rows: [obstruction, window(appPID, bounds)], overlayPID: overlayPID,
                                          notificationCenterPIDs: [notificationPID], displayBounds: [display]).isEmpty)
        }
        // Without a verified owner or matching display, keep the conservative check.
        let rows = [window(notificationPID, display, layer: 21), window(appPID, bounds)]
        XCTAssertTrue(visibleGeometry([candidate], rows: rows, overlayPID: overlayPID, displayBounds: [display]).isEmpty)
        XCTAssertTrue(visibleGeometry([candidate], rows: rows, overlayPID: overlayPID,
                                      notificationCenterPIDs: [notificationPID], displayBounds: [bounds]).isEmpty)
    }
}

extension FilteringLayoutTests {
    @MainActor func testRankedSearchRendersTheSameTargetsAsKeyboardAndPointerInEveryMode() throws {
        var snapshot = fixture()
        snapshot.windows[1].title = "Needle" // Strongest match belongs to the second app.
        let closed = Target(id: .init(process: UUID()), app: "Needle", title: "Needle", address: "c", foldAddress: "c", isRunning: false)
        snapshot.apps.insert(closed, at: 0)
        for mode in DisplayMode.allCases {
            let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
            defer { presenter.dismiss() }
            var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
            _ = state.handle(.beginSearch); _ = state.handle(.query("needle"))
            XCTAssertEqual(state.displayMatches.first?.id, snapshot.windows[1].id, mode.rawValue)
            var chosen: TargetID?
            presenter.onChoose = { id, _ in chosen = id }
            for target in state.displayMatches.filter(\.available) {
                XCTAssertEqual(state.highlightedAction, .target(target.id), mode.rawValue)
                presenter.present(state, icons: [:], status: "")
                let buttons = descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
                let rows = buttons.filter { $0.accessibilityIdentifier().hasPrefix("target-") }
                XCTAssertFalse(rows.contains { $0.accessibilityIdentifier() == "target-c" })
                let row = try XCTUnwrap(rows.first { $0.accessibilityIdentifier() == "target-" + target.address })
                XCTAssertEqual(row.accessibilityValue() as? String, "Selected", mode.rawValue)
                XCTAssertTrue(row.accessibilityPerformPress()); XCTAssertEqual(chosen, target.id)
                var entering = state; XCTAssertEqual(entering.handle(.enter), .selected(target.id))
                if mode == .fold {
                    let families = buttons.filter { $0.accessibilityIdentifier().hasPrefix("family-") }.sorted { $0.frame.minY < $1.frame.minY }
                    XCTAssertEqual(families.map { $0.accessibilityIdentifier() }, ["family-o", "family-i"])
                } else {
                    let ordered: [NSButton]
                    if mode == .canopy { ordered = rows.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) } }
                    else { ordered = rows.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) } }
                    XCTAssertEqual(ordered.map { $0.accessibilityIdentifier() }, state.displayMatches.map { "target-" + $0.address }, mode.rawValue)
                }
                _ = state.handle(.next)
            }
        }
    }
}

final class SearchChoicePersistenceTests: XCTestCase {
    @MainActor func testExplicitConsentPersistenceClearDisableUndoAndStaleCallbacks() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let isolated = UserDefaults(suiteName: domain)!
        defer { isolated.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: isolated)
        XCTAssertFalse(preferences.document.rememberSearchChoices)
        XCTAssertNil(preferences.searchMemory)
        var doc = preferences.document; doc.rememberSearchChoices = true
        XCTAssertTrue(preferences.commit(doc))
        var memory = try XCTUnwrap(preferences.searchMemory)
        let target = Target(id: .init(process: UUID(), window: UUID()), app: "Browser", title: "Private title")
        memory.remember(query: "private query", target: target)
        preferences.saveSearchChoices(memory)
        let data = try XCTUnwrap(isolated.data(forKey: Preferences.searchMemoryKey))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private title"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private query"))
        XCTAssertEqual(Preferences(defaults: isolated).searchMemory, memory)
        let older = memory
        memory.remember(query: "newer choice", target: target)
        preferences.saveSearchChoices(memory); preferences.saveSearchChoices(older)
        XCTAssertEqual(preferences.searchMemory, memory, "Delayed callbacks cannot overwrite newer choices")
        preferences.clearSearchChoices()
        XCTAssertEqual(preferences.searchMemory?.count, 0)
        XCTAssertNil(isolated.data(forKey: Preferences.searchMemoryKey))
        preferences.saveSearchChoices(memory) // A callback queued before Clear cannot restore it.
        XCTAssertNil(isolated.data(forKey: Preferences.searchMemoryKey))
        memory = try XCTUnwrap(preferences.searchMemory)
        memory.remember(query: "private query", target: target); preferences.saveSearchChoices(memory)
        doc.rememberSearchChoices = false; XCTAssertTrue(preferences.commit(doc))
        preferences.saveSearchChoices(memory)
        XCTAssertNil(preferences.searchMemory); XCTAssertNil(isolated.data(forKey: Preferences.searchMemoryKey))
        preferences.undo()
        XCTAssertTrue(preferences.document.rememberSearchChoices)
        XCTAssertEqual(preferences.searchMemory?.count, 0, "Undo restores consent, never deleted history")
        XCTAssertTrue(preferences.commit(SettingsDocument()))
        XCTAssertNil(preferences.searchMemory)
    }

    @MainActor func testDisabledAndDamagedMemoryNeverBreaksPreferences() throws {
        let domain = "pl.tabnax.tests.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data("invalid".utf8), forKey: Preferences.searchMemoryKey)
        let off = Preferences(defaults: defaults)
        XCTAssertFalse(off.readOnly); XCTAssertNil(off.searchMemory)
        XCTAssertNil(defaults.data(forKey: Preferences.searchMemoryKey))
        var doc = off.document; doc.rememberSearchChoices = true; XCTAssertTrue(off.commit(doc))
        for data in [Data("invalid".utf8), Data(repeating: 1, count: 65_000)] {
            defaults.set(data, forKey: Preferences.searchMemoryKey)
            let reloaded = Preferences(defaults: defaults)
            XCTAssertFalse(reloaded.readOnly); XCTAssertTrue(reloaded.document.rememberSearchChoices)
            XCTAssertEqual(reloaded.searchMemory?.count, 0)
        }
    }
}

extension SearchChoicePersistenceTests {
    @MainActor func testInputSelectionRecordsChoiceAndUsesItOnTheNextOpening() async throws {
        let domain = "pl.tabnax.tests.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        var settings = preferences.document; settings.rememberSearchChoices = true
        XCTAssertTrue(preferences.commit(settings))
        let a = Target(id: .init(process: UUID(), window: UUID()), app: "Alpha", title: "Project draft", address: "a")
        let b = Target(id: .init(process: UUID(), window: UUID()), app: "Beta", title: "Project review", address: "b")
        let saved = expectation(description: "Choice persisted"), ranked = expectation(description: "Next query prefers chosen target")
        let router = InputRouter(onState: { state in
            if state.active, state.query == "project", state.searchMemory?.count == 1 {
                XCTAssertEqual(state.highlightedAction, .target(b.id)); ranked.fulfill()
            }
        }, onSelect: { id in XCTAssertEqual(id, b.id) }, onCancel: {}, onHealth: { _ in })
        router.markRunningForTesting(); defer { router.clearRunningForTesting() }
        preferences.onSearchMemoryChange = { router.configureSearchMemory($0) }
        router.onSearchMemory = { memory in preferences.saveSearchChoices(memory); saved.fulfill() }
        router.configureSettings(settings); router.configureSearchMemory(preferences.searchMemory)
        router.update(.init(windows: [a,b])); router.open()
        router.key(.beginSearch); router.key(.query("project")); router.choose(b.id)
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(Preferences(defaults: defaults).searchMemory?.count, 1)
        router.open(); router.key(.beginSearch); router.key(.query("project"))
        await fulfillment(of: [ranked], timeout: 3)
        router.dismiss()
    }
}

final class ExclusionContractTests: XCTestCase {
    @MainActor func testForegroundInitializationPreviewOwnPanelsAndMissingIdentity() {
        var current: ForegroundIdentity? = .init(pid: 42, bundleID: "test.VM")
        var previews = Set<pid_t>()
        var registrations: [Bool] = []
        let router = ShortcutExceptionRouter(ownPID: 1, sample: { current }, isPreview: { previews.contains($0) }, configureFallback: { registrations.append($0) })
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID: "test.VM")]
        router.configure(rules, enabled: true)
        XCTAssertTrue(router.gate.passesThrough); XCTAssertEqual(registrations, [false])
        current = .init(pid: 1, bundleID: "test.Tabnax"); router.refresh()
        XCTAssertEqual(router.external?.bundleID, "test.VM"); XCTAssertFalse(registrations.last!)
        previews.insert(50); current = .init(pid: 50, bundleID: "test.Editor"); router.refresh()
        XCTAssertEqual(router.external?.bundleID, "test.VM")
        previews.removeAll(); router.refresh()
        XCTAssertFalse(router.gate.passesThrough); XCTAssertTrue(registrations.last!)
        current = .init(pid: 60, bundleID: nil); router.refresh()
        XCTAssertNil(router.external?.bundleID, "Missing ID must replace the previous app, never borrow its identity")
        XCTAssertTrue(router.permitsActivation())
        current = nil; router.refresh()
        XCTAssertTrue(router.gate.passesThrough); XCTAssertFalse(registrations.last!)
        current = .init(pid: 42, bundleID: "test.VM"); router.refresh()
        router.configure(.init(), enabled: true)
        XCTAssertTrue(router.permitsActivation(), "Rule changes and Undo apply to current foreground immediately")
        router.configure(rules, enabled: false); XCTAssertFalse(router.permitsActivation())
    }
    @MainActor func testCommittingAnAlreadyPreviewedExceptionNeedsNoNewActivationNotification() {
        var current: ForegroundIdentity? = .init(pid: 2, bundleID: "test.Editor")
        var preview = false
        var allowed = false
        let router = ShortcutExceptionRouter(ownPID: 1, sample: { current }, isPreview: { _ in preview }, configureFallback: { allowed = $0 })
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID: "test.VM")]
        router.configure(rules, enabled: true)
        current = .init(pid: 3, bundleID: "test.VM"); preview = true; router.refresh()
        XCTAssertTrue(allowed, "Highlighting a VM does not suspend switcher shortcuts")
        router.refresh(acceptPreview: true)
        XCTAssertFalse(allowed, "After the overlay closes, actual foreground owns the shortcuts even without another activation")
        preview = false; router.refresh(); XCTAssertTrue(router.gate.passesThrough)
    }
    @MainActor func testDeactivationDoesNotReregisterAgainstTheDepartingAppOrStaleNotification() {
        var current: ForegroundIdentity? = .init(pid: 2, bundleID: "test.Editor")
        var registrations: [Bool] = []
        let router = ShortcutExceptionRouter(ownPID: 1, sample: { current }, isPreview: { _ in false }, configureFallback: { registrations.append($0) })
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID: "test.VM")]
        router.configure(rules, enabled: true)
        router.beginTransition(from: 2); router.refresh()
        XCTAssertFalse(registrations.last!, "The workspace can still report the departing app until activation completes")
        current = .init(pid: 3, bundleID: "test.VM"); router.refresh()
        XCTAssertFalse(registrations.last!)
        current = .init(pid: 4, bundleID: "test.Editor"); router.refresh()
        XCTAssertTrue(registrations.last!)
        router.beginTransition(from: 2)
        XCTAssertTrue(registrations.last!, "An older queued deactivation must not strand the fallback disabled")
        router.beginTransition(from: 4); XCTAssertFalse(registrations.last!)
        router.activationCompleted(for: 4)
        XCTAssertTrue(registrations.last!, "Cancelled activation returning to the same PID must resume registration")
    }
    @MainActor func testCarbonRegistrationReallyReleasesAndDefersRestorationUntilKeyUp() {
        var held = false, registered = 0, unregistered = 0, fires = 0
        let fallback = HotKeyFallback(keyIsDown: { _ in held }, register: { _ in registered += 1; return true }, unregister: { unregistered += 1 })
        fallback.onFire = { fires += 1 }
        let activation = ActivationPreferences()
        held = true; fallback.configure(activation)
        XCTAssertFalse(fallback.isRegistered, "A launch while the chord is held must not reserve its remaining events")
        held = false; fallback.reconcile()
        XCTAssertTrue(fallback.isRegistered); XCTAssertEqual(registered, 1)
        let generation = fallback.registrationGeneration
        fallback.dispatch(generation: generation); XCTAssertEqual(fires, 1)
        fallback.configure(nil)
        XCTAssertFalse(fallback.isRegistered); XCTAssertEqual(unregistered, 1)
        fallback.dispatch(generation: generation); XCTAssertEqual(fires, 1)
        held = true; fallback.configure(activation); fallback.reconcile()
        XCTAssertEqual(registered, 1, "Original repeat/up stay with the exception app")
        held = false; fallback.reconcile()
        XCTAssertEqual(registered, 2)
        fallback.dispatch(generation: generation); XCTAssertEqual(fires, 1, "Old queued Carbon events cannot activate after re-registration")
        fallback.dispatch(generation: fallback.registrationGeneration); XCTAssertEqual(fires, 2)
        fallback.configure(nil)
        held = true; fallback.configure(activation); fallback.configure(nil)
        held = false; fallback.reconcile()
        XCTAssertFalse(fallback.isRegistered, "A pending retry cannot resurrect a disabled fallback")
    }
    @MainActor func testRealCarbonReservationIsReleasedAndRestoredForExceptionForeground() throws {
        // No events are posted or apps activated. Use an otherwise unused four-modifier
        // F20 chord, probe for a collision first, and release every registration on exit.
        var activation = ActivationPreferences()
        activation.keyCode = 90
        activation.modifiers = CGEventFlags([.maskCommand, .maskControl, .maskShift, .maskAlternate]).rawValue
        func probe() -> OSStatus {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(90, UInt32(cmdKey | controlKey | shiftKey | optionKey),
                EventHotKeyID(signature: 0x54455354, id: 7), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if let reference { UnregisterEventHotKey(reference) }
            return status
        }
        guard probe() == noErr else { throw XCTSkip("The isolated F20 test chord is already registered; no existing registration was changed.") }
        let fallback = HotKeyFallback()
        defer { fallback.stop() }
        var current: ForegroundIdentity? = .init(pid: 2, bundleID: "test.Editor")
        let router = ShortcutExceptionRouter(ownPID: 1, sample: { current }, isPreview: { _ in false }, configureFallback: { fallback.configure($0 ? activation : nil) })
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID: "test.VM")]
        router.configure(rules, enabled: true)
        XCTAssertTrue(fallback.isRegistered)
        XCTAssertEqual(probe(), OSStatus(eventHotKeyExistsErr))
        current = .init(pid: 3, bundleID: "test.VM"); router.refresh()
        XCTAssertFalse(fallback.isRegistered)
        XCTAssertEqual(probe(), noErr, "The OS must release the chord, not merely ignore our callback")
        current = .init(pid: 2, bundleID: "test.Editor"); router.refresh()
        XCTAssertTrue(fallback.isRegistered)
        XCTAssertEqual(probe(), OSStatus(eventHotKeyExistsErr))
        router.configure(rules, enabled: false)
        XCTAssertEqual(probe(), noErr)
    }
    @MainActor func testActivationRaceRechecksForegroundAfterRegistrationAndBeforeDispatch() {
        var current: ForegroundIdentity? = .init(pid: 2, bundleID: "test.Editor")
        var registers = 0, unregisters = 0
        let fallback = HotKeyFallback(keyIsDown: { _ in false }, register: { _ in
            registers += 1; current = .init(pid: 3, bundleID: "test.VM"); return true
        }, unregister: { unregisters += 1 })
        let router = ShortcutExceptionRouter(ownPID: 1, sample: { current }, isPreview: { _ in false }, configureFallback: { fallback.configure($0 ? .init() : nil) })
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID: "test.VM")]
        router.configure(rules, enabled: true)
        XCTAssertEqual(registers, 1); XCTAssertEqual(unregisters, 1)
        XCTAssertFalse(fallback.isRegistered); XCTAssertTrue(router.gate.passesThrough)
        XCTAssertFalse(router.permitsActivation())
        // A stale activation notification refreshes actual foreground instead of using its old payload.
        router.refresh(); XCTAssertFalse(fallback.isRegistered)
    }
    @MainActor func testDeferredRegistrationRechecksForegroundWhenTheKeyIsReleased() {
        var held = true, count = 0
        var current: ForegroundIdentity? = .init(pid: 2, bundleID: "test.Editor")
        let fallback = HotKeyFallback(keyIsDown: { _ in held }, register: { _ in count += 1; return true }, unregister: {})
        let router = ShortcutExceptionRouter(ownPID: 1, sample: { current }, isPreview: { _ in false }, configureFallback: { fallback.configure($0 ? .init() : nil) })
        fallback.onRetryRegistration = { router.refresh() }
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID: "test.VM")]
        router.configure(rules, enabled: true)
        XCTAssertEqual(count, 0)
        held = false; current = .init(pid: 3, bundleID: "test.VM")
        fallback.retryRegistration()
        XCTAssertEqual(count, 0, "Even before activation notification delivery, a queued retry must see current foreground")
        XCTAssertFalse(fallback.isRegistered)
        fallback.stop()
    }
    func testExceptionDoesNotBypassMouseCancellationOrPassiveKeyFocusGuards() {
        let cancels = Locked(0), passive = Locked(0)
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: { cancels.withValue { $0 += 1 } }, onPassiveKey: { passive.withValue { $0 += 1 } }, onHealth: { _ in })
        router.shortcutExceptionGate.set(true)
        let mouse = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        XCTAssertEqual(router.replayForTesting(snapshot: .init(), events: [(.leftMouseDown, mouse), event(0)]), [false, false])
        XCTAssertEqual(cancels.withValue { $0 }, 1)
        XCTAssertEqual(passive.withValue { $0 }, 1)
    }
    private func event(_ code: UInt16, down: Bool = true, repeatKey: Bool = false, flags: CGEventFlags = []) -> (CGEventType, CGEvent) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags; event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        return (down ? .keyDown : .keyUp, event)
    }
    func testExceptionKeySequencesPassIntactAcrossRuleAndForegroundChanges() {
        var settings = SettingsDocument(); settings.activation.useCommandTab()
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: {}, onHealth: { _ in })
        router.shortcutExceptionGate.set(true)
        XCTAssertEqual(router.replayForTesting(snapshot: .init(), settings: settings, events: [event(48, flags: .maskCommand)]), [false])
        router.shortcutExceptionGate.set(false)
        XCTAssertEqual(router.replayForTesting(snapshot: .init(), settings: settings, events: [event(48, repeatKey: true, flags: .maskCommand), event(48, down: false, flags: .maskCommand)]), [false, false])
        XCTAssertFalse(router.presentationPendingForTesting)
        XCTAssertEqual(router.replayForTesting(snapshot: .init(), settings: settings, events: [event(48, flags: .maskCommand)]), [true])
        router.shortcutExceptionGate.set(true)
        XCTAssertEqual(router.replayForTesting(snapshot: .init(), settings: settings, events: [event(48, repeatKey: true, flags: .maskCommand), event(48, down: false, flags: .maskCommand)]), [true, true], "Previously owned sequences remain paired")
    }
    func testRecorderStillReceivesShortcutsWhenExternalAppIsAnException() {
        let received = Locked<[Shortcut]>([])
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: {}, onHealth: { _ in })
        router.shortcutExceptionGate.set(true)
        router.recordShortcut { shortcut in received.withValue { $0.append(shortcut) } }
        XCTAssertEqual(router.replayForTesting(snapshot: .init(), events: [event(48, flags: .maskCommand), event(48, repeatKey: true, flags: .maskCommand), event(48, down: false, flags: .maskCommand)]), [true, true, true])
        XCTAssertEqual(received.withValue { $0.count }, 1)
    }
    @MainActor func testExclusionPersistenceUndoAndPreviewAcrossAllSixLayouts() throws {
        let domain = "pl.tabnax.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        // Use one model's actual preference object so the preview observes saved changes.
        let activeModel = SettingsModel(preferences: preferences)
        activeModel.addAppRule(bundleID: "com.apple.Safari", exception: false)
        activeModel.addAppRule(bundleID: "test.UninstalledVM", exception: true)
        activeModel.change { $0.exclusions.titles = [.init(bundleID: "com.apple.dt.Xcode", pattern: "Tabnax · Settings")] }
        XCTAssertFalse(preferences.readOnly)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.document.exclusions, preferences.document.exclusions)
        XCTAssertTrue(restored.document.exclusions.passesActivationShortcuts(to: "test.UninstalledVM"))
        let original = activeModel.liveSession.mapForTest(SettingsModel.samples())
        for mode in DisplayMode.allCases {
            activeModel.change { $0.mode = mode }
            let state = activeModel.previewState
            XCTAssertFalse(state.snapshot.apps.contains { $0.bundleID == "com.apple.Safari" })
            XCTAssertFalse(state.snapshot.windows.contains { $0.title == "Tabnax · Settings" })
            XCTAssertTrue(state.snapshot.windows.contains { $0.title == "Review changes" })
            XCTAssertNil(InputRouter.previewTarget(in: state, enabled: true).flatMap { state.snapshot.suppressedIDs.contains($0) ? $0 : nil })
            for target in state.snapshot.windows { XCTAssertEqual(target.address, original.windows.first { $0.id == target.id }?.address) }
        }
        activeModel.change { $0.exclusions = .init() }
        XCTAssertTrue(activeModel.previewState.snapshot.apps.contains { $0.bundleID == "com.apple.Safari" })
        preferences.undo(); activeModel.discard()
        XCTAssertFalse(activeModel.previewState.snapshot.apps.contains { $0.bundleID == "com.apple.Safari" })
        XCTAssertTrue(preferences.document.exclusions.passesActivationShortcuts(to: "test.UninstalledVM"))
    }
}

private extension LabelSession {
    func mapForTest(_ source: CatalogueSnapshot) -> CatalogueSnapshot { var session = self; return session.map(source.resolvingTabOwners()) }
}

extension FilteringLayoutTests {
    @MainActor func testEveryOrderingRendersAndCyclesTheSameRowsInAllLayouts() throws {
        var snapshot = fixture()
        snapshot.windows[0].title = "Zulu"; snapshot.windows[0].hidden = true
        snapshot.windows[1].title = "Alpha"; snapshot.windows[1].minimized = true
        snapshot.windows[2].title = "Bravo"; snapshot.windows[2].elsewhere = true
        snapshot.history.observe(snapshot.windows[2].id)
        snapshot.apps.append(Target(id: .init(process: UUID()), app: "Closed", title: "Closed", address: "c", foldAddress: "c", isRunning: false))
        for mode in DisplayMode.allCases {
            for order in TraversalOrder.allCases {
                let presenter = SwitcherPresenter(); presenter.previewOnly = true; presenter.embedded = true
                defer { presenter.dismiss() }
                var state = SelectionState(); state.configure(mode: mode); state.configure(ordering: order); state.update(snapshot); state.open()
                func verify(_ current: SelectionState) throws {
                    presenter.present(current, icons: [:], status: "")
                    let buttons = descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
                    let prefix = mode == .fold && current.prefix.isEmpty ? "family-" : "target-"
                    let rows = buttons.filter { ($0.accessibilityIdentifier().hasPrefix(prefix) || (mode == .lattice && $0.accessibilityIdentifier().hasPrefix("cell-"))) && $0.isEnabled }
                    let ordered: [NSButton]
                    if mode == .canopy { ordered = rows.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) } }
                    else { ordered = rows.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) } }
                    let expected = current.navigationItems.map { item -> String in
                        switch item.action {
                        case .target(let id): return "target-" + current.targets.first { $0.id == id }!.address
                        case .branch(let code): return (mode == .fold ? "family-" : "cell-") + code
                        }
                    }
                    XCTAssertEqual(ordered.map { $0.accessibilityIdentifier() }, expected, "\(mode) / \(order)")
                    if case .target(let id)? = current.highlightedAction {
                        let target = try XCTUnwrap(current.targets.first { $0.id == id })
                        let row = try XCTUnwrap(rows.first { $0.accessibilityIdentifier() == "target-" + target.address })
                        XCTAssertEqual(row.accessibilityValue() as? String, "Selected")
                        var selected: TargetID?
                        presenter.onChoose = { id, _ in selected = id }
                        XCTAssertTrue(row.accessibilityPerformPress()); XCTAssertEqual(selected, id)
                    }
                }
                let items = state.navigationItems
                _ = state.handle(.highlight(items[0].action))
                for item in items {
                    XCTAssertEqual(state.highlightedAction, item.action)
                    try verify(state)
                    if mode == .fold {
                        var family = state; _ = family.handle(.enter)
                        for child in family.navigationItems {
                            _ = family.handle(.highlight(child.action)); try verify(family)
                        }
                    }
                    _ = state.handle(.next)
                }
                // Real native rows keep their order after metadata/history refresh.
                var latest = snapshot; latest.windows.reverse(); latest.apps.reverse()
                latest.windows[0].title = "Changed"; latest.history.observe(snapshot.windows[0].id)
                state.update(state.snapshot.reconcilingLive(latest)); try verify(state)
            }
        }
    }
}

final class OrderingContractTests: XCTestCase {
    @MainActor func testPreferencesPersistencePreviewAndUndo() throws {
        let domain = "pl.tabnax.tests.\(UUID())", defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.document.traversalOrder, .stable)
        let model = SettingsModel(preferences: preferences)
        for order in TraversalOrder.allCases {
            var doc = preferences.document; doc.traversalOrder = order
            XCTAssertTrue(preferences.commit(doc)); model.refreshPreview()
            XCTAssertEqual(Preferences(defaults: defaults).document.traversalOrder, order)
            XCTAssertEqual(model.previewState.ordering, order)
        }
        preferences.undo()
        XCTAssertEqual(preferences.document.traversalOrder, .alphabetical)
        XCTAssertTrue(SettingsModel.previewRelevantKeyPaths.contains(\SettingsDocument.traversalOrder))
    }
    func testFocusObservationRejectsReadsThatCrossPreviewOrFocusTransitions() {
        let focus = FocusCoordinator()
        let before = focus.observationToken
        XCTAssertNotNil(before)
        XCTAssertTrue(WindowCatalogue.acceptsObservation(started: before, current: before))
        // Even a cancelled/unavailable preview changes generation. No user app is touched.
        focus.preview(.init(process: UUID(), window: UUID()))
        focus.cancel()
        XCTAssertFalse(WindowCatalogue.acceptsObservation(started: before, current: focus.observationToken))
        XCTAssertFalse(WindowCatalogue.acceptsObservation(started: nil, current: focus.observationToken))
        XCTAssertFalse(WindowCatalogue.acceptsObservation(started: before, current: nil))
        let after = focus.observationToken
        XCTAssertTrue(WindowCatalogue.acceptsObservation(started: after, current: after))
        focus.markPreviewActivationForTesting(42)
        XCTAssertNil(focus.observationToken)
        focus.cancel() // Opening a menu or dismissing must not turn a preview into history.
        XCTAssertNil(focus.observationToken)
        XCTAssertTrue(focus.isPreviewActivation(42))
        focus.externalActivation(42) // Late notification from the same preview.
        XCTAssertNil(focus.observationToken)
        focus.externalActivation(43) // A genuinely different foreground app resumes observation.
        XCTAssertNotNil(focus.observationToken)
        XCTAssertFalse(focus.isPreviewActivation(42))
        XCTAssertFalse(WindowCatalogue.acceptsObservation(started: after, current: focus.observationToken))
    }
}

extension NativeContractTests {
    func testCommandTabCyclesChosenOrderAndCommitsExactHighlightInEveryMode() {
        let owners = [UUID(), UUID(), UUID()]
        let windows = ["Charlie", "Alpha", "Bravo"].enumerated().map { index, name in
            Target(id: .init(process: owners[index], window: UUID()), app: name, title: name,
                   address: ["j", "k", "l"][index], minimized: index == 1,
                   foldAddress: ["uj", "ij", "oj"][index], elsewhere: index == 2)
        }
        let apps = windows.enumerated().map { index, window in
            Target(id: .init(process: window.id.process), app: window.app, title: window.app,
                   address: ["u", "i", "o"][index], foldAddress: ["u", "i", "o"][index])
        }
        var history = FocusHistory(); for target in windows { history.observe(target.id) }
        let snapshot = CatalogueSnapshot(windows: windows, apps: apps, history: history)
        for mode in DisplayMode.allCases { for order in TraversalOrder.allCases { for behavior in ActivationBehavior.allCases {
            var expected = SelectionState(); expected.configure(mode: mode); expected.configure(ordering: order); expected.update(snapshot); expected.open()
            _ = expected.handle(.next)
            guard case .selected(let id) = expected.commitHighlight() else { XCTFail("Missing selection"); continue }
            let chosen = Locked<[TargetID]>([])
            let router = InputRouter(onState: { _ in }, onSelect: { id in chosen.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
            var settings = SettingsDocument(); settings.traversalOrder = order; settings.activation.useCommandTab(); settings.activation.behavior = behavior
            let consumed = router.replayForTesting(snapshot: snapshot, mode: mode, settings: settings, events: [
                event(48, flags: .maskCommand), event(48, false, flags: .maskCommand),
                event(48, flags: .maskCommand), event(48, false, flags: .maskCommand), modifiers([])
            ])
            XCTAssertTrue(consumed.prefix(4).allSatisfy { $0 }, "\(mode) / \(order) / \(behavior)")
            XCTAssertEqual(chosen.withValue { $0 }, [id], "\(mode) / \(order) / \(behavior)")
            XCTAssertEqual(snapshot.history, history)
        } } }
    }
}

final class SearchShortcutContractTests: XCTestCase {
    private func event(_ code: UInt16, _ type: CGEventType = .keyDown, flags: CGEventFlags = [], repeated: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: type != .keyUp)!
        event.type = type; event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeated ? 1 : 0)
        return event
    }
    private var snapshot: CatalogueSnapshot {
        let a = Target(id: .init(process: UUID(), window: UUID()), app: "Alpha", title: "First", address: "a", foldAddress: "aa")
        let b = Target(id: .init(process: UUID(), window: UUID()), app: "Beta", title: "Second", address: "b", foldAddress: "bb")
        var history = FocusHistory(); history.observe(b.id); history.observe(a.id)
        return .init(windows: [a,b], history: history)
    }
    func testSearchTapOpensEveryLayoutLatchedAndOwnsTriggerAcrossReleaseRepeat() {
        for mode in DisplayMode.allCases {
            for behavior in ActivationBehavior.allCases {
                var settings = SettingsDocument(); settings.searchActivation.enabled = true
                settings.activation.behavior = behavior; settings.activation.quietReturn = true
                let selected = Locked<[TargetID]>([])
                let router = InputRouter(onState: { _ in }, onSelect: { id in selected.withValue { $0.append(id) } }, onCancel: {}, onHealth: { _ in })
                let chord = CGEventFlags(rawValue: settings.searchActivation.shortcut.modifiers)
                let events = [event(49, flags: chord), event(49, flags: chord, repeated: true), event(49, .keyUp, flags: chord),
                              event(59, .flagsChanged), event(49, flags: chord), event(49, .keyUp), event(59, .flagsChanged)]
                XCTAssertEqual(router.replayForTesting(snapshot: snapshot, mode: mode, settings: settings, events: events.map { ($0.type,$0) }), [true,true,true,false,true,true,false])
                XCTAssertTrue(router.stateForTesting.active); XCTAssertEqual(router.stateForTesting.query, "")
                XCTAssertEqual(router.stateForTesting.session, 1, "Repeating search preserves the session")
                XCTAssertTrue(router.presentationPendingForTesting, "Quiet return never hides search")
                XCTAssertTrue(selected.withValue { $0.isEmpty })
            }
        }
    }
    func testSearchInvocationDisarmsExistingHoldSessionAndKeepsFrozenOrdering() {
        var settings = SettingsDocument(); settings.searchActivation.enabled = true
        settings.activation.behavior = .hold; settings.activation.quietReturn = true
        let router = InputRouter(onState: { _ in }, onSelect: { _ in XCTFail("Search must not commit on release") }, onCancel: {}, onHealth: { _ in })
        let events = [event(49, flags: [.maskControl,.maskAlternate]), event(49,.keyUp),
                      event(49, flags: [.maskControl,.maskShift]), event(49,.keyUp), event(59,.flagsChanged)]
        let source = snapshot
        _ = router.replayForTesting(snapshot: source, settings: settings, events: events.map { ($0.type,$0) })
        XCTAssertEqual(router.stateForTesting.session, 1)
        XCTAssertEqual(router.stateForTesting.query, ""); XCTAssertEqual(router.stateForTesting.openingHistory, source.history)
    }
    func testDisabledSideSpecificExceptionSuspensionAndMenuOwnership() {
        var settings = SettingsDocument()
        let router = InputRouter(onState: { _ in }, onSelect: { _ in }, onCancel: {}, onHealth: { _ in })
        func replay(_ events: [CGEvent]) -> [Bool] { router.replayForTesting(snapshot: snapshot, settings: settings, events: events.map { ($0.type,$0) }) }
        let chord: CGEventFlags = [.maskControl,.maskShift]
        XCTAssertEqual(replay([event(49, flags: chord),event(49,.keyUp)]),[false,false])
        settings.searchActivation.enabled = true; settings.searchActivation.shortcut.side = .left
        XCTAssertEqual(replay([event(49,flags: chord),event(49,.keyUp)]),[false,false])
        let left = CGEventFlags(rawValue: chord.rawValue | 0x1 | 0x2)
        router.shortcutExceptionGate.set(true)
        XCTAssertEqual(replay([event(49,flags: left)]),[false])
        router.shortcutExceptionGate.set(false)
        XCTAssertEqual(replay([event(49,flags: left,repeated:true),event(49,.keyUp)]),[false,false])
        router.suspendActivation(true)
        XCTAssertEqual(replay([event(49,flags:left),event(49,.keyUp)]),[false,false])
        let recordings = Locked(0)
        router.recordShortcut { _ in recordings.withValue { $0 += 1 } }
        XCTAssertEqual(replay([event(49,flags:left),event(49,.keyUp)]),[true,true]); XCTAssertEqual(recordings.withValue { $0 },1)
        router.recordShortcut(using:nil)
        XCTAssertEqual(replay([event(49,flags:left),event(49,.keyUp)]),[true,true])
        router.setMenuTracking(true, session:router.stateForTesting.session)
        XCTAssertEqual(replay([event(49,flags:left),event(49,.keyUp)]),[true,true])
        XCTAssertEqual(router.stateForTesting.session,1)
    }
    @MainActor func testEarlyTextIsQueuedToNativeEditorThenEnterSelectsExactResult() async throws {
        for mode in DisplayMode.allCases {
            var settings = SettingsDocument(); settings.searchActivation.enabled = true
            settings.activation.behavior = .hold; settings.activation.quietReturn = true
            let presenter = SwitcherPresenter(); presenter.allowsDesktopSpotlight = false
            presenter.settings = settings
            let selected = expectation(description: "Native Enter selected in \(mode)")
            let source = snapshot
            let router = InputRouter(onState: { state in presenter.present(state, icons: [:], status: "") },
                onSelect: { id in XCTAssertEqual(id, source.windows[1].id); selected.fulfill() }, onCancel: {}, onHealth: { _ in })
            router.onSearchFocus = { presenter.focusSearch(session:$0) }
            router.onSearchInput = { presenter.deliverSearchInput($0,session:$1) }
            presenter.onKey = { router.key($0,session:$1) }
            let text = event(11); var characters = Array("Beta".utf16)
            text.keyboardSetUnicodeString(stringLength:characters.count,unicodeString:&characters)
            let keys = [event(49,flags:[.maskControl,.maskShift]),event(49,.keyUp),event(59,.flagsChanged),text,event(11,.keyUp),event(36),event(36,.keyUp)]
            XCTAssertEqual(router.replayForTesting(snapshot:source, mode:mode, settings:settings, events:keys.map { ($0.type,$0) }),[true,true,false,true,true,true,true])
            router.markRunningForTesting()
            await fulfillment(of:[selected],timeout:3)
            router.clearRunningForTesting(); presenter.dismiss()
        }
    }
    @MainActor func testRecordingPersistenceConflictAndLegacyRecovery() throws {
        let domain = "pl.tabnax.tests.\(UUID())", defaults = UserDefaults(suiteName:domain)!
        defer { defaults.removePersistentDomain(forName:domain) }
        let preferences = Preferences(defaults:defaults)
        var doc = preferences.document; doc.mode = .fold; doc.activation.keyCode = 0; doc.activation.modifiers = 1 << 17
        defaults.set(try JSONEncoder().encode(doc),forKey:"settingsDocument.v1")
        let migrated = Preferences(defaults:defaults)
        XCTAssertFalse(migrated.readOnly); XCTAssertEqual(migrated.document.mode,.fold)
        XCTAssertEqual(migrated.document.activation,ActivationPreferences())
        let model = SettingsModel(preferences:migrated)
        var enabled = migrated.document; enabled.searchActivation.enabled = true
        XCTAssertTrue(migrated.commit(enabled))
        model.recordShortcut(.search)
        let session = try XCTUnwrap(model.recordingSession)
        model.acceptRecordedShortcut(.init(keyCode:0,modifiers:.maskShift),session:session)
        XCTAssertTrue(model.recording); XCTAssertEqual(migrated.document.searchActivation.shortcut,SearchActivationPreferences.suggestedShortcut)
        model.acceptRecordedShortcut(.init(keyCode:49,modifiers:[.maskControl,.maskAlternate]),session:session)
        XCTAssertTrue(model.recording); XCTAssertTrue(migrated.message.contains("overlaps"))
        model.acceptRecordedShortcut(.init(keyCode:40,modifiers:[.maskControl,.maskShift]),session:session)
        XCTAssertFalse(model.recording); XCTAssertEqual(migrated.document.searchActivation.shortcut.keyCode,40)
        XCTAssertEqual(Preferences(defaults:defaults).document,migrated.document)
        model.recordShortcut(.main); let cancelled = try XCTUnwrap(model.recordingSession)
        model.acceptRecordedShortcut(.init(keyCode:53,modifiers:[]),session:cancelled)
        model.acceptRecordedShortcut(.init(keyCode:1,modifiers:.maskCommand),session:cancelled)
        XCTAssertEqual(migrated.document.activation,ActivationPreferences())
        model.restoreDefaults(); XCTAssertFalse(migrated.document.searchActivation.enabled)
        migrated.undo(); XCTAssertTrue(migrated.document.searchActivation.enabled)
    }
}

extension SearchShortcutContractTests {
    @MainActor private func dispatch(_ id: EventHotKeyID) -> OSStatus {
        var event: EventRef?, identity = id
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(0), &event)
        guard created == noErr, let event else { return created }
        defer { ReleaseEvent(event) }
        let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identity)
        guard parameter == noErr else { return parameter }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }
    @MainActor func testTwoRealCarbonHandlersDispatchOnlyTheirOwnIDsAndReleaseBothForExceptions() throws {
        var main = ActivationPreferences(), search = SearchActivationPreferences.suggestedShortcut
        main.keyCode = 80; search.keyCode = 90
        main.modifiers = CGEventFlags([.maskCommand,.maskControl,.maskShift,.maskAlternate]).rawValue; search.modifiers = main.modifiers
        func probe(_ code: UInt16) -> OSStatus {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code),UInt32(cmdKey | controlKey | shiftKey | optionKey),
                .init(signature:0x54455354,id:UInt32(code)),GetApplicationEventTarget(),OptionBits(kEventHotKeyExclusive),&reference)
            if let reference { UnregisterEventHotKey(reference) }; return status
        }
        guard probe(80) == noErr, probe(90) == noErr else { throw XCTSkip("An isolated test chord is already registered; existing registrations are untouched.") }
        let first = HotKeyFallback(), second = HotKeyFallback(); defer { first.stop(); second.stop() }
        var mainFires = 0, searchFires = 0, held = false
        first.onFire = { mainFires += 1 }; second.onFire = { searchFires += 1 }
        var current: ForegroundIdentity? = .init(pid:2,bundleID:"test.Editor")
        let policy = ShortcutExceptionRouter(ownPID:1,sample:{ current },isPreview:{ _ in false },configureFallback: { allowed in
            first.configure(allowed && !held ? main : nil); second.configure(allowed && !held ? search : nil)
        })
        first.onRetryRegistration = { policy.refresh() }; second.onRetryRegistration = { policy.refresh() }
        var rules = ExclusionPreferences(); rules.shortcutExceptions = [.init(bundleID:"test.VM")]
        policy.configure(rules,enabled:true)
        XCTAssertTrue(first.isRegistered && second.isRegistered)
        XCTAssertNotEqual(first.signature,second.signature)
        let old = first.eventID
        XCTAssertEqual(dispatch(first.eventID),noErr); XCTAssertEqual(mainFires,1); XCTAssertEqual(searchFires,0)
        XCTAssertEqual(dispatch(second.eventID),noErr); XCTAssertEqual(mainFires,1); XCTAssertEqual(searchFires,1)
        XCTAssertEqual(dispatch(.init(signature:0x00000001,id:1)),OSStatus(eventNotHandledErr))
        current = .init(pid:3,bundleID:"test.VM"); policy.refresh()
        XCTAssertFalse(first.isRegistered || second.isRegistered)
        XCTAssertEqual(probe(80),noErr); XCTAssertEqual(probe(90),noErr)
        _ = dispatch(old); XCTAssertEqual(mainFires,1)
        current = .init(pid:2,bundleID:"test.Editor"); policy.refresh()
        XCTAssertEqual(probe(80),OSStatus(eventHotKeyExistsErr)); XCTAssertEqual(probe(90),OSStatus(eventHotKeyExistsErr))
        _ = dispatch(old); XCTAssertEqual(mainFires,1)
        _ = dispatch(second.eventID); XCTAssertEqual(searchFires,2)
        held = true; policy.refresh() // Recording suspends both registrations using the same policy.
        XCTAssertFalse(first.isRegistered || second.isRegistered)
    }
    @MainActor func testFallbackSearchUsesRealDispatchAndPreservesQueryOnRepeat() async {
        var settings = SettingsDocument(); settings.searchActivation.enabled = true; settings.activation.behavior = .hold
        let opened = expectation(description:"Fallback opened search")
        var publications = 0
        let router = InputRouter(onState: { state in
            if state.active, state.query == "" { publications += 1; if publications == 1 { opened.fulfill() } }
        },onSelect:{ _ in XCTFail("Fallback cannot select on release") },onCancel:{},onHealth:{ _ in })
        _ = router.replayForTesting(snapshot:snapshot,settings:settings,events:[])
        router.markRunningForTesting(); defer { router.clearRunningForTesting() }
        let fallback = HotKeyFallback(keyIsDown:{ _ in false },register:{ _ in true },unregister:{},installHandlerForTesting:true)
        defer { fallback.stop() }
        fallback.configure(settings.searchActivation.shortcut)
        fallback.onFire = { router.toggleFromHotKey(search:true) }
        XCTAssertEqual(dispatch(fallback.eventID),noErr)
        await fulfillment(of:[opened],timeout:3)
        router.key(.query("Beta"))
        _ = dispatch(fallback.eventID)
        let drained = expectation(description:"Input loop drained")
        CFRunLoopPerformBlock(CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue) { drained.fulfill() }
        CFRunLoopWakeUp(CFRunLoopGetMain()); await fulfillment(of:[drained],timeout:3)
        XCTAssertEqual(router.stateForTesting.query,"Beta"); XCTAssertEqual(router.stateForTesting.session,1)
        router.key(.escape)
        let escaped = expectation(description:"Escape drained")
        CFRunLoopPerformBlock(CFRunLoopGetMain(),CFRunLoopMode.commonModes.rawValue) { escaped.fulfill() }
        CFRunLoopWakeUp(CFRunLoopGetMain()); await fulfillment(of:[escaped],timeout:3)
        XCTAssertTrue(router.stateForTesting.active); XCTAssertNil(router.stateForTesting.query)
    }
}

extension SearchShortcutContractTests {
    @MainActor func testRepeatedSearchPreservesNativeMarkedTextAndSelection() async throws {
        let presenter = SwitcherPresenter(); presenter.allowsDesktopSpotlight = false
        var settings = SettingsDocument(); settings.searchActivation.enabled = true
        let ready = expectation(description:"Search ready")
        var count = 0
        let router = InputRouter(onState:{ state in
            presenter.present(state,icons:[:],status:"")
            count += 1; if count == 1 { ready.fulfill() }
        },onSelect:{ _ in XCTFail("Composition cannot select a target") },onCancel:{},onHealth:{ _ in })
        router.onSearchFocus = { presenter.focusSearch(session:$0) }
        let first = event(49,flags:[.maskControl,.maskShift])
        _ = router.replayForTesting(snapshot:snapshot,settings:settings,events:[(.keyDown,first),(.keyUp,event(49,.keyUp))])
        await fulfillment(of:[ready],timeout:3)
        func descendants(_ view:NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let field = try XCTUnwrap(descendants(presenter.embeddedView).compactMap { $0 as? NSSearchField }.first)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setMarkedText("に",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        XCTAssertTrue(editor.hasMarkedText())
        let before = editor.selectedRange()
        _ = router.replayForTesting(snapshot:router.stateForTesting.snapshot,settings:settings,events:[(.keyDown,event(49,flags:[.maskControl,.maskShift])),(.keyUp,event(49,.keyUp))])
        await Task.yield()
        try await Task.sleep(for:.milliseconds(30))
        XCTAssertTrue(editor.hasMarkedText()); XCTAssertEqual(editor.string,"に"); XCTAssertEqual(editor.selectedRange(),before)
        XCTAssertFalse(presenter.control(field,textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:))), "IME owns Return while composing")
        XCTAssertFalse(presenter.control(field,textView:editor,doCommandBy:#selector(NSResponder.cancelOperation(_:))))
        editor.unmarkText(); presenter.dismiss()
    }
}

extension SearchShortcutContractTests {
    func testOppositeModifierSidesRouteToDifferentActivationModes() throws {
        var settings = SettingsDocument(); settings.activation.side = .left
        settings.searchActivation.enabled = true; settings.searchActivation.shortcut = settings.activation
        settings.searchActivation.shortcut.side = .right
        _ = try settings.validated()
        for search in [false,true] {
            let router = InputRouter(onState:{ _ in },onSelect:{ _ in },onCancel:{},onHealth:{ _ in })
            let bits: UInt64 = search ? 0x2000 | 0x40 : 0x1 | 0x20
            let down = event(49,flags:.init(rawValue:settings.activation.modifiers | bits))
            XCTAssertEqual(router.replayForTesting(snapshot:snapshot,settings:settings,events:[(.keyDown,down),(.keyUp,event(49,.keyUp))]),[true,true])
            XCTAssertEqual(router.stateForTesting.query,search ? "" : nil)
        }
    }
    @MainActor func testEarlyTextAutorepeatKeepsOriginalEventsAndOwnership() async {
        var settings = SettingsDocument(); settings.searchActivation.enabled = true
        let delivered = expectation(description:"Early text and repeat reached native handoff"); delivered.expectedFulfillmentCount = 2
        let router = InputRouter(onState:{ _ in },onSelect:{ _ in XCTFail("Text is never an address") },onCancel:{},onHealth:{ _ in })
        var repeats: [Bool] = []
        router.onSearchInput = { event,_ in
            repeats.append(event.getIntegerValueField(.keyboardEventAutorepeat) != 0); delivered.fulfill()
        }
        let events = [event(49,flags:[.maskControl,.maskShift]),event(49,.keyUp),event(0),event(0,repeated:true)]
        XCTAssertEqual(router.replayForTesting(snapshot:snapshot,settings:settings,events:events.map { ($0.type,$0) }),[true,true,true,true])
        await fulfillment(of:[delivered],timeout:3)
        XCTAssertEqual(repeats,[false,true])
        XCTAssertFalse(router.routeForTesting(event(0,repeated:true)), "After handoff native repeat is ordinary text")
        XCTAssertTrue(router.routeForTesting(event(0,.keyUp)), "Buffered down owns its release")
        XCTAssertFalse(router.routeForTesting(event(0)), "Subsequent text goes straight to AppKit")
    }
}

final class MultiDisplayContractTests: XCTestCase {
    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor private func field(_ panel: NSPanel) throws -> NSSearchField {
        try XCTUnwrap(descendants(panel.contentView!).compactMap { $0 as? NSSearchField }.first)
    }
    @MainActor private func targets(_ panel: NSPanel) -> [NSButton] {
        descendants(panel.contentView!).compactMap { $0 as? NSButton }.filter { $0.accessibilityIdentifier().hasPrefix("target-") }
    }
    private var synthetic: [SwitcherDisplay] {
        [.init(id: 1, frame: CGRect(x:0,y:0,width:1600,height:1000), visibleFrame: CGRect(x:0,y:60,width:1600,height:912), scale:2),
         .init(id: 2, frame: CGRect(x:-1280,y:-240,width:1280,height:800), visibleFrame: CGRect(x:-1280,y:-190,width:1280,height:724), scale:1),
         .init(id: 3, frame: CGRect(x:1600,y:300,width:1920,height:1080), visibleFrame: CGRect(x:1600,y:330,width:1920,height:1022), scale:1.5)]
    }
    private func snapshot() -> CatalogueSnapshot {
        let app = UUID(), browser = UUID()
        let windows = [
            Target(id:.init(process:app,window:UUID()),app:"Alpha",title:"Release console",address:"j",foldAddress:"ij", bounds:CGRect(x:60,y:80,width:450,height:350),onScreen:true),
            Target(id:.init(process:app,window:UUID()),app:"Alpha",title:"Release checklist",address:"k",foldAddress:"ik"),
            Target(id:.init(process:browser,window:UUID()),app:"Beta",title:"rc",address:"l",foldAddress:"oj"),
            Target(id:.init(process:browser,window:UUID()),app:"Beta",title:"Exclude me",address:"u",foldAddress:"ok")]
        let apps = [Target(id:.init(process:app),app:"Alpha",title:"Alpha",address:"i",foldAddress:"i"),
                    Target(id:.init(process:browser),app:"Beta",title:"Beta",address:"o",foldAddress:"o")]
        let tab = Target(id:.init(process:UUID(),window:UUID()),app:"Beta",title:"Browser rc",address:"p",foldAddress:"ol",owner:browser)
        var history = FocusHistory(); history.observe(windows[1].id); history.observe(windows[0].id)
        var source = CatalogueSnapshot(windows:windows,apps:apps,allocated:Set((windows+apps+[tab]).map(\.address)),tabs:[tab],history:history)
        var rules = ExclusionPreferences(); rules.titles = [.init(pattern:"Exclude me")]
        source = rules.applying(to:source)
        return source
    }
    private func opened(_ source: CatalogueSnapshot, mode: DisplayMode) -> SelectionState {
        var state = SelectionState(); state.configure(mode:mode); state.configure(ordering:.recent); state.update(source); state.open(); return state
    }
    @MainActor func testSyntheticFramesSharedTargetsAndOwnershipForAllLayoutsAndAnchors() throws {
        let source = snapshot()
        for mode in DisplayMode.allCases { for anchor in Anchor.allCases { try autoreleasepool {
            let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main
            p.settings.appearance.preset = .graphite; p.allowsDesktopSpotlight = false
            var placement = Placement.defaults(for:mode); placement.anchor = anchor; placement.inset = 64
            p.settings.positions[mode.rawValue] = placement
            p.displayProvider = { self.synthetic }
            var state = opened(source,mode:mode)
            p.present(state,icons:[:],status:"")
            XCTAssertEqual(p.panels.count,3)
            for (panel,screen) in zip(p.panels,synthetic) {
                XCTAssertTrue(screen.visibleFrame.contains(panel.frame), "\(mode) \(anchor): \(panel.frame)")
                XCTAssertEqual(panel.collectionBehavior.intersection([.canJoinAllSpaces,.fullScreenAuxiliary]),[.canJoinAllSpaces,.fullScreenAuxiliary])
                XCTAssertFalse(targets(panel).contains { $0.accessibilityLabel()?.contains("Exclude me") == true })
            }
            _ = state.handle(.beginSearch); _ = state.handle(.query("rc")); p.present(state,icons:[:],status:"")
            let reference = targets(p.panels[0]).map { $0.accessibilityIdentifier() }
            for panel in p.panels {
                XCTAssertEqual(try field(panel).stringValue,"rc")
                XCTAssertEqual(targets(panel).map { $0.accessibilityIdentifier() },reference)
            }
            XCTAssertEqual(p.panels.filter { (try? field($0).currentEditor()) != nil }.count,1)
            let held = p.panels
            p.dismiss(); XCTAssertTrue(held.allSatisfy { !$0.isVisible }); XCTAssertTrue(p.panels.isEmpty)
        } } }
    }
    @MainActor func testDefaultAndEmbeddedStaySingleAndTopologyDropsEveryOldPanel() {
        let p = SwitcherPresenter(); p.allowsDesktopSpotlight = false
        var displays = synthetic; p.displayProvider = { displays }
        var state = opened(snapshot(),mode:.fold)
        p.present(state,icons:[:],status:""); XCTAssertEqual(p.panels.count,1)
        p.settings.allDisplays = true; p.present(state,icons:[:],status:""); XCTAssertEqual(p.panels.count,3)
        let old = p.panels
        displays.remove(at:1); p.present(state,icons:[:],status:"")
        XCTAssertEqual(p.panels.count,2); XCTAssertFalse(old[1].isVisible)
        XCTAssertTrue(p.panels.allSatisfy { panel in displays.contains { $0.visibleFrame.contains(panel.frame) } })
        displays = []; p.present(state,icons:[:],status:""); XCTAssertTrue(p.panels.isEmpty)
        displays = synthetic; p.present(state,icons:[:],status:""); XCTAssertEqual(p.panels.count,3)
        state.cancel(); p.present(state,icons:[:],status:""); XCTAssertTrue(p.panels.isEmpty)
        p.embedded = true; state.open(); p.present(state,icons:[:],status:""); XCTAssertEqual(p.panels.count,1)
        p.dismiss()
    }
    @MainActor func testConnectedDisplaysShareNativeEditorExactSelectionAndUniqueEffects() throws {
        let connected = SwitcherDisplay.connected()
        guard connected.count > 1 else { throw XCTSkip("Actual simultaneous presentation requires multiple connected displays; synthetic coverage still runs.") }
        let source = snapshot()
        var evidence: [[String: Any]] = []
        for mode in DisplayMode.allCases {
            let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main
            p.settings.appearance.preset = .graphite; p.settings.appearance.desktopSpotlight.mode = .switcherOnly
            var state = opened(source,mode:mode), selected: [TargetID] = []
            p.onKey = { key, session in
                guard session == state.session else { return }
                if case .selected(let id) = state.handle(key) { selected.append(id) }
                p.present(state,icons:[:],status:"")
            }
            p.onChoose = { id, session in
                guard session == state.session else { return }
                if case .selected(let chosen) = state.select(id) { selected.append(chosen) }
                p.present(state,icons:[:],status:"")
            }
            var regions: [CGRect] = []; p.onSurfaces = { regions = $0 }
            p.present(state,icons:[:],status:"")
            let panels = p.panels
            XCTAssertEqual(panels.count,connected.count)
            XCTAssertEqual(p.desktopSpotlight.panels.filter(\.isVisible).count,connected.count)
            XCTAssertGreaterThanOrEqual(regions.count,panels.count)
            for (panel,screen) in zip(panels,connected) {
                XCTAssertTrue(panel.isVisible); XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
                XCTAssertEqual((panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,screen.id)
            }
            // Initiate search using a control in the secondary physical copy.
            let mirror = panels[1]
            let searchButton = try XCTUnwrap(descendants(mirror.contentView!).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "begin-search" })
            mirror.makeKey(); searchButton.performClick(nil)
            XCTAssertTrue(p.inputPanel === mirror)
            let editor = try XCTUnwrap(try field(mirror).currentEditor() as? NSTextView)
            editor.insertText("rc",replacementRange:NSRange(location:NSNotFound,length:0))
            for panel in panels { XCTAssertEqual(try field(panel).stringValue,"rc") }
            XCTAssertEqual(state.highlightedTarget?.title,"rc")
            XCTAssertEqual(panels.filter { (try? field($0).currentEditor()) != nil }.count,1)
            evidence.append(["mode":mode.rawValue,"query":state.query ?? "","highlight":state.highlightedTarget?.title ?? "",
                "panels":panels.map { panel in ["frame":NSStringFromRect(panel.frame),"screenID":(panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,"scale":panel.backingScaleFactor,"visible":panel.isVisible] as [String:Any] },"surfaceCount":regions.count,"spotlightCount":p.desktopSpotlight.panels.filter(\.isVisible).count])
            let attachment = XCTAttachment(string: String(describing:evidence.last!)); attachment.name = "Connected displays \(mode)"; attachment.lifetime = .keepAlways; add(attachment)
            if mode == .fold {
                let directory = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("verification/competitive-gaps-2026-09-22")
                try p.saveDisplayPreviews(to:directory.path)
            }
            let expected = try XCTUnwrap(state.highlightedTarget?.id)
            XCTAssertTrue(p.control(try field(mirror),textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:))))
            XCTAssertEqual(selected,[expected]); XCTAssertTrue(panels.allSatisfy { !$0.isVisible }); XCTAssertTrue(regions.isEmpty)
            XCTAssertTrue(p.desktopSpotlight.panels.allSatisfy { !$0.isVisible })
            // A second Return and a stale row click cannot commit the old session again.
            _ = p.control(try field(mirror),textView:editor,doCommandBy:#selector(NSResponder.insertNewline(_:)))
            XCTAssertEqual(selected,[expected]); p.dismiss()
        }
        let file = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("verification/competitive-gaps-2026-09-22/connected-displays.json")
        try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:file)
    }
    @MainActor func testCompositionTransferCompletesOldEditorWithoutDuplicatingInput() throws {
        let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main; p.allowsDesktopSpotlight = false
        p.displayProvider = { self.synthetic }
        var state = opened(snapshot(),mode:.shore); _ = state.handle(.beginSearch)
        p.onKey = { key,_ in _ = state.handle(key); p.present(state,icons:[:],status:"") }
        p.present(state,icons:[:],status:""); defer { p.dismiss() }
        let first = p.panels[0], second = p.panels[1]
        let editor = try XCTUnwrap(try field(first).currentEditor() as? NSTextView)
        editor.setMarkedText("に",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        p.focusSearch(session:state.session); XCTAssertTrue(editor.hasMarkedText())
        second.makeKey()
        XCTAssertFalse(editor.hasMarkedText()); XCTAssertTrue(p.inputPanel === second)
        XCTAssertNil(try field(first).currentEditor())
        XCTAssertEqual(try field(second).stringValue,"に")
        XCTAssertNotNil(try field(second).currentEditor())
    }
}

extension MultiDisplayContractTests {
    @MainActor func testImmediateTypingAfterEditorTransferSurvivesQueuedQueryPublications() throws {
        let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main; p.allowsDesktopSpotlight = false
        p.displayProvider = { self.synthetic }
        var state = opened(snapshot(),mode:.shore); _ = state.handle(.beginSearch)
        var queued: [SelectionKey] = []
        p.onKey = { key,_ in queued.append(key) } // Deliberately hold the router's publications.
        p.present(state,icons:[:],status:""); defer { p.dismiss() }
        let first = p.panels[0], second = p.panels[1]
        let editor = try XCTUnwrap(try field(first).currentEditor() as? NSTextView)
        editor.insertText("Release",replacementRange:NSRange(location:NSNotFound,length:0))
        editor.setMarkedText("に",selectedRange:NSRange(location:1,length:0),replacementRange:NSRange(location:NSNotFound,length:0))
        second.makeKey()
        let destination = try XCTUnwrap(try field(second).currentEditor() as? NSTextView)
        XCTAssertEqual(destination.string,"Releaseに")
        XCTAssertEqual(destination.selectedRange(),NSRange(location:8,length:0))
        destination.insertText("X",replacementRange:NSRange(location:NSNotFound,length:0))
        XCTAssertEqual(destination.string,"ReleaseにX")
        XCTAssertFalse(editor.hasMarkedText()); XCTAssertNil(try field(first).currentEditor())
        for key in queued {
            _ = state.handle(key); p.present(state,icons:[:],status:"")
            XCTAssertEqual(destination.string,"ReleaseにX", "Older query publications must not roll back the new editor")
        }
        XCTAssertEqual(state.query,"ReleaseにX")
        XCTAssertEqual(try field(first).stringValue,"ReleaseにX")
    }
}

extension MultiDisplayContractTests {
    @MainActor func testMenuTrackingBlocksEveryCopyAndLateCompletionCannotResurrectPanels() throws {
        let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main
        p.displayProvider = { self.synthetic }
        var state = opened(snapshot(),mode:.beacons)
        _ = state.handle(.beginSearch); _ = state.handle(.query("rc"))
        var inspected = 0, chosen = 0, keys = 0, menuEvents: [Bool] = []
        var complete: (@MainActor @Sendable ([SwitcherActionItem]) -> Void)?
        p.onInspectActions = { _, callback in inspected += 1; complete = callback }
        p.onMenuTracking = { tracking,_ in menuEvents.append(tracking) }
        p.onChoose = { _,_ in chosen += 1 }; p.onKey = { _,_ in keys += 1 }
        p.present(state,icons:[:],status:"")
        let panels = p.panels
        panels[1].makeKey(); p.showActionMenu()
        XCTAssertEqual(inspected,1); XCTAssertEqual(menuEvents,[true])
        XCTAssertTrue(p.desktopSpotlight.panels.allSatisfy { !$0.isVisible })
        for panel in panels {
            let button = try XCTUnwrap(descendants(panel.contentView!).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "switcher-actions" })
            button.performClick(nil)
            targets(panel).first?.performClick(nil)
        }
        XCTAssertEqual(inspected,1); XCTAssertEqual(chosen,0); XCTAssertEqual(keys,0)
        p.dismiss(); complete?(state.actionMenuItems)
        XCTAssertEqual(menuEvents,[true,false]); XCTAssertTrue(panels.allSatisfy { !$0.isVisible })
        XCTAssertTrue(p.panels.isEmpty)
    }
    @MainActor func testPrefixNavigationAndExactPointerSelectionStayShared() throws {
        for mode in DisplayMode.allCases {
            let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main
            p.allowsDesktopSpotlight = false; p.displayProvider = { self.synthetic }
            var state = opened(snapshot(),mode:mode); var selected: [TargetID] = []
            p.onChoose = { id,_ in
                if case .selected(let chosen) = state.select(id) { selected.append(chosen) }
                p.present(state,icons:[:],status:"")
            }
            _ = state.handle(.prefix(mode == .fold || mode == .canopy ? "i" : "j"))
            p.present(state,icons:[:],status:"")
            let panels = p.panels
            let first = targets(panels[0]).map { $0.accessibilityIdentifier() }
            for panel in panels { XCTAssertEqual(targets(panel).map { $0.accessibilityIdentifier() },first) }
            _ = state.handle(.beginSearch); _ = state.handle(.query("rc")); p.present(state,icons:[:],status:"")
            let expected = try XCTUnwrap(state.highlightedTarget?.id)
            let target = try XCTUnwrap(targets(panels.last!).first { $0.accessibilityLabel()?.contains("rc") == true })
            target.performClick(nil); target.performClick(nil)
            XCTAssertEqual(selected,[expected]); XCTAssertTrue(panels.allSatisfy { !$0.isVisible })
            p.dismiss()
        }
    }
}

extension MultiDisplayContractTests {
    @MainActor func testRepeatedAndTruncatedQueryAcknowledgementsCannotRollbackTheDraft() throws {
        let p = SwitcherPresenter(); p.settings.allDisplays = true; p.settings.display = .main; p.allowsDesktopSpotlight = false
        p.displayProvider = { self.synthetic }
        var state = opened(snapshot(),mode:.shore); _ = state.handle(.beginSearch)
        var queued: [SelectionKey] = []
        p.onKey = { key,_ in queued.append(key) }
        p.present(state,icons:[:],status:""); defer { p.dismiss() }
        let first = p.panels[0], second = p.panels[1]
        let editor = try XCTUnwrap(try field(first).currentEditor() as? NSTextView)
        for text in ["A", "AB", "A"] {
            editor.insertText(text,replacementRange:NSRange(location:0,length:(editor.string as NSString).length))
        }
        second.makeKey()
        let destination = try XCTUnwrap(try field(second).currentEditor() as? NSTextView)
        for key in queued {
            _ = state.handle(key); p.present(state,icons:[:],status:"")
            XCTAssertEqual(destination.string,"A", "An earlier A acknowledgement must not expose the queued AB")
        }
        queued.removeAll()
        destination.insertText(String(repeating:"X",count:1100),replacementRange:NSRange(location:0,length:1))
        for key in queued { _ = state.handle(key); p.present(state,icons:[:],status:"") }
        XCTAssertEqual(destination.string.count,1024)
        // Once acknowledged, an authoritative query update can replace the native draft.
        _ = state.handle(.query("Beta")); p.present(state,icons:[:],status:"")
        XCTAssertEqual(destination.string,"Beta"); XCTAssertEqual(try field(first).stringValue,"Beta")
    }
}
