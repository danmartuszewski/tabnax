import XCTest
import AppKit
@testable import Tabnax
import TabnaxCore

/// Behavioral coverage for preparing and reusing native switcher views. Timing belongs in
/// the profiling harness; these tests protect interaction and invalidation while views persist.
final class RendererPerformanceTests: XCTestCase {
    @MainActor private final class DrawProbe: NSView {
        var draws = 0
        override func draw(_ dirtyRect: NSRect) { draws += 1 }
    }

    @MainActor func testOpeningDrawsPendingContentBeforeReturningIncludingAfterDismissal() throws {
        let presenter = presenter()
        let panel = try XCTUnwrap(presenter.embeddedView.window)
        defer { presenter.dismiss() }
        // Attach to the frame view so body reconciliation does not remove the probe.
        let frame = try XCTUnwrap(panel.contentView?.superview)
        let probe = DrawProbe(frame: NSRect(x: 20, y: 20, width: 10, height: 10))
        frame.addSubview(probe)
        var state = opened(fixture())
        probe.needsDisplay = true
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(panel.isVisible)
        XCTAssertGreaterThan(probe.draws, 0, "Opening must draw before on-open refresh can be queued.")

        presenter.dismiss()
        state.cancel(); state.open()
        let previousDraws = probe.draws
        probe.needsDisplay = true
        presenter.present(state, icons: [:], status: "")
        XCTAssertGreaterThan(probe.draws, previousDraws, "Reopening must service drawing invalidated while hidden.")
    }

    private func fixture() -> CatalogueSnapshot {
        let alpha = UUID(), beta = UUID()
        let windows = [
            Target(id: .init(process: alpha, window: UUID()), app: "Alpha", title: "Alpha one", address: "j", foldAddress: "ij"),
            Target(id: .init(process: beta, window: UUID()), app: "Beta", title: "Beta one", address: "k", foldAddress: "oj"),
            Target(id: .init(process: alpha, window: UUID()), app: "Alpha", title: "Alpha two", address: "l", foldAddress: "ik")
        ]
        let tab = Target(id: .init(process: UUID(), window: UUID()), app: "Alpha", title: "Alpha tab", address: "uu", foldAddress: "il", owner: alpha)
        let apps = [
            Target(id: .init(process: alpha), app: "Alpha", title: "Alpha", address: "i", foldAddress: "i"),
            Target(id: .init(process: beta), app: "Beta", title: "Beta", address: "o", foldAddress: "o")
        ]
        var history = FocusHistory(); history.observe(windows[1].id); history.observe(windows[0].id)
        return .init(windows: windows, apps: apps, allocated: Set((windows + apps + [tab]).map(\.address)), tabs: [tab], history: history)
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    @MainActor private func targetRows(_ presenter: SwitcherPresenter) -> [NSButton] {
        descendants(presenter.embeddedView).compactMap { $0 as? NSButton }
            .filter { $0.accessibilityIdentifier().hasPrefix("target-") }
    }

    @MainActor private func row(_ address: String, in presenter: SwitcherPresenter) throws -> NSButton {
        try XCTUnwrap(targetRows(presenter).first { $0.accessibilityIdentifier() == "target-\(address)" })
    }

    @MainActor private func field(_ text: String, in view: NSView) throws -> NSTextField {
        try XCTUnwrap(descendants(view).compactMap { $0 as? NSTextField }.first { $0.stringValue == text })
    }

    @MainActor private func presenter() -> SwitcherPresenter {
        let presenter = SwitcherPresenter()
        presenter.settings.mode = .canopy
        presenter.settings.appearance.preset = .graphite
        presenter.settings.appearance.source = .light
        return presenter
    }

    private func opened(_ snapshot: CatalogueSnapshot, mode: DisplayMode = .canopy) -> SelectionState {
        var state = SelectionState(); state.configure(mode: mode); state.update(snapshot); state.open()
        return state
    }

    @MainActor func testMinimizedBadgesAcrossEveryLayoutAndLiveRestoration() throws {
        for mode in DisplayMode.allCases {
            for compact in [false, true] {
                for large in [false, true] {
                    var snapshot = fixture(); snapshot.windows[0].minimized = true
                    var state = opened(snapshot, mode: mode)
                    if mode == .fold { _ = state.handle(.highlight(.branch("i"))) }
                    let presenter = SwitcherPresenter(); presenter.previewOnly = true
                    presenter.embedded = compact
                    if compact { presenter.embeddedView.removeFromSuperview() }
                    presenter.previewSize = compact ? CGSize(width: 410, height: 460) : CGSize(width: 900, height: 720)
                    presenter.settings.appearance.scale = large ? .extraLarge : .standard
                    presenter.settings.appearance.source = compact ? .dark : .light
                    presenter.settings.appearance.strongOutlines = large
                    defer { presenter.dismiss() }
                    presenter.present(state, icons: [:], status: "")
                    presenter.embeddedView.layoutSubtreeIfNeeded()
                    let address = mode == .fold || mode == .canopy ? "ij" : "j"
                    let window = try row(address, in: presenter)
                    func badge(in view: NSView) throws -> NSView {
                        try XCTUnwrap(descendants(view).first { $0.identifier?.rawValue == "minimized-indicator" })
                    }
                    let marker = try badge(in: window)
                    XCTAssertFalse(marker.isHidden, mode.rawValue)
                    XCTAssertTrue(window.bounds.contains(marker.frame), "\(mode): \(marker.frame) in \(window.bounds)")
                    XCTAssertTrue(window.accessibilityLabel()?.contains("Minimized") == true)
                    XCTAssertTrue(window.toolTip?.contains("Minimized") == true)
                    for field in window.subviews.compactMap({ $0 as? NSTextField }).filter({ !$0.isHidden }) {
                        XCTAssertFalse(marker.frame.intersects(field.frame), "Badge overlaps text in \(mode): \(field.stringValue)")
                    }
                    var group: NSView?
                    if mode == .fold {
                        group = descendants(presenter.embeddedView).first { $0.accessibilityIdentifier() == "family-i" }
                    } else if mode != .canopy { group = try row("i", in: presenter) }
                    if let group {
                        XCTAssertFalse(try badge(in: group).isHidden)
                        XCTAssertTrue(group.accessibilityLabel()?.contains("Contains minimized windows") == true)
                        XCTAssertTrue(group.bounds.contains(try badge(in: group).frame))
                    }
                    snapshot.windows[0].minimized = false
                    state.update(snapshot); presenter.present(state, icons: [:], status: "")
                    XCTAssertTrue(try row(address, in: presenter) === window)
                    XCTAssertTrue(marker.isHidden, "Restore must clear reused row badge in \(mode)")
                    XCTAssertFalse(window.accessibilityLabel()?.contains("Minimized") == true)
                    if let group { XCTAssertTrue(try badge(in: group).isHidden) }

                    snapshot.windows[0].minimized = true
                    state.update(snapshot); _ = state.handle(.beginSearch); _ = state.handle(.query("Alpha one"))
                    presenter.present(state, icons: [:], status: "")
                    XCTAssertFalse(try badge(in: row(address, in: presenter)).isHidden, "Search retains state in \(mode)")
                }
            }
        }
    }

    @MainActor func testPreparationStaysHiddenAndPreparedRowsChooseThePresentedSession() async throws {
        let snapshot = fixture(), presenter = presenter()
        defer { presenter.dismiss() }
        let panel = try XCTUnwrap(presenter.embeddedView.window)
        let visibleBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        var surfaces: [[CGRect]] = [], choices: [(TargetID, UInt64)] = []
        presenter.onSurfaces = { surfaces.append($0) }
        presenter.onChoose = { choices.append(($0, $1)) }

        let preparation = try XCTUnwrap(presenter.prepare(snapshot, icons: [:]))
        await preparation.value

        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init)), visibleBefore)
        XCTAssertTrue(surfaces.isEmpty, "Preparing must not publish interactive surfaces.")
        XCTAssertTrue(choices.isEmpty)

        presenter.previewOnly = true
        let state = opened(snapshot)
        presenter.present(state, icons: [:], status: "")
        XCTAssertEqual(Set(targetRows(presenter).map { $0.accessibilityIdentifier() }), ["target-ij", "target-ik", "target-il", "target-oj"])
        XCTAssertTrue(try row("ij", in: presenter).accessibilityPerformPress())
        XCTAssertEqual(choices.map(\.0), [snapshot.windows[0].id])
        XCTAssertEqual(choices.map(\.1), [state.session])
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor func testReopeningRetainsRowsAndRoutesThemToTheNewSession() throws {
        let snapshot = fixture(), presenter = presenter()
        presenter.previewOnly = true
        defer { presenter.dismiss() }
        var state = opened(snapshot), choices: [(TargetID, UInt64)] = []
        presenter.onChoose = { choices.append(($0, $1)) }
        presenter.present(state, icons: [:], status: "")
        let original = try row("ij", in: presenter), parent = try XCTUnwrap(original.superview)
        XCTAssertTrue(original.accessibilityPerformPress())
        let firstSession = state.session

        _ = state.handle(.next)
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(try row("ij", in: presenter) === original)
        XCTAssertTrue(original.superview === parent)
        presenter.dismiss()
        XCTAssertTrue(original.superview === parent)

        state.cancel(); state.open()
        presenter.present(state, icons: [:], status: "")
        XCTAssertNotEqual(state.session, firstSession)
        XCTAssertTrue(try row("ij", in: presenter) === original)
        XCTAssertTrue(original.superview === parent)
        XCTAssertTrue(original.accessibilityPerformPress())
        XCTAssertEqual(choices.map(\.0), [snapshot.windows[0].id, snapshot.windows[0].id])
        XCTAssertEqual(choices.map(\.1), [firstSession, state.session])
    }

    @MainActor func testReusedRowsUpdateMetadataAvailabilityAndSearchMembership() throws {
        var snapshot = fixture(), state = opened(snapshot)
        let presenter = presenter(); presenter.previewOnly = true
        defer { presenter.dismiss() }
        presenter.present(state, icons: [:], status: "")
        let original = try row("ij", in: presenter)

        snapshot.windows[0].title = "Renamed Alpha"
        snapshot.windows[0].available = false
        state.update(snapshot)
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(try row("ij", in: presenter) === original)
        XCTAssertNotNil(try field("Renamed Alpha", in: original))
        XCTAssertFalse(original.isEnabled)
        XCTAssertFalse(original.accessibilityPerformPress())
        XCTAssertTrue(original.toolTip?.contains("Renamed Alpha") == true)

        _ = state.handle(.beginSearch); _ = state.handle(.query("Beta"))
        presenter.present(state, icons: [:], status: "")
        XCTAssertEqual(targetRows(presenter).map { $0.accessibilityIdentifier() }, ["target-oj"])
        XCTAssertNil(original.superview)

        _ = state.handle(.escape)
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(try row("ij", in: presenter) === original)
        XCTAssertFalse(original.isEnabled)
        snapshot.windows[0].available = true
        state.update(snapshot)
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(original.isEnabled)
    }

    @MainActor func testReusedRowsRefreshAppearanceAndLayoutWhenModeChanges() throws {
        let snapshot = fixture(), presenter = presenter()
        presenter.previewOnly = true
        defer { presenter.dismiss() }
        var state = opened(snapshot)
        presenter.present(state, icons: [:], status: "")
        presenter.embeddedView.layoutSubtreeIfNeeded()
        let original = try row("ij", in: presenter), heading = try field("Alpha one", in: original)
        let listTextX = heading.frame.minX, listHeight = original.frame.height
        let lightColor = try XCTUnwrap(heading.textColor).rgb.hex

        presenter.settings.appearance.source = .dark
        presenter.present(state, icons: [:], status: "")
        XCTAssertTrue(try row("ij", in: presenter) === original)
        XCTAssertNotEqual(try XCTUnwrap(heading.textColor).rgb.hex, lightColor)

        state.configure(mode: .lattice)
        presenter.present(state, icons: [:], status: "")
        presenter.embeddedView.layoutSubtreeIfNeeded()
        XCTAssertTrue(try row("j", in: presenter) === original)
        XCTAssertGreaterThan(original.frame.height, listHeight)
        XCTAssertLessThan(heading.frame.minX, listTextX)

        state.configure(mode: .canopy)
        presenter.present(state, icons: [:], status: "")
        presenter.embeddedView.layoutSubtreeIfNeeded()
        XCTAssertTrue(try row("ij", in: presenter) === original)
        XCTAssertEqual(original.frame.height, listHeight)
        XCTAssertEqual(heading.frame.minX, listTextX)
    }

    @MainActor func testPresentationCancelsPendingPreparationWithoutRestoringStaleContent() async throws {
        var snapshot = fixture()
        let presenter = presenter()
        defer { presenter.dismiss() }
        let preparation = try XCTUnwrap(presenter.prepare(snapshot, icons: [:]))
        snapshot.windows[0].title = "Latest Alpha"
        let state = opened(snapshot)
        presenter.previewOnly = true
        presenter.present(state, icons: [:], status: "")
        let current = try row("ij", in: presenter)

        await preparation.value

        XCTAssertTrue(try row("ij", in: presenter) === current)
        XCTAssertNotNil(try field("Latest Alpha", in: current))
        XCTAssertFalse(presenter.embeddedView.window?.isVisible ?? true)
    }
}
