import AppKit
import SwiftUI
import QuartzCore
import TabnaxCore

/// One material per panel, with every control inside its content view. Keeping the
/// host stable avoids rebuilding the compositor whenever the keyboard cursor moves.
@MainActor final class ThemeSurfaceView: NSView {
    let contents: NSView
    private var effect: NSView?
    private var configuration: (tokens: ThemeTokens, embedded: Bool, radius: CGFloat)?
    private var snapshotFallback = false
    private(set) var activeStyle: ThemeSurfaceStyle = .solid
    override var isFlipped: Bool { true }

    init(contents: NSView) {
        self.contents = contents
        super.init(frame: contents.frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        addSubview(contents)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }

    @discardableResult func configure(tokens: ThemeTokens, embedded: Bool, cornerRadius: CGFloat) -> ThemeSurfaceStyle {
        configuration = (tokens, embedded, cornerRadius)
        let supportsGlass: Bool
        if #available(macOS 26.0, *) { supportsGlass = true } else { supportsGlass = false }
        let style = tokens.surfaceStyle.resolved(
            reduceTransparency: snapshotFallback || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            supportsLiquidGlass: supportsGlass)
        if style != activeStyle {
            contents.removeFromSuperview()
            if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView { glass.contentView = nil }
            effect?.removeFromSuperview(); effect = nil
            switch style {
            case .solid: addSubview(contents)
            case .liquidGlass:
                if #available(macOS 26.0, *) {
                    let glass = NSGlassEffectView(frame: bounds)
                    glass.style = .regular
                    glass.contentView = contents
                    effect = glass; addSubview(glass)
                }
            case .frosted:
                let frost = NSVisualEffectView(frame: bounds)
                frost.material = .hudWindow
                frost.state = .active
                frost.addSubview(contents)
                effect = frost; addSubview(frost)
            }
            activeStyle = style
        }
        if let frost = effect as? NSVisualEffectView { frost.blendingMode = embedded ? .withinWindow : .behindWindow }
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView { glass.cornerRadius = cornerRadius }
        layer?.cornerRadius = cornerRadius
        layer?.backgroundColor = style == .solid ? NSColor(tokens.surface).cgColor : NSColor.clear.cgColor
        effect?.autoresizingMask = [.width, .height]
        contents.autoresizingMask = [.width, .height]
        needsLayout = true
        return style
    }
    override func layout() {
        super.layout()
        effect?.frame = bounds
        contents.frame = bounds
    }
    func useSnapshotFallback(_ enabled: Bool) {
        guard let configuration else { return }
        snapshotFallback = enabled
        configure(tokens: configuration.tokens, embedded: configuration.embedded, cornerRadius: configuration.radius)
        layoutSubtreeIfNeeded()
    }
}

/// AppKit's offscreen cache omits the Liquid Glass compositor (including its
/// content). Export readable opaque palette previews, then restore the live effect.
@MainActor func withThemeSnapshotFallback<T>(in view: NSView, _ operation: () throws -> T) rethrows -> T {
    func surfaces(_ view: NSView) -> [ThemeSurfaceView] {
        (view as? ThemeSurfaceView).map { [$0] } ?? view.subviews.flatMap(surfaces)
    }
    let hosts = surfaces(view)
    hosts.forEach { $0.useSnapshotFallback(true) }
    defer { hosts.forEach { $0.useSnapshotFallback(false) } }
    return try operation()
}

@MainActor private func themeRowFill(_ tokens: ThemeTokens, card: Bool) -> NSColor {
    let opaque = tokens.surfaceStyle == .solid || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    return NSColor(tokens.surface).withAlphaComponent(opaque ? 1 : card ? 0.48 : 0.20)
}

@MainActor protocol ModePresenter: AnyObject {
    func present(_ state: SelectionState, icons: [UUID: NSImage], status: String)
    func dismiss()
}
private final class Canvas: NSView {
    // Every present() reassigns these, usually to the same values. Redraw only on a real
    // change: the panel canvas spans the whole window, so repainting it per keystroke is costly.
    var fill = NSColor.windowBackgroundColor { didSet { if fill != oldValue { needsDisplay = true } } }
    /// Non-zero only for a canvas that is a borderless panel's whole surface: the window is
    /// transparent there, so the rounded shape (and the shadow AppKit derives from it) is drawn.
    var cornerRadius: CGFloat = 0 { didSet { if cornerRadius != oldValue { needsDisplay = true } } }
    var outline: NSColor? { didSet { if outline != oldValue { needsDisplay = true } } }
    var outlineWidth: CGFloat = 1 { didSet { if outlineWidth != oldValue { needsDisplay = true } } }
    /// Hairline rules in this view's coordinates, drawn over the fill.
    var rules: [(rect: CGRect, color: NSColor)] = [] {
        didSet { if !rules.elementsEqual(oldValue, by: { $0.rect == $1.rect && $0.color == $1.color }) { needsDisplay = true } }
    }
    var onAppearanceChanged: (() -> Void)?
    override var isFlipped: Bool { true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); onAppearanceChanged?() }
    override func draw(_ dirtyRect: NSRect) {
        if cornerRadius > 0 {
            fill.setFill(); NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            if let outline {
                let inset = outlineWidth/2, path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: cornerRadius-inset, yRadius: cornerRadius-inset)
                path.lineWidth = outlineWidth; outline.setStroke(); path.stroke()
            }
        } else {
            fill.setFill(); dirtyRect.fill()
        }
        for rule in rules where rule.rect.intersects(dirtyRect) { rule.color.setFill(); rule.rect.fill() }
    }
}
fileprivate final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onBecomeKey: (() -> Void)?
    override func becomeKey() { onBecomeKey?(); super.becomeKey() }
    var onKey: ((NSEvent) -> Void)?
    var onCancel: (() -> Void)?
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
private class SessionButton: NSButton {
    var navigationAction: NavigationAction?
    var onPress: (() -> Void)?
    /// Mouse hover moves the keyboard cursor onto this row/tile, the same way wheel-scroll
    /// hover already does — there's no separate "unhighlight" action, so leaving the pointer
    /// simply leaves the cursor on the last-hovered item, matching standard menu behavior.
    var onHover: (() -> Void)?
    private var pressedAction: (() -> Void)?
    private var trackingPress = false
    private var hoverArea: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect tracks clipping/frame changes automatically. Keeping this area
        // also avoids synthetic exit/enter churn when a cached row is presented again.
        guard hoverArea == nil else { return }
        // .mouseMoved lets a row that was already under a resting pointer pick up the highlight
        // once the pointer really moves; the presenter decides whether a report counts.
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { guard isEnabled else { return }; onHover?() }
    override func mouseMoved(with event: NSEvent) { guard isEnabled else { return }; onHover?() }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressedAction = onPress; trackingPress = true
        super.mouseDown(with:event)
        trackingPress = false; pressedAction = nil
    }
    @objc func press() { if trackingPress { pressedAction?() } else { onPress?() } }
    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; onPress?(); return true }
}
private final class ActionButton: SessionButton {
    convenience init(_ title: String, action: @escaping () -> Void) {
        self.init(frame: .zero); self.title = title; bezelStyle = .rounded
        target = self; self.action = #selector(press); onPress = action
    }
}
/// A tinted card for actionable status, mirroring StatusMenuHeaderView's warning card —
/// truncated footer text plus a hover tooltip is easy to miss entirely.
private final class StatusBanner: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.cornerRadius = 7
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byWordWrapping; label.maximumNumberOfLines = 2
        addSubview(label); setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }
    func update(_ text: String, tokens: ThemeTokens) {
        label.stringValue = text; label.textColor = NSColor(tokens.text)
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor
        setAccessibilityLabel(text)
    }
    override func layout() {
        super.layout()
        label.frame = CGRect(x: 10, y: 6, width: max(0, bounds.width-20), height: max(0, bounds.height-12))
    }
}

/// A display in AppKit points. Stable IDs and an injectable inventory let tests exercise
/// mixed scale factors, negative origins and topology changes without fake NSScreen objects.
struct SwitcherDisplay: Equatable {
    var id: UInt32
    var frame: CGRect
    var visibleFrame: CGRect
    var scale: CGFloat
    @MainActor static func connected() -> [Self] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return Self(id: id.uint32Value, frame: screen.frame, visibleFrame: screen.visibleFrame, scale: screen.backingScaleFactor)
        }
    }
}

/// One coordinator, one input owner, and non-recursive renderers. These renderers only
/// cache a published SelectionState; all actions go back to the single InputRouter.
@MainActor final class SwitcherPresenter: ModePresenter {
    private let primary = SwitcherSurfacePresenter()
    private var mirrors: [UInt32: SwitcherSurfacePresenter] = [:]
    private var ordered: [SwitcherSurfacePresenter] = []
    private weak var owner: SwitcherSurfacePresenter?
    private weak var menuOwner: SwitcherSurfacePresenter?
    private var inventory: [SwitcherDisplay] = []
    private var state = SelectionState()
    private var icons: [UUID: NSImage] = [:]
    private var status = ""
    private var transferringInput = false
    private var presenting = false
    private var wasSimultaneous = false
    /// The router publishes asynchronously. Keep the newest native draft until that
    /// edit revision is acknowledged, so repeated text in an older publication cannot
    /// masquerade as the latest acknowledgement.
    private var pendingQuery: (session: UInt64, text: String, revision: UInt64)?
    private var publishedQueryRevision: UInt64 = 0
    var displayProvider: () -> [SwitcherDisplay] = { SwitcherDisplay.connected() }
    var settings = SettingsDocument() { didSet {
        primary.settings = settings; mirrors.values.forEach { $0.settings = settings }
    } }
    var embedded = false
    var previewOnly = false { didSet {
        primary.previewOnly = previewOnly; mirrors.values.forEach { $0.previewOnly = previewOnly }
    } }
    var previewSize: CGSize?
    var allowsDesktopSpotlight = true
    var desktopSpotlightReady = true
    var embeddedView: NSView { primary.embeddedView }
    var desktopSpotlight: DesktopSpotlight { primary.desktopSpotlight }
    var onSurfaces: (([CGRect]) -> Void)?
    var onChoose: ((TargetID, UInt64) -> Void)?
    var onKey: ((SelectionKey, UInt64) -> Void)?
    var onAction: ((SwitcherAction, UInt64) -> Void)?
    var onMenuTracking: ((Bool, UInt64) -> Void)?
    var onMenuReady: ((UInt64) -> Void)?
    var onMenuDisarm: ((UInt64) -> Void)?
    var onMenuAction: ((SwitcherAction, TargetID, UInt64) -> Void)?
    var onInspectActions: (([SwitcherActionItem], @escaping @MainActor @Sendable ([SwitcherActionItem]) -> Void) -> Void)?
    var onRefresh: (() -> Void)?
    /// App-owned windows/views also serve native verification without desktop capture.
    var panels: [NSPanel] { ordered.map { $0.panel } }
    var inputPanel: NSPanel? { owner?.panel }

    init() { wire(primary); owner = primary }
    private func wire(_ surface: SwitcherSurfacePresenter) {
        surface.onChoose = { [weak self] id, session in
            guard let self, state.active, state.session == session, menuOwner == nil else { return }
            onChoose?(id, session)
        }
        surface.onKey = { [weak self] key, session in
            guard let self, state.active, state.session == session, menuOwner == nil else { return }
            forwardKey(key, session: session)
        }
        surface.onAction = { [weak self] action, session in self?.onAction?(action, session) }
        surface.onInteraction = { [weak self, weak surface] in
            guard let self, let surface else { return }; claimInput(surface)
        }
        surface.onAppearance = { [weak self] in
            guard let self, !presenting else { return }; present(state, icons: icons, status: status)
        }
        surface.onMenuTracking = { [weak self, weak surface] tracking, session in
            guard let self, let surface else { return }
            if tracking {
                claimInput(surface); menuOwner = surface; desktopSpotlight.dismiss()
            } else if menuOwner === surface { menuOwner = nil }
            for copy in ordered { copy.peerMenuTracking = tracking && copy !== surface }
            onMenuTracking?(tracking, session)
        }
        surface.onMenuReady = { [weak self] in self?.onMenuReady?($0) }
        surface.onMenuDisarm = { [weak self] in self?.onMenuDisarm?($0) }
        surface.onMenuAction = { [weak self] in self?.onMenuAction?($0, $1, $2) }
        surface.onInspectActions = { [weak self] items, completion in
            if let inspect = self?.onInspectActions { inspect(items, completion) }
            else { completion(items.map { item in
                var item = item
                if item.disabledReason == nil { item.disabledReason = "Preview does not control real windows" }
                return item
            }) }
        }
        surface.onRefresh = { [weak self] in self?.onRefresh?() }
    }
    private func configure(_ surface: SwitcherSurfacePresenter) {
        surface.settings = settings; surface.embedded = embedded; surface.previewOnly = previewOnly
        surface.previewSize = previewSize; surface.desktopSpotlightReady = desktopSpotlightReady
        surface.allowsDesktopSpotlight = surface === primary && allowsDesktopSpotlight && menuOwner == nil
        surface.ownsInput = surface === owner
        surface.peerMenuTracking = menuOwner != nil && menuOwner !== surface
    }
    private func forwardKey(_ key: SelectionKey, session: UInt64) {
        if case .query(let text) = key {
            pendingQuery = (session, String(text.prefix(1024)), max(publishedQueryRevision, pendingQuery?.revision ?? 0) &+ 1)
            for copy in ordered where copy !== owner {
                copy.search.stringValue = text
            }
        }
        onKey?(key, session)
    }
    private func claimInput(_ surface: SwitcherSurfacePresenter) {
        guard !transferringInput, menuOwner == nil || menuOwner === surface,
              ordered.contains(where: { $0 === surface }), owner !== surface else { return }
        transferringInput = true
        defer { transferringInput = false }
        // Finish composition in its original native editor before moving ownership.
        // Never copy an NSTextInputContext or let two editors maintain marked ranges.
        var transferredText: String?, transferredSelection: NSRange?
        if let old = owner {
            if let editor = old.search.currentEditor() as? NSTextView {
                editor.unmarkText()
                transferredText = editor.string; transferredSelection = editor.selectedRange()
                if state.query != editor.string || pendingQuery != nil { forwardKey(.query(editor.string), session: state.session) }
            }
            old.panel.makeFirstResponder(old.panel)
            old.ownsInput = false
        }
        owner = surface; surface.ownsInput = true
        if let transferredText { surface.search.stringValue = transferredText }
        if !previewOnly && !embedded {
            surface.panel.makeKeyAndOrderFront(nil)
            if state.query != nil {
                surface.focusSearch(session: state.session)
                if let range = transferredSelection, let editor = surface.search.currentEditor() as? NSTextView {
                    let length = (editor.string as NSString).length
                    let start = min(range.location, length)
                    editor.setSelectedRange(NSRange(location: start, length: min(range.length, length-start)))
                }
            }
            else { surface.panel.makeFirstResponder(surface.panel) }
        }
    }
    func present(_ state: SelectionState, icons: [UUID: NSImage], status: String) {
        guard state.active else { dismiss(); return }
        let screens = displayProvider().filter { $0.visibleFrame.width > 1 && $0.visibleFrame.height > 1 }
        guard !screens.isEmpty || embedded || previewOnly else { dismiss(); return }
        let simultaneous = settings.allDisplays && !embedded && !previewOnly
        // Topology is frozen for an opening. AppDelegate cancels the router on changes;
        // this guard also ensures callers cannot retain windows on removed displays.
        if self.state.active, inventory != screens || wasSimultaneous != simultaneous { dismiss() }
        let opening = !self.state.active || self.state.session != state.session || self.state.mode != state.mode
        if opening {
            dismiss(); inventory = screens; wasSimultaneous = simultaneous
            ordered = [primary]; owner = primary
            primary.panel.identifier = .init("switcher")
            primary.displayBounds = nil
            if simultaneous, !screens.isEmpty {
                let focused = state.snapshot.windows.first { $0.id == state.focusHistory.current }?.bounds
                let focusFrame = focused.map { CGRect(x: $0.minX, y: screens[0].frame.maxY - $0.maxY, width: $0.width, height: $0.height) }
                let initial: SwitcherDisplay?
                switch settings.placement(for: state.mode).display {
                case .main: initial = screens.first
                case .pointer: initial = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                case .focused:
                    initial = focusFrame.flatMap { rect in screens.max { a, b in
                        let a = a.frame.intersection(rect), b = b.frame.intersection(rect)
                        return (a.isNull ? 0 : a.width*a.height) < (b.isNull ? 0 : b.width*b.height)
                    } }
                }
                let first = initial ?? screens.first!
                primary.displayBounds = first.visibleFrame
                for screen in screens where screen.id != first.id {
                    let copy = SwitcherSurfacePresenter(); wire(copy)
                    copy.displayBounds = screen.visibleFrame
                    copy.panel.identifier = .init("switcher-display-\(screen.id)")
                    copy.panel.title = "Tabnax window switcher · display \(screen.id)"
                    mirrors[screen.id] = copy; ordered.append(copy)
                }
            }
        }
        publishedQueryRevision = state.queryRevision
        var state = state
        if let draft = pendingQuery {
            if draft.session != state.session || state.query == nil || state.queryRevision >= draft.revision { pendingQuery = nil }
            else { _ = state.handle(.query(draft.text)) }
        }
        self.state = state; self.icons = icons; self.status = status
        presenting = true
        defer { presenting = false }
        for copy in ordered {
            configure(copy)
            copy.sharedBeaconBank = simultaneous
            copy.showsPlaques = copy === primary
        }
        // Mirrors contain full banks; place them before planning unique spatial plaques.
        for copy in ordered.dropFirst() { copy.present(state, icons: icons, status: status) }
        primary.additionalReservedFrames = ordered.dropFirst().map { $0.panel.frame }
        primary.present(state, icons: icons, status: status)
        if !embedded { onSurfaces?(ordered.flatMap(\.surfaceFrames)) }
    }
    func dismiss() {
        state.cancel(); pendingQuery = nil
        for copy in ordered { copy.dismiss() }
        if ordered.isEmpty { primary.dismiss() }
        mirrors.removeAll(); ordered.removeAll(); inventory.removeAll(); owner = primary; menuOwner = nil
        primary.peerMenuTracking = false
        onSurfaces?([])
    }
    @discardableResult func prepare(_ snapshot: CatalogueSnapshot, icons: [UUID: NSImage]) -> Task<Void, Never>? {
        configure(primary); return primary.prepare(snapshot, icons: icons)
    }
    func focusSearch(session: UInt64) { owner?.focusSearch(session: session) }
    func deliverSearchInput(_ event: CGEvent, session: UInt64) { owner?.deliverSearchInput(event, session: session) }
    func restoreSearchInputAfterPreview() { owner?.restoreSearchInputAfterPreview() }
    func showActionMenu(for state: SelectionState? = nil) { (owner ?? primary).showActionMenu(for: state) }
    func performMenuShortcut(_ action: SwitcherAction, session: UInt64) {
        menuOwner?.performMenuShortcut(action, session: session)
    }
    func makeActionMenu(_ items: [SwitcherActionItem], title: String, session: UInt64) -> NSMenu {
        configure(primary); return primary.makeActionMenu(items, title: title, session: session)
    }
    func showActionOutcome(_ message: String, action: SwitcherAction, target: TargetID) {
        let accepted = ordered.map { $0.showActionOutcome(message, action: action, target: target) }.contains(true)
        if state.active && accepted { present(state, icons: icons, status: message) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        (owner ?? primary).control(control, textView: textView, doCommandBy: selector)
    }
    func savePreview(to path: String) throws { try primary.savePreview(to: path) }
    func saveDisplayPreviews(to directory: String) throws {
        for (index, copy) in ordered.enumerated() { try copy.savePreview(to: "\(directory)/display-\(index).png") }
    }
}

/// Constructs only the selected layout. All input and identity live outside the views.
@MainActor final class SwitcherSurfacePresenter: NSObject, ModePresenter, NSSearchFieldDelegate {
    fileprivate let panel = SwitcherSurfacePresenter.makePanel(String(localized: "Tabnax window switcher"), id: "switcher")
    private let content = Canvas()
    private lazy var surface = ThemeSurfaceView(contents: content)
    private let hint = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let searchButton = ActionButton(String(localized: "Search  /")) {}
    private let backButton = ActionButton("") {}
    private let closeButton = ActionButton("") {}
    private let helpButton = ActionButton("") {}
    private let actionsButton = ActionButton("") {}
    private var trackingMenu = false
    private var activeMenu: NSMenu?
    private var menuGeneration: UInt64 = 0
    private var actionStatus: (session: UInt64, message: String)?
    private var pendingMenuAction: (session: UInt64, action: SwitcherAction, target: TargetID)?
    private let statusBanner = StatusBanner(frame: .zero)
    fileprivate let search = NSSearchField()
    private let scroll = NSScrollView()
    private let body = Canvas()
    private var rows: [TargetID: TargetRow] = [:]
    private var desiredBodyViews: [NSView] = []
    private var preparationTask: Task<Void, Never>?
    private var preparationGeneration: UInt64 = 0
    private var plaques: [TargetID: SwitcherPanel] = [:]
    let desktopSpotlight = DesktopSpotlight()
    private var familyButtons: [String: ActionButton] = [:]
    private var familyIcons: [String: NSImageView] = [:]
    private var familyMinimizedBadges: [String: MinimizedBadge] = [:]
    private var familyLabels: [String: NSTextField] = [:]
    private var familyAddresses: [String: NSTextField] = [:]
    private var branchTiles: [String: BranchTile] = [:]
    private let emptyStateRefresh = ActionButton(String(localized: "Refresh")) {}
    private var labelPool: [NSTextField] = []
    private var labelCursor = 0
    private var imagePool: [NSImageView] = []
    private var imageCursor = 0
    fileprivate var lastState = SelectionState()
    private var display: NSScreen?
    private var shownMode: DisplayMode?
    private var previouslySearching = false
    private var lastIcons: [UUID:NSImage] = [:]
    private var lastStatus = ""
    var displayBounds: CGRect?
    var sharedBeaconBank = false
    var showsPlaques = true
    var additionalReservedFrames: [CGRect] = []
    private var plaqueRows: [TargetID: TargetRow] = [:]
    var ownsInput = true
    var peerMenuTracking = false
    var onInteraction: (() -> Void)?
    var onAppearance: (() -> Void)?
    var surfaceFrames: [CGRect] { [panel.frame] + plaques.values.filter(\.isVisible).map(\.frame) }
    var settings = SettingsDocument() { didSet {
        if settings != oldValue { needsFullPresent = true; cancelPreparation() }
    } }
    /// Set whenever something present() reads changed outside its arguments.
    private var needsFullPresent = true
    /// Derived once per present() and shared by every row/tile built in that frame.
    private var frameMatches: [Target] = []
    private var frameMatchIDs = Set<TargetID>()
    private var frameMinimizedOwners = Set<UUID>()
    private var frameHighlight: NavigationAction?
    /// Shared stand-in for apps without an icon, so a frame never reassigns a fresh image.
    private static let placeholderIcon = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
    /// Also derived once per present(): these SelectionState properties re-filter and re-sort
    /// every target on each read, and the layout reads them several times per frame.
    private var frameDisplayTargets: [Target] = []
    private var frameLatticeCells: [AddressCell] = []
    /// Collected while laying out, then handed to the body in one assignment.
    private var frameRules: [(rect: CGRect, color: NSColor)] = []
    /// Where the pointer rested when the keyboard last owned the highlight. Rebuilding or
    /// scrolling rows under a resting pointer raises mouseEntered without the mouse moving,
    /// so hover is ignored until the pointer has actually left this spot.
    private var hoverAnchor: CGPoint?
    /// When hover last asked for the highlight, so the frame it causes is not mistaken for a
    /// keyboard move. A timestamp rather than a flag: a refused request produces no frame.
    private var hoverSent: CFTimeInterval = 0
    var onSurfaces: (([CGRect]) -> Void)?
    private var mouseMonitor: Any?
    private var wheel = WheelGesture()
    private var sessionPlacement = Placement()
    /// Recomputed once per present() call and read by row()/label()/lattice()/fold();
    /// avoids re-resolving the palette on every row and section label within a frame.
    private var tokens = ThemeTokens.resolve(AppearancePreferences(),dark:false)
    /// Cache for ThemeTokens.resolve keyed by the inputs it depends on; present() is called
    /// far more often than appearance actually changes, so skip re-resolving when it hasn't.
    private var cachedTokensKey: (appearance: AppearancePreferences, dark: Bool)?
    /// Derived from the tokens once per present(): divider rules, and the outline of card rows.
    private var hairline = NSColor.separatorColor, cardLine = NSColor.separatorColor
    /// A transparent window's shadow follows its drawn shape, so it is rebuilt on resize.
    private var shadowSize = CGSize.zero
    private var sessionHeight: CGFloat = 0
    private var rowHeight: CGFloat { (embedded ? 42 : 54) + (settings.appearance.scale.factor-1)*30 }
    private var rowStride: CGFloat { rowHeight + (embedded ? 4 : 6) }
    private var tileHeight: CGFloat { 112 + (settings.appearance.scale.factor-1)*40 }
    private var sectionHeight: CGFloat { 32 * settings.appearance.scale.factor }
    var embedded = false
    var embeddedView: NSView { surface }
    var previewOnly = false
    var allowsDesktopSpotlight = true { didSet { if oldValue != allowsDesktopSpotlight { needsFullPresent = true } } }
    var desktopSpotlightReady = true {
        didSet { if oldValue != desktopSpotlightReady { needsFullPresent = true } }
    }
    var previewSize: CGSize?
    var onChoose: ((TargetID, UInt64) -> Void)?
    var onKey: ((SelectionKey, UInt64) -> Void)?
    var onAction: ((SwitcherAction, UInt64) -> Void)?
    var onMenuTracking: ((Bool, UInt64) -> Void)?
    var onMenuReady: ((UInt64) -> Void)?
    var onMenuDisarm: ((UInt64) -> Void)?
    var onMenuAction: ((SwitcherAction, TargetID, UInt64) -> Void)?
    var onInspectActions: (([SwitcherActionItem], @escaping @MainActor @Sendable ([SwitcherActionItem]) -> Void) -> Void)?
    /// Wired by the app delegate to the same catalogue refresh the status-bar menu's
    /// "Refresh Windows" item triggers; nil until then, so the button is a no-op until wired.
    var onRefresh: (() -> Void)?
    override init() {
        super.init()
        panel.contentView = surface
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail; footer.lineBreakMode = .byTruncatingTail
        search.placeholderString = String(localized: "Search windows, tabs & apps"); search.delegate = self
        search.sendsSearchStringImmediately = true
        search.setAccessibilityLabel(String(localized: "Search windows or apps")); search.identifier = .init("switcher-search")
        scroll.documentView = body; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        statusBanner.isHidden = true
        for view in [hint, search, scroll, footer, statusBanner, searchButton, backButton, closeButton, helpButton, actionsButton] { content.addSubview(view) }
        searchButton.onPress = { [weak self] in
            guard let self else { return }
            send(lastState.query == nil ? .beginSearch : .escape)
        }
        searchButton.identifier = .init("begin-search")
        backButton.onPress = { [weak self] in self?.send(.backspace) }
        closeButton.onPress = { [weak self] in self?.send(.dismiss) }
        helpButton.onPress = { [weak self] in self?.showKeyboardHelp() }
        actionsButton.onPress = { [weak self] in self?.showActionMenu() }
        for (button, symbol, label, id) in [
            (backButton, "chevron.left", String(localized: "Go back one letter"), "back-prefix"),
            (closeButton, "xmark", String(localized: "Close switcher"), "close-switcher"),
            (helpButton, "questionmark.circle", String(localized: "Keyboard shortcuts"), "switcher-help"),
            (actionsButton, "ellipsis.circle", String(localized: "Window actions"), "switcher-actions")
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly; button.isBordered = false
            button.setAccessibilityLabel(label); button.toolTip = label; button.identifier = .init(id)
        }
        actionsButton.toolTip = String(localized: "Actions for highlighted target (⌘.)")
        panel.onBecomeKey = { [weak self] in self?.onInteraction?() }
        panel.onKey = { [weak self] in _ = self?.localKey($0) }
        panel.onCancel = { [weak self] in if self?.trackingMenu != true { self?.send(.escape) } }
        content.onAppearanceChanged = { [weak self] in DispatchQueue.main.async { self?.refreshAppearance() } }
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(refreshAppearance),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
    }
    @objc private func refreshAppearance() {
        guard lastState.active else { return }
        needsFullPresent = true
        if let onAppearance { onAppearance() } else { present(lastState,icons:lastIcons,status:lastStatus) }
    }
    private func startMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { EventRoute(event: self == nil ? event : self!.mouse(event)) }.event
        }
    }
    private func send(_ key: SelectionKey) { guard !peerMenuTracking else { return }; onKey?(key,lastState.session) }
    private func showKeyboardHelp() {
        guard !trackingMenu, !peerMenuTracking else { return }
        let session = lastState.session
        beginMenu(session: session)
        defer { endMenu(session: session) }
        let menu = NSMenu()
        activeMenu = menu
        let searching = lastState.query != nil
        let enter = lastState.mode == .relay && lastState.query == nil
            ? String(localized: "↵  Switch to previous window") : String(localized: "↵  Select highlighted item")
        var shortcuts = [searching ? String(localized: "Search by app, window or tab title") : String(localized: "Type an item's letters to select it"),
                         String(localized: "↑ ↓ / Tab  Move selection"), enter,
                         searching ? String(localized: "Esc  Exit search") : String(localized: "Esc  Back / Close"),
                         String(localized: "⌘ Q  Quit highlighted app")]
        if settings.windowActionsEnabled {
            shortcuts.append(String(localized: "⌘ .  Window actions"))
            shortcuts += lastState.actionMenuItems.filter { $0.action != .quitApplication }.map { "\($0.action.shortcut.label)  \($0.action.title)" }
        }
        if !searching {
            shortcuts += [String(localized: "/  Search"), String(localized: "⌫  Go back one letter"), String(localized: "⌥  Restore minimized window")]
        }
        for text in shortcuts {
            menu.addItem(withTitle: text, action: nil, keyEquivalent: "")
        }
        onMenuReady?(session)
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: helpButton.bounds.maxY), in: helpButton)
    }
    private func beginMenu(session: UInt64) {
        trackingMenu = true; menuGeneration &+= 1
        onMenuTracking?(true, session)
        desktopSpotlight.dismiss()
    }
    private func endMenu(session: UInt64) {
        activeMenu = nil; trackingMenu = false
        onMenuTracking?(false, session)
        // NSMenu restores the existing responder. Re-selecting the search control here
        // would select all of its text and discard the user's insertion/marked-text state.
    }
    func showActionMenu(for state: SelectionState? = nil) {
        let frozen = state ?? lastState
        guard !embedded, !trackingMenu, !peerMenuTracking, frozen.active, settings.windowActionsEnabled else { return }
        beginMenu(session: frozen.session)
        let generation = menuGeneration
        let title = frozen.highlightedTarget.map { $0.id.window == nil ? $0.app : "\($0.app) · \($0.title)" } ?? "Highlighted target"
        let items = frozen.actionMenuItems
        let complete: @MainActor @Sendable ([SwitcherActionItem]) -> Void = { [weak self] checked in
            guard let self, generation == menuGeneration else { return }
            guard lastState.active, lastState.session == frozen.session else { endMenu(session: frozen.session); return }
            let menu = makeActionMenu(checked, title: title, session: frozen.session)
            activeMenu = menu
            onMenuReady?(frozen.session)
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: actionsButton.bounds.maxY), in: actionsButton)
            endMenu(session: frozen.session)
        }
        if previewOnly || onInspectActions == nil {
            complete(items.map { entry in
                var entry = entry
                if entry.disabledReason == nil { entry.disabledReason = "Preview does not control real windows" }
                return entry
            })
        } else { onInspectActions?(items, complete) }
    }
    /// Builds a native menu with immutable action/target pairs. Kept separate from
    /// tracking so the exact commands can be verified without acting on desktop windows.
    func makeActionMenu(_ checked: [SwitcherActionItem], title: String, session: UInt64) -> NSMenu {
        let menu = NSMenu(title: "Window actions"); menu.autoenablesItems = false
        let heading = menu.addItem(withTitle: String(title.prefix(90)), action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(.separator())
        for entry in checked {
            let label = entry.action.title + (entry.disabledReason.map { " — \($0)" } ?? "")
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: entry.action.shortcut.keyEquivalent)
            item.keyEquivalentModifierMask = entry.action.shortcut.modifiers
            item.identifier = .init("action-\(entry.action.rawValue)")
            item.toolTip = entry.disabledReason ?? "\(entry.action.title): \(title)"
            item.isEnabled = entry.target != nil && entry.disabledReason == nil
            if let id = entry.target, item.isEnabled {
                let command = SwitcherMenuCommand { [weak self] in
                    guard let self, !previewOnly else { return }
                    pendingMenuAction = (session, entry.action, id)
                    onMenuAction?(entry.action, id, session)
                }
                item.target = command; item.action = #selector(SwitcherMenuCommand.invokeAction(_:)); item.representedObject = command
            }
            menu.addItem(item)
        }
        return menu
    }
    func performMenuShortcut(_ action: SwitcherAction, session: UInt64) {
        guard trackingMenu, lastState.active, lastState.session == session else { return }
        activeMenu?.performWindowActionShortcut(action)
    }
    private func hover(_ action: NavigationAction, session: UInt64) {
        guard !trackingMenu, !peerMenuTracking, lastState.active, lastState.session == session, settings.mouse != .off, frameHighlight != action else { return }
        if let anchor = hoverAnchor {
            let pointer = NSEvent.mouseLocation
            guard hypot(pointer.x-anchor.x, pointer.y-anchor.y) > 4 else { return }
            hoverAnchor = nil
        }
        hoverSent = CACurrentMediaTime(); send(.highlight(action))
    }
    private func mouse(_ event: NSEvent) -> NSEvent? {
        if trackingMenu || peerMenuTracking { return event }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
           event.window === panel || plaques.values.contains(where: { $0 === event.window }) {
            onInteraction?()
        }
        if event.type == .leftMouseDown, event.window === panel {
            let point = content.convert(event.locationInWindow, from: nil)
            if (!actionsButton.isHidden && actionsButton.frame.contains(point)) || helpButton.frame.contains(point) {
                // NSButton invokes on mouse-up. Protect a release while the button is held.
                onMenuDisarm?(lastState.session)
            }
        }
        // Observe gesture boundaries even when the pointer is outside our body.
        if event.type == .scrollWheel, event.phase.contains(.began) || event.phase.contains(.mayBegin) || event.phase.contains(.ended) || event.phase.contains(.cancelled) { wheel.reset() }
        guard !previewOnly || embedded, lastState.active, event.window === panel || (embedded && event.window === content.window) || plaques.values.contains(where: { $0 === event.window }) else { return event }
        // Native panels can handle Escape before their responder's keyDown.
        // Route direct commands once, before AppKit's default cancel handling.
        // Embedded settings previews leave all keyboard input to their controls.
        if event.type == .keyDown {
            return !embedded && localKey(event) ? nil : event
        }
        let point = content.convert(event.locationInWindow,from:nil)
        let inBody = scroll.frame.contains(point)
        let inPlaque = plaques.values.contains { $0 === event.window }
        guard inBody || inPlaque else { return event }
        if settings.mouse == .off { return nil }
        guard event.type == .scrollWheel, settings.mouse == .clickAndWheel, inBody, !inPlaque else { return event }
        let region = lastState.mode == .fold && point.x < scroll.frame.minX + min(240,body.frame.width*0.36) ? "family" : "targets"
        let phase: WheelPhase = event.phase.contains(.began) ? .began : event.phase.contains(.mayBegin) ? .mayBegin : event.phase.contains(.ended) ? .ended : event.phase.contains(.cancelled) ? .cancelled : event.phase.isEmpty ? .unphased : .changed
        if let movement = wheel.navigate(region:region,phase:phase,delta:-event.scrollingDeltaY,precise:event.hasPreciseScrollingDeltas,momentum:!event.momentumPhase.isEmpty,horizontal:event.scrollingDeltaX) {
            let (region,steps) = movement
            let navigable = Set(lastState.navigationItems.map(\.action))
            let actions = body.subviews.compactMap { $0 as? SessionButton }.filter { button in
                guard button.isEnabled,let action = button.navigationAction else { return false }
                if lastState.mode == .fold {
                    let isFamily = button.accessibilityIdentifier().hasPrefix("family-")
                    return isFamily == (region == "family") && (lastState.query == nil || navigable.contains(action))
                }
                return navigable.contains(action)
            }.compactMap(\.navigationAction)
            if !actions.isEmpty {
                let index = actions.firstIndex(where: { $0 == frameHighlight }) ?? (steps > 0 ? -1 : actions.count)
                send(.highlight(actions[max(0,min(actions.count-1,index+steps))]))
            }
        }
        return nil
    }
    private static func makePanel(_ title: String, id: String) -> SwitcherPanel {
        let panel = SwitcherPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 650),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title; panel.identifier = .init(id); panel.level = .floating
        // Without .fullScreenAuxiliary the panel cannot appear over another app's full-screen Space.
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        // The canvas paints an opaque rounded surface; the window itself is clear so its corners
        // (and the shadow AppKit derives from the drawn shape) follow that radius.
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
        panel.animationBehavior = .none
        return panel
    }
    @discardableResult private func localKey(_ event: NSEvent) -> Bool {
        let shortcutAction = WindowActionShortcut.action(code: event.keyCode,
            flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)), activation: CGEventFlags(rawValue: settings.activation.modifiers))
        if trackingMenu, let shortcutAction {
            if !event.isARepeat { performMenuShortcut(shortcutAction, session: lastState.session) }
            return true
        }
        guard !trackingMenu, !peerMenuTracking else { return false }
        if settings.windowActionsEnabled, InputRouter.isActionMenuShortcut(code: event.keyCode,
            flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)), activation: CGEventFlags(rawValue: settings.activation.modifiers)) {
            if !event.isARepeat { showActionMenu() }; return true
        }
        if let shortcutAction, shortcutAction == .quitApplication || settings.windowActionsEnabled {
            if !event.isARepeat, !previewOnly { onAction?(shortcutAction, lastState.session) }
            return true
        }
        guard lastState.query == nil else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let key: SelectionKey?
        switch event.keyCode {
        case 53: key = .escape
        case 51: key = .backspace
        case 48, 125: key = event.modifierFlags.contains(.shift) ? .previous : .next
        case 126: key = .previous
        case 123: key = .lateral(-1)
        case 124: key = .lateral(1)
        case 36, 76: key = .enter
        case 44: key = .beginSearch
        default:
            let letter = settings.selection.interpretation == .physical ? InputRouter.letters[event.keyCode] : event.charactersIgnoringModifiers?.lowercased()
            key = letter.map { .letter($0) }
        }
        // A stray key is swallowed, as in the router, rather than beeping; function keys pass.
        guard let key else { return !InputRouter.functionKeys.contains(event.keyCode) }
        if !event.isARepeat { send(key) }; return true
    }
    func controlTextDidBeginEditing(_ obj: Notification) { onInteraction?() }
    func controlTextDidChange(_ obj: Notification) {
        guard ownsInput, lastState.active else { return }
        send(.query(search.stringValue))
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !trackingMenu, !peerMenuTracking else { return false }
        // AppKit resolves marked text before these commands; search uses the native field editor.
        guard !textView.hasMarkedText() else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): send(.enter)
        case #selector(NSResponder.cancelOperation(_:)): send(.escape)
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)): send(.next)
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)): send(.previous)
        default: return false
        }
        return true
    }
    /// Warms reusable row content without opening a session, fixing placement, ordering a
    /// window, installing input monitors, or announcing anything to accessibility clients.
    /// Each batch yields to input; a newer catalogue or actual presentation cancels it.
    @discardableResult func prepare(_ snapshot: CatalogueSnapshot, icons: [UUID: NSImage]) -> Task<Void, Never>? {
        guard !embedded, !lastState.active else { return nil }
        cancelPreparation()
        let generation = preparationGeneration
        var state = SelectionState(); state.configure(mode: settings.mode); state.update(snapshot)
        // Bound retained preparation for large tab catalogues. First-use rows beyond the
        // cache remain correct and are built by the ordinary layout when needed.
        let targets = Array(state.displayTargets.prefix(128))
        let appearance = settings.appearance
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self, !Task.isCancelled, generation == preparationGeneration, !lastState.active else { return }
            let native = appearance.source == .system ? content.effectiveAppearance : NSAppearance(named: appearance.source == .dark ? .darkAqua : .aqua)!
            let palette = ThemeTokens.resolve(appearance, dark: native.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            let live = Set(state.targets.map(\.id))
            rows = rows.filter { live.contains($0.key) }
            var index = 0
            while index < targets.count {
                guard !Task.isCancelled, generation == preparationGeneration, !lastState.active else { return }
                let started = CACurrentMediaTime()
                repeat {
                    let target = targets[index]
                    let row = rows[target.id] ?? TargetRow(); rows[target.id] = row
                    row.style = appearance; row.compact = false
                    row.grouped = state.mode == .canopy || state.mode == .fold
                    // Never change the layout of an attached, retained row while hidden.
                    if row.superview == nil { row.frame = CGRect(x: 0, y: 0, width: 260, height: rowHeight) }
                    row.bind(target, image: icons[target.id.process], matches: true, selected: false, tokens: palette)
                    row.layoutSubtreeIfNeeded()
                    index += 1
                } while index < targets.count && CACurrentMediaTime()-started < 0.002
                if index < targets.count { try? await Task.sleep(for: .milliseconds(1)) }
            }
            if generation == preparationGeneration { preparationTask = nil }
        }
        preparationTask = task
        return task
    }
    private func cancelPreparation() {
        preparationGeneration &+= 1
        preparationTask?.cancel(); preparationTask = nil
    }
    private func attachToBody(_ view: NSView) {
        desiredBodyViews.append(view)
        if view.superview !== body { body.addSubview(view) }
    }
    private func reconcileBodyViews() {
        let wanted = Set(desiredBodyViews.map(ObjectIdentifier.init))
        for view in body.subviews where !wanted.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
        // Subview order is also the mouse-wheel navigation order. Only touch it when
        // identities/order really changed, retaining AppKit tracking and layout state.
        if body.subviews.map(ObjectIdentifier.init) != desiredBodyViews.map(ObjectIdentifier.init) {
            body.subviews = desiredBodyViews
        }
        desiredBodyViews.removeAll(keepingCapacity: true)
    }
    func present(_ state: SelectionState, icons: [UUID: NSImage], status: String) {
        guard state.active else { dismiss(); return }
        let status = actionStatus?.session == state.session ? actionStatus!.message : status
        cancelPreparation()
        Trace.log.info("perf: present entry t=\(CACurrentMediaTime(), privacy: .public) mode=\(state.mode.rawValue, privacy: .public)")
        let previousStatus = lastStatus, previousMode = shownMode
        let opening = shownMode != state.mode || lastState.session != state.session || (!previewOnly && !panel.isVisible)
        // Catalogue publishes arrive in bursts while the panel is open (every process answers
        // the on-open refresh separately) and most change nothing on screen.
        if !opening, !needsFullPresent, !embedded, !previewOnly, status == lastStatus, icons == lastIcons, state.rendersSame(as: lastState) {
            lastState = state; return
        }
        lastIcons = icons; lastStatus = status
        if opening {
            dismiss(); shownMode = state.mode
            sessionPlacement = settings.placement(for:state.mode)
            let focused = state.snapshot.windows.first { $0.id == state.focusHistory.current }.flatMap { cocoaBounds($0.bounds) }
            let mouse = NSEvent.mouseLocation
            let pointer = NSScreen.screens.first { NSMouseInRect(mouse,$0.frame,false) } ?? NSScreen.screens.first { $0.frame.insetBy(dx:-1,dy:-1).contains(mouse) }
            let focusDisplay = focused.flatMap { rect in NSScreen.screens.max { a,b in a.frame.intersection(rect).width*a.frame.intersection(rect).height < b.frame.intersection(rect).width*b.frame.intersection(rect).height } }
            display = switch sessionPlacement.display { case .focused: focusDisplay ?? NSScreen.main; case .pointer: pointer ?? NSScreen.main; case .main: NSScreen.screens.first }
            display = display ?? NSScreen.screens.first
        }
        startMouseMonitor()
        let cursorMoved = opening || lastState.cursor != state.cursor || lastState.prefix != state.prefix || lastState.query != state.query
        if cursorMoved || lastState.pointerFocus != state.pointerFocus {
            if opening || CACurrentMediaTime()-hoverSent > 0.25 { hoverAnchor = NSEvent.mouseLocation }
        }
        if opening || lastState.prefix != state.prefix || lastState.query != state.query { wheel.reset() }
        lastState = state
        frameMatches = state.displayMatches; frameMatchIDs = Set(frameMatches.map(\.id)); frameHighlight = state.highlightedAction
        frameDisplayTargets = state.displayTargets
        frameLatticeCells = state.mode == .lattice ? state.latticeCells : []
        frameMinimizedOwners = Set(state.snapshot.windows.filter { $0.minimized && $0.available && $0.isRunning }.map(\.groupOwner))
        let appearance = settings.appearance.source
        let nativeAppearance: NSAppearance? = appearance == .system ? nil : NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        if panel.appearance?.name != nativeAppearance?.name { panel.appearance = nativeAppearance }
        if surface.appearance?.name != nativeAppearance?.name { surface.appearance = nativeAppearance }
        if content.appearance?.name != nativeAppearance?.name { content.appearance = nativeAppearance }
        let dark = (nativeAppearance ?? content.effectiveAppearance).bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        if let cached = cachedTokensKey, cached.appearance == settings.appearance, cached.dark == dark {
            // Appearance hasn't changed since the last present(); reuse the resolved palette.
        } else {
            tokens = ThemeTokens.resolve(settings.appearance,dark:dark)
            cachedTokensKey = (settings.appearance, dark)
        }
        let material = surface.configure(tokens: tokens, embedded: embedded, cornerRadius: embedded ? 9 : 20)
        content.fill = NSColor(tokens.surface).withAlphaComponent(material == .solid ? 1 : material == .frosted ? 0.28 : 0.08)
        body.fill = .clear
        // Borders and rules are the text colour mixed into the surface rather than a system
        // separator, so they stay in family with every theme and both appearances.
        let strong = settings.appearance.strongOutlines || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if allowsDesktopSpotlight && !trackingMenu && !embedded && !previewOnly {
            desktopSpotlight.present(state, preferences: settings.appearance.desktopSpotlight,
                                     accent: NSColor(tokens.selection), strong: strong, screens: NSScreen.screens.map(\.frame), ready: desktopSpotlightReady)
        } else { desktopSpotlight.dismiss() }
        // On glass/frosted surfaces a fully opaque rule reads as a hard seam cut through the
        // blur. Mixing further towards the text colour but drawing it back at partial alpha
        // keeps the line legible while letting it sit on the material like a real hairline.
        let glassSurface = material != .solid
        let lineAlpha: CGFloat = glassSurface ? (strong ? 0.85 : 0.55) : 1
        hairline = NSColor(tokens.surface.mixed(with:tokens.text,amount:strong ? 0.5 : (glassSurface ? 0.22 : 0.1))).withAlphaComponent(lineAlpha)
        cardLine = NSColor(tokens.surface.mixed(with:tokens.text,amount:strong ? 0.6 : (glassSurface ? 0.3 : 0.14))).withAlphaComponent(lineAlpha)
        // Settings clips its embedded preview itself; only a real panel owns its corners.
        content.cornerRadius = embedded ? 0 : 20
        content.outline = NSColor(tokens.surface.mixed(with:tokens.text,amount:strong ? 0.6 : (glassSurface ? 0.32 : 0.22))).withAlphaComponent(lineAlpha); content.outlineWidth = strong ? 2 : 1
        // Mirrors TargetRow.bind's contrast handling: fall back from the secondary token
        // to the full-strength text token when the system asks for increased contrast.
        let secondaryText = NSColor(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? tokens.text : tokens.secondary)
        hint.textColor = secondaryText; footer.textColor = secondaryText
        var safe = displayBounds ?? display?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        if let previewSize { safe.size.width = min(safe.width, previewSize.width); safe.size.height = min(safe.height, previewSize.height) }
        let searchMode = state.query != nil
        let mode = state.mode
        let targetName = "windows, tabs & apps"
        let searchLabel = String(localized: "Search \(targetName)")
        if search.placeholderString != searchLabel { search.placeholderString = searchLabel }
        if search.accessibilityLabel() != searchLabel { search.setAccessibilityLabel(searchLabel) }
        // Search filters inside the mode's own layout, so the panel keeps that mode's size too.
        var geometry = SwitcherGeometry.size(mode:mode,count:frameDisplayTargets.count,rowStride:rowStride)
        if mode != .shore { geometry.height = max(180, geometry.height-100) }
        if mode == .shore {
            // Size the narrow index to its actual chrome. Keep its full-session row
            // allowance while filtering so the panel does not jump with every letter.
            let rowsHeight: CGFloat = frameDisplayTargets.isEmpty ? 66 : CGFloat(min(12, frameDisplayTargets.count))*rowStride
            let searchHeight: CGFloat = searchMode ? 36 : 0
            let warningHeight: CGFloat = status.isEmpty ? 0 : 44
            geometry.height = rowsHeight + 64 + searchHeight + warningHeight
        }
        if mode == .canopy {
            // Canopy hugs its content: enough columns for every app group, widened up
            // to whatever the screen allows, but never narrower than fold's layout.
            // Sized off the full target set (not the prefix-filtered matches) so typing
            // a letter dims non-matching tiles in place instead of reflowing the grid.
            let columns = max(1, canopyOrder(frameDisplayTargets).count)
            let columnWidth: CGFloat = 260, gap: CGFloat = 12, margins: CGFloat = 36
            let gutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            let natural = CGFloat(columns)*columnWidth + CGFloat(columns-1)*gap + margins + gutter
            geometry.width = max(SwitcherGeometry.size(mode:.fold,count:0).width, natural)
        }
        if mode == .lattice {
            // A handful of live targets now trims to a handful of address cells
            // (SelectionState.latticeCells), so the panel should open close to that height
            // instead of always allocating for a full alphabet grid. This mirrors the exact
            // row/column math lattice(width:) below; an underestimate self-corrects in the
            // same present() call via the grow-to-fit block further down, so this only needs
            // to be a close approximation, not exact.
            let cells = frameLatticeCells.count
            let columns = max(1, min((cells+1)/2, Int(geometry.width/190)))
            let rows = max(1, Int((Double(cells)/Double(columns)).rounded(.up)))
            geometry.height = max(180, CGFloat(rows)*(tileHeight+10)+64)
        }
        let desiredWidth: CGFloat = min(safe.width,geometry.width)
        let defaultHeight = geometry.height
        let desiredHeight = embedded ? safe.height : min(safe.height, defaultHeight)
        let size = CGSize(width:desiredWidth,height:desiredHeight)
        let frame = embedded ? CGRect(origin:.zero,size:size) : sessionPlacement.frame(size:size,visible:safe)
        let width = frame.width, height = frame.height
        if !embedded { panel.setFrame(frame, display: false) }
        surface.frame = CGRect(origin: .zero, size: frame.size)
        content.frame = CGRect(origin: .zero, size: frame.size)
        // Destinations own the panel. Only active search or an unfinished address needs a header.
        let typingAddress = !searchMode && !state.prefix.isEmpty
        hint.isHidden = !typingAddress
        hint.frame = CGRect(x: 48, y: 15, width: width-66, height: 22)
        hint.font = .systemFont(ofSize: 12, weight: .semibold)
        hint.textColor = NSColor(tokens.selection)
        hint.stringValue = typingAddress ? String(localized: "\(state.prefix.uppercased()) · Next letter") : ""
        backButton.isHidden = !typingAddress
        backButton.frame = CGRect(x: 14, y: 12, width: 28, height: 28)
        search.isHidden = !searchMode
        search.frame = CGRect(x: 18, y: 14, width: width-36, height: 28)
        if searchMode, search.stringValue != state.query,
           opening || (search.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            search.stringValue = state.query ?? ""
        }
        var top: CGFloat = searchMode || typingAddress ? 52 : embedded ? 10 : 18
        let bottomMargin: CGFloat = embedded ? 10 : 46
        let bannerText = status
        statusBanner.isHidden = bannerText.isEmpty
        if !bannerText.isEmpty {
            statusBanner.update(bannerText, tokens: tokens)
            statusBanner.frame = CGRect(x: embedded ? 10 : 18, y: top, width: width-(embedded ? 20 : 36), height: 38)
            top += 44
        }
        scroll.frame = CGRect(x: embedded ? 10 : 18, y: top, width: width-(embedded ? 20 : 36), height: max(40,height-top-bottomMargin))
        footer.font = .systemFont(ofSize: 11)
        footer.maximumNumberOfLines = 1
        footer.stringValue = mode == .relay && !searchMode ? String(localized: "↑ ↓ Choose · ↵ Previous") : String(localized: "↑ ↓ Choose · ↵ Select")
        let footerTip = searchMode ? String(localized: "Use the arrows or Tab to move the highlight, then Return to select.") : String(localized: "Type an item's letters to select it immediately. Use the arrows or Tab to move the highlight.")
        if footer.toolTip != footerTip { footer.toolTip = footerTip }
        func placeControls(at height: CGFloat) {
            for view in [footer, searchButton, helpButton, closeButton] { view.isHidden = embedded }
            footer.frame = CGRect(x: 110, y: height-32, width: max(0,width-230), height: 18)
            // Compact previews already provide controls in Settings, outside the renderer.
            footer.isHidden = embedded || width < 390
            let searchTitle = searchMode ? String(localized: "Done") : String(localized: "Search  /")
            let searchTip = searchMode ? String(localized: "Exit search (Esc)") : String(localized: "Search windows, tabs and apps (/)")
            if searchButton.title != searchTitle { searchButton.title = searchTitle }
            if searchButton.toolTip != searchTip { searchButton.toolTip = searchTip }
            searchButton.frame = CGRect(x: 14, y: height-37, width: 86, height: 26)
            helpButton.frame = CGRect(x: width-74, y: height-37, width: 28, height: 26)
            actionsButton.isHidden = embedded || !settings.windowActionsEnabled
            actionsButton.frame = CGRect(x: width-108, y: height-37, width: 28, height: 26)
            closeButton.frame = CGRect(x: width-40, y: height-37, width: 28, height: 26)
            for button in [backButton, helpButton, closeButton, actionsButton] { button.contentTintColor = secondaryText }
        }
        placeControls(at: height)
        desiredBodyViews.removeAll(keepingCapacity: true)
        frameRules.removeAll(keepingCapacity: true)
        labelCursor = 0; imageCursor = 0
        let liveIDs = Set(state.targets.map(\.id))
        rows = rows.filter { liveIDs.contains($0.key) }
        scroll.tile()
        // Reserve the native scroller gutter before drawing; AppKit may switch
        // from overlay to legacy scrollers after the first window layout.
        let gutter = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let bodyWidth = max(100, min(scroll.contentView.bounds.width, scroll.frame.width-gutter))
        var bodyHeight: CGFloat = 0
        var wantedPlaques = Set<TargetID>()
        // Filtering narrows what each mode shows; it never swaps the mode for a plain list.
        let shown = searchMode ? frameMatches : frameDisplayTargets
        if !(searchMode && frameMatches.isEmpty) {
            switch mode {
            case .shore: bodyHeight = list(frameMatches, width: bodyWidth, state: state, icons: icons)
            case .canopy: bodyHeight = canopy(state, width: bodyWidth, icons: icons)
            case .lattice: bodyHeight = lattice(state, width: bodyWidth, icons: icons)
            case .fold: bodyHeight = fold(state, width: bodyWidth, icons: icons)
            case .relay: bodyHeight = relay(state, width: bodyWidth, icons: icons)
            case .beacons:
                let beaconsStart = CACurrentMediaTime()
                // The shared target pool also contains browser tabs and application
                // launchers. They have no desktop rectangle; label their bank sections
                // by what they are instead of reporting a failed window position.
                let tabIDs = Set(state.snapshot.tabs.map(\.id)), appIDs = Set(state.snapshot.apps.map(\.id))
                let windows = shown.filter { !tabIDs.contains($0.id) && !appIDs.contains($0.id) }
                let tabs = shown.filter { tabIDs.contains($0.id) }.map(\.id)
                let apps = shown.filter { appIDs.contains($0.id) }.map(\.id)
                let frames = Dictionary(uniqueKeysWithValues: windows.compactMap { t in cocoaBounds(t.bounds).map { (t.id, $0) } })
                var plan = BeaconPlan.make(targets: windows, frames: frames, screens: showsPlaques ? NSScreen.screens.map(\.visibleFrame) : [], reserved: frame.insetBy(dx: -8, dy: -8),plaqueHeight:rowHeight)
                let columns = max(1, Int(bodyWidth/300))
                func bankGroups(_ plan: BeaconPlan) -> [(String, [TargetID])] {
                    // Geometry reasons belong in diagnostics, not the user's destination list.
                    let bankIDs = sharedBeaconBank ? Set(windows.map(\.id)) : Set(plan.bank.map(\.id))
                    if state.ordering != .stable || state.hasSearchTerms {
                        // Preserve the shared traversal order across windows, tabs and app
                        // rows. Spatial plaques keep their positions; the bank is the same
                        // ordered sequence with those plaque targets omitted.
                        let ids = shown.filter { bankIDs.contains($0.id) || tabIDs.contains($0.id) || appIDs.contains($0.id) }.map(\.id)
                        return ids.isEmpty ? [] : [(String(localized: "Targets"), ids)]
                    }
                    return [
                        (String(localized: "Windows"), windows.filter { bankIDs.contains($0.id) }.map(\.id)),
                        (String(localized: "Browser tabs"), tabs),
                        (String(localized: "Apps"), apps),
                    ].filter { !$0.1.isEmpty }
                }
                func bankHeight(_ groups: [(String, [TargetID])]) -> CGFloat {
                    groups.isEmpty ? 65 : groups.reduce(CGFloat.zero) { total, group in
                        total + sectionHeight + CGFloat((group.1.count+columns-1)/columns)*rowStride + 10
                    }
                }
                if !embedded {
                    // The bank may grow after its sections are laid out. Remove plaques
                    // covered by that final footprint, then include those rows in the next
                    // size calculation. Every pass removes at least one plaque (at most
                    // 24 total); surviving plaques keep their original window positions.
                    while true {
                        let bankSize = CGSize(width: width, height: min(safe.height, max(height, bankHeight(bankGroups(plan))+top+bottomMargin)))
                        let bankFrame = sessionPlacement.frame(size: bankSize, visible: safe).insetBy(dx: -8, dy: -8)
                        let covered = windows.filter { target in plan.plaques[target.id].map { plaque in plaque.intersects(bankFrame) || additionalReservedFrames.contains { $0.insetBy(dx: -8, dy: -8).intersects(plaque) } } ?? false }
                        guard !covered.isEmpty else { break }
                        for target in covered {
                            plan.plaques.removeValue(forKey: target.id)
                            plan.bank.append(BankEntry(id: target.id, reason: .colliding))
                        }
                    }
                }
                Trace.log.info("perf: beacon plan \(shown.count, privacy: .public) targets, \(plan.plaques.count, privacy: .public) plaques, elapsed=\(CACurrentMediaTime()-beaconsStart, privacy: .public)")
                for target in windows {
                    guard let plaqueFrame = plan.plaques[target.id] else { continue }
                    wantedPlaques.insert(target.id)
                    let isNewPlaque = plaques[target.id] == nil
                    let plaque = plaques[target.id] ?? Self.makePanel(String(localized: "Tabnax · \(target.app)"), id: "beacon-\(target.address)")
                    plaques[target.id] = plaque; plaque.onKey = { [weak self] in _ = self?.localKey($0) }
                    // The row is the plaque's whole surface, so it carries the plaque's radius and
                    // outline; the clear wrapper only hosts it inside the transparent window.
                    let row = row(target, state: state, icons: icons, outline: content.outline, radius: 9, plaque: sharedBeaconBank)
                    let plaqueSurface = (plaque.contentView as? ThemeSurfaceView) ?? ThemeSurfaceView(contents: Canvas())
                    let wrapper = plaqueSurface.contents as! Canvas
                    if row.superview !== wrapper { wrapper.addSubview(row) }
                    row.frame = CGRect(origin: .zero, size: plaqueFrame.size)
                    plaqueSurface.frame = CGRect(origin: .zero, size: plaqueFrame.size)
                    if plaqueSurface.appearance?.name != nativeAppearance?.name { plaqueSurface.appearance = nativeAppearance }
                    let plaqueMaterial = plaqueSurface.configure(tokens: tokens, embedded: false, cornerRadius: 12)
                    wrapper.fill = NSColor(tokens.surface).withAlphaComponent(plaqueMaterial == .solid ? 1 : 0.12)
                    if plaque.appearance?.name != nativeAppearance?.name { plaque.appearance = nativeAppearance }
                    if plaque.contentView !== plaqueSurface { plaque.contentView = plaqueSurface }
                    plaque.setFrame(plaqueFrame, display: false)
                    let orderStart = CACurrentMediaTime()
                    // Ordering is a WindowServer round trip; a plaque already on screen keeps its place.
                    if !previewOnly && !plaque.isVisible { plaque.orderFront(nil) }
                    Trace.log.info("perf: plaque \(target.app, privacy: .public) new=\(isNewPlaque, privacy: .public) orderFront elapsed=\(CACurrentMediaTime()-orderStart, privacy: .public)")
                }
                Trace.log.info("perf: beacons loop done t=\(CACurrentMediaTime(), privacy: .public)")
                let groups = bankGroups(plan)
                if groups.isEmpty {
                    label(String(localized: "Choose a letter beside a window."), x: 0, y: 30, width: bodyWidth); bodyHeight = 65
                } else {
                    var y: CGFloat = 0
                    for (text, ids) in groups {
                        let idSet = Set(ids)
                        label("\(text) · \(ids.count)", x: 0, y: y, width: bodyWidth, section: true)
                        y = grid(shown.filter { idSet.contains($0.id) }, width: bodyWidth, y: y+sectionHeight, columns: columns, state: state, icons: icons, outline: cardLine) + 10
                    }
                    bodyHeight = y
                }
            }
        }
        for (id, plaque) in plaques where !wantedPlaques.contains(id) { plaque.close(); plaques[id] = nil }
        if frameDisplayTargets.isEmpty || (searchMode && frameMatches.isEmpty) {
            if searchMode {
                label(String(localized: "No matching \(targetName)."), x: 0, y: 0, width: bodyWidth); bodyHeight = 48
            } else {
                label(String(localized: "No windows or apps available."), x: 0, y: 0, width: bodyWidth)
                emptyStateRefresh.onPress = { [weak self] in self?.onRefresh?() }
                emptyStateRefresh.frame = CGRect(x: 0, y: 26, width: 90, height: 24)
                emptyStateRefresh.setAccessibilityLabel(String(localized: "Refresh windows"))
                attachToBody(emptyStateRefresh); bodyHeight = 66
            }
        }
        reconcileBodyViews()
        body.rules = frameRules
        // Fit the initial content, then retain that height while searching or moving
        // between Fold families. Fewer results should not move the panel under the pointer.
        let requiredHeight = min(safe.height, max(140, sessionHeight, bodyHeight+top+bottomMargin))
        if !embedded { sessionHeight = requiredHeight }
        if !embedded && requiredHeight != height {
            let grownFrame = sessionPlacement.frame(size: CGSize(width: width, height: requiredHeight), visible: safe)
            panel.setFrame(grownFrame, display: false)
            surface.frame = CGRect(origin: .zero, size: grownFrame.size)
            content.frame = CGRect(origin: .zero, size: grownFrame.size)
            let grownHeight = grownFrame.height
            placeControls(at: grownHeight)
            scroll.frame = CGRect(x: 18, y: top, width: width-36, height: max(40,grownHeight-top-bottomMargin))
        }
        body.frame = CGRect(x: 0, y: 0, width: bodyWidth, height: max(bodyHeight, scroll.contentSize.height))
        // The key hints sit below a rule, apart from the targets above them.
        content.rules = embedded ? [] : [(CGRect(x: 0, y: content.frame.height-46, width: content.frame.width, height: 1), hairline)]
        if !embedded, shadowSize != panel.frame.size { shadowSize = panel.frame.size; panel.invalidateShadow() }
        if opening && !previewOnly { if ownsInput { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }; Trace.signposter.emitEvent("panelCommit"); Trace.log.info("perf: panelCommit session=\(state.session, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)") }
        if ownsInput && !previewOnly && searchMode && (!previouslySearching || opening) { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(search) }
        if ownsInput && !embedded && !previewOnly && !searchMode && (opening || previouslySearching) { panel.makeFirstResponder(panel) }
        previouslySearching = searchMode
        if !embedded { onSurfaces?([panel.frame] + plaques.values.filter(\.isVisible).map(\.frame)) }
        if cursorMoved, let highlight = frameHighlight {
            // Branches (Fold apps and Lattice overflow) are keyboard destinations too.
            let selected: NSView?
            switch highlight {
            case .target(let id): selected = rows[id]
            case .branch(let code): selected = state.mode == .fold ? familyButtons[code] : branchTiles[code]
            }
            if let selected, selected.superview === body { body.scrollToVisible(selected.frame) }
        }
        if opening && !embedded && !previewOnly {
            // Ordering is not drawing. In particular, after a long hidden interval AppKit
            // still owes us layout/backing-store work. Submit it before the caller queues
            // catalogue refreshes, whose main-queue callbacks can overtake deferred drawing.
            // Include the final scroll position and any Beacons panels in the first frame.
            let started = CACurrentMediaTime()
            for window in [panel] + plaques.values.filter(\.isVisible) + desktopSpotlight.panels.filter(\.isVisible) {
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
            }
            CATransaction.flush()
            Trace.signposter.emitEvent("firstFrameSubmitted", "session=\(state.session, privacy: .public)")
            // Submission is not proof that WindowServer has displayed the pixels.
            Trace.log.info("perf: firstFrameSubmitted session=\(state.session, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public) drawing=\(CACurrentMediaTime()-started, privacy: .public)")
        }
        // VoiceOver users get no visual redraw cue for these, so announce them explicitly
        // instead of relying on incidental focus-change announcements.
        if ownsInput && !previewOnly {
            if opening {
                announce(String(localized: "Tabnax \(mode.title) switcher, \(frameDisplayTargets.count) targets"))
            } else if previousMode != nil && previousMode != state.mode {
                announce(String(localized: "\(mode.title) mode"))
            } else if previousStatus != status && !status.isEmpty {
                announce(status)
            }
        }
        needsFullPresent = false
        if opening {
            Trace.signposter.emitEvent("presentationPrepared")
            Trace.log.info("perf: presentationPrepared session=\(state.session, privacy: .public) t=\(CACurrentMediaTime(), privacy: .public)")
        }
    }
    private func announce(_ message: String) {
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                              userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func focusSearch(session: UInt64) {
        guard lastState.session == session, lastState.active, lastState.query != nil, ownsInput, !peerMenuTracking, !trackingMenu else { return }
        panel.makeKeyAndOrderFront(nil)
        // Do not select all or discard marked text on repeated search invocation.
        if search.currentEditor() == nil { panel.makeFirstResponder(search) }
    }
    func deliverSearchInput(_ event: CGEvent, session: UInt64) {
        guard lastState.session == session, lastState.active, lastState.query != nil, ownsInput, !peerMenuTracking, !trackingMenu,
              let native = NSEvent(cgEvent: event) else { return }
        focusSearch(session: session)
        search.currentEditor()?.keyDown(with: native)
    }
    func restoreSearchInputAfterPreview() {
        guard ownsInput, lastState.active, lastState.query != nil, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        if search.currentEditor() == nil { panel.makeFirstResponder(search) }
    }
    private func cocoaBounds(_ bounds: CGRect?) -> CGRect? {
        guard let bounds, bounds.width.isFinite, bounds.height.isFinite, bounds.minX.isFinite, bounds.minY.isFinite else { return nil }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: bounds.minX, y: primaryTop-bounds.maxY, width: bounds.width, height: bounds.height)
    }
    /// `outline` turns the row into a card: a bordered surface for rows that stand on their own
    /// (tiles, shelves, plaques) rather than reading as lines of one list.
    private func row(_ target: Target, state: SelectionState, icons: [UUID: NSImage], addressOverride: String? = nil, outline: NSColor? = nil, radius: CGFloat = 7, tile: Bool = false, plaque: Bool = false) -> TargetRow {
        let row = (plaque ? plaqueRows[target.id] : rows[target.id]) ?? TargetRow()
        if plaque { plaqueRows[target.id] = row } else { rows[target.id] = row }
        row.onPress = { [weak self] in
            guard let self, !peerMenuTracking, !trackingMenu, lastState.active, lastState.session == state.session else { return }
            onChoose?(target.id,state.session)
        }
        row.onHover = { [weak self] in self?.hover(.target(target.id), session: state.session) }
        row.navigationAction = .target(target.id)
        row.style = settings.appearance
        row.compact = embedded; row.tile = tile
        row.grouped = state.mode == .canopy || state.mode == .fold
        // The letters already typed fade on every address they lead to, leaving what is still
        // to press. Fold's child rows show only that remainder, so they have nothing to fade.
        let typed = addressOverride == nil && state.query == nil && target.address.hasPrefix(state.prefix) ? state.prefix.count : 0
        row.bind(target, image: icons[target.id.process], matches: frameMatchIDs.contains(target.id),
                 selected: frameHighlight == .target(target.id), tokens: tokens, addressOverride: addressOverride,
                 typed: typed, current: target.id == state.focusHistory.current, outline: outline, radius: radius,
                 containsMinimizedWindows: target.id.window == nil && frameMinimizedOwners.contains(target.groupOwner))
        return row
    }
    /// `section` is the quiet, letter-spaced caption that names a group of rows; plain labels
    /// stay at reading size for messages and app names.
    @discardableResult private func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, section: Bool = false) -> NSTextField {
        let label: NSTextField
        if labelCursor < labelPool.count { label = labelPool[labelCursor] } else { label = NSTextField(wrappingLabelWithString: ""); labelPool.append(label) }
        labelCursor += 1
        label.alphaValue = 1
        if section {
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            label.font = NSFont.monospacedSystemFont(ofSize: 10 * settings.appearance.scale.factor, weight: .medium)
            label.attributedStringValue = NSAttributedString(string: text.localizedUppercase, attributes: [
                .font: label.font as Any,
                .foregroundColor: NSColor(contrast ? tokens.text : tokens.secondary), .kern: 1.1])
            // VoiceOver reads the caption as written, not as a run of capitals.
            label.setAccessibilityLabel(text)
        } else {
            label.stringValue = text; label.font = .systemFont(ofSize: 12 * settings.appearance.scale.factor, weight: .medium); label.textColor = NSColor(tokens.text)
            label.setAccessibilityLabel(nil)
        }
        label.frame = CGRect(x: x, y: y, width: width, height: sectionHeight); attachToBody(label); return label
    }
    private func list(_ targets: [Target], width: CGFloat, state: SelectionState, icons: [UUID: NSImage]) -> CGFloat {
        grid(targets, width: width, y: 0, columns: 1, state: state, icons: icons)
    }
    private func grid(_ targets: [Target], width: CGFloat, y: CGFloat, columns: Int, state: SelectionState, icons: [UUID: NSImage], outline: NSColor? = nil) -> CGFloat {
        let gap: CGFloat = 8, cellWidth = (width - CGFloat(columns-1)*gap)/CGFloat(columns)
        for (i, target) in targets.enumerated() {
            let row = row(target, state: state, icons: icons, outline: outline); attachToBody(row)
            row.frame = CGRect(x: CGFloat(i%columns)*(cellWidth+gap), y: y+CGFloat(i/columns)*rowStride, width: cellWidth, height: rowHeight)
        }
        return y + CGFloat((targets.count+columns-1)/columns)*rowStride
    }
    private func canopyGroupKey(_ target: Target) -> UUID { target.groupOwner }
    private func canopyOrder(_ matches: [Target]) -> [Target] {
        var seen = Set<UUID>()
        return matches.filter { seen.insert(canopyGroupKey($0)).inserted }
    }
    private func canopy(_ state: SelectionState, width: CGFloat, icons: [UUID: NSImage]) -> CGFloat {
        // Grouped and ordered off the full target set so a letter-prefix narrows via
        // per-row dimming (see TargetRow.bind's `matches` alpha) rather than dropping
        // tiles and reflowing the grid underneath the user.
        // A search drops the apps and windows that don't match, but columns keep the width
        // they had before filtering.
        let shown = state.query != nil ? frameMatches : frameDisplayTargets
        let groups = Dictionary(grouping: shown, by: canopyGroupKey)
        let order = canopyOrder(state.query != nil ? frameMatches : frameDisplayTargets).filter { groups[canopyGroupKey($0)] != nil }
        let matchedGroups = Set(frameMatches.map(canopyGroupKey))
        let columns = max(1, min(canopyOrder(frameDisplayTargets).count, Int(width/260))), w = (width-CGFloat(columns-1)*12)/CGFloat(columns)
        let iconSize: CGFloat = (embedded ? 32 : 36) + (settings.appearance.scale.factor-1)*12
        let header = max(iconSize+8,sectionHeight+8)
        var y: CGFloat = 0
        for start in stride(from: 0, to: order.count, by: columns) {
            let chunk = Array(order[start..<min(start+columns, order.count)])
            var maxHeight: CGFloat = 0
            for (column, app) in chunk.enumerated() {
                let x = CGFloat(column)*(w+12), children = groups[canopyGroupKey(app)] ?? []
                let iconX: CGFloat = embedded ? 4 : 7
                let image: NSImageView
                if imageCursor < imagePool.count { image = imagePool[imageCursor] } else { image = NSImageView(); imagePool.append(image) }
                imageCursor += 1
                image.frame = CGRect(x:x+iconX,y:y,width:iconSize,height:iconSize)
                let appImage = icons[app.groupOwner] ?? Self.placeholderIcon
                if image.image !== appImage { image.image = appImage }
                image.imageScaling = .scaleProportionallyUpOrDown; attachToBody(image)
                let groupMatches = matchedGroups.contains(canopyGroupKey(app))
                image.alphaValue = groupMatches ? 1 : 0.4
                let textX = iconX+iconSize+6
                let countText = String(children.count)
                let countFont = NSFont.monospacedDigitSystemFont(ofSize: 11 * settings.appearance.scale.factor, weight: .medium)
                let countWidth = ceil((countText as NSString).size(withAttributes: [.font: countFont]).width)+2
                let count = label(countText, x:x+w-countWidth-10, y:y, width:countWidth)
                count.font = countFont
                count.textColor = NSColor(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? tokens.text : tokens.secondary)
                count.alphaValue = groupMatches ? 1 : 0.4
                count.setAccessibilityLabel(children.count == 1 ? String(localized: "1 target") : String(localized: "\(children.count) targets"))
                let countHeight = ceil(count.intrinsicContentSize.height)
                count.frame.origin.y = y+(iconSize-countHeight)/2; count.frame.size.height = countHeight
                let nameWidth = max(20,w-textX-countWidth-24)
                let name = label(app.app,x:x+textX,y:y,width:nameWidth)
                name.alphaValue = groupMatches ? 1 : 0.4
                let nameHeight = ceil(name.intrinsicContentSize.height)
                name.frame = CGRect(x:x+textX,y:y+(iconSize-nameHeight)/2,width:nameWidth,height:nameHeight)
                // A quiet rule makes the app heading readable across glass and solid surfaces.
                frameRules.append((CGRect(x:x+7,y:y+header-3,width:max(0,w-14),height:1),hairline))
                for (i, target) in children.enumerated() {
                    let row = row(target, state: state, icons: icons); attachToBody(row)
                    row.frame = CGRect(x: x, y: y+header+CGFloat(i)*rowStride, width: w, height: rowHeight)
                }
                maxHeight = max(maxHeight, header+CGFloat(children.count)*rowStride)
            }
            // Each app is a column of its own; a rule in the gutter keeps neighbours apart.
            for column in chunk.indices.dropFirst() {
                frameRules.append((CGRect(x: CGFloat(column)*(w+12)-6, y: y, width: 1, height: maxHeight), hairline))
            }
            y += maxHeight+16
        }
        return y
    }
    private func lattice(_ state: SelectionState, width: CGFloat, icons: [UUID: NSImage]) -> CGFloat {
        let cells = frameLatticeCells
        let columns = max(1, min((cells.count+1)/2, Int(width/190))), w = (width-CGFloat(columns-1)*10)/CGFloat(columns)
        if state.query != nil {
            // Search results stay on the same tile grid instead of collapsing into a list.
            for (i, target) in frameMatches.enumerated() {
                let row = row(target, state: state, icons: icons, outline: cardLine, radius: 9, tile: true); attachToBody(row)
                row.frame = CGRect(x: CGFloat(i%columns)*(w+10), y: CGFloat(i/columns)*(tileHeight+10), width: w, height: tileHeight)
            }
            return CGFloat((frameMatches.count+columns-1)/columns)*(tileHeight+10)
        }
        func detail(for cell: AddressCell) -> String {
            guard !cell.descendants.isEmpty else {
                return cell.held ? String(localized: "Reserved letter") : String(localized: "Unused")
            }
            let names = cell.descendants.prefix(2).map(\.title).joined(separator: " · ")
            return String(localized: "Open group · \(cell.descendants.count) items\n\(names)")
        }
        var y: CGFloat = 0
        for start in stride(from: 0, to: cells.count, by: columns) {
            let rowCells = Array(cells[start..<min(start+columns, cells.count)])
            let rowHeight = tileHeight
            for (offset, cell) in rowCells.enumerated() {
                let rect = CGRect(x: CGFloat(offset)*(w+10), y: y, width: w, height: rowHeight)
                // A closed assigned app's cell falls through to the held-slot branch below:
                // its letter still launches it, but no tile names it until it's running.
                if let target = cell.target, target.isRunning {
                    let row = row(target, state: state, icons: icons, outline: cardLine, radius: 9, tile: true); attachToBody(row); row.frame = rect
                } else {
                    let detail = detail(for: cell)
                    let button = branchTiles[cell.address] ?? BranchTile(address: cell.address.uppercased(), detail: detail) { [weak self] in self?.onKey?(.prefix(cell.address),state.session) }
                    branchTiles[cell.address] = button
                    button.update(address: cell.address.uppercased(), detail: detail) { [weak self] in self?.onKey?(.prefix(cell.address),state.session) }
                    button.onHover = { [weak self] in self?.hover(.branch(cell.address), session: state.session) }
                    button.applyStyle(tokens,outline:cardLine,scale:settings.appearance.scale.factor,strong:settings.appearance.strongOutlines || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
                    button.navigationAction = .branch(cell.address)
                    button.isEnabled = cell.descendants.contains(where: \.available); button.alphaValue = button.isEnabled ? 1 : 0.4; button.frame = rect
                    if frameHighlight == .branch(cell.address) { button.highlight(tokens) }
                    let help = cell.descendants.isEmpty ? nil : String(localized: "Press Return to open this group. Backspace returns to the previous level.")
                    if button.accessibilityHelp() != help { button.setAccessibilityHelp(help) }
                    let inventory = cell.descendants.map { $0.address.uppercased() + "  " + $0.title }.joined(separator: "\n")
                    let tip = inventory.isEmpty ? detail : inventory
                    if button.toolTip != tip { button.toolTip = tip }
                    let spoken = cell.address.uppercased() + ", " + detail + (inventory.isEmpty ? "" : "\n" + inventory)
                    if button.accessibilityLabel() != spoken { button.setAccessibilityLabel(spoken) }
                    if button.accessibilityIdentifier() != "cell-\(cell.address)" { button.setAccessibilityIdentifier("cell-\(cell.address)") }
                    attachToBody(button)
                }
            }
            y += rowHeight + 10
        }
        branchTiles = branchTiles.filter { key, _ in cells.contains { $0.target == nil && $0.address == key } }
        return grid(frameMatches.filter { $0.address.isEmpty },width:width,y:y,columns:columns,state:state,icons:icons,outline:cardLine)
    }
    private func fold(_ state: SelectionState, width: CGFloat, icons: [UUID: NSImage]) -> CGFloat {
        // While searching, the spine lists only apps with a result and the right side follows
        // the highlighted result's app.
        let searching = state.query != nil
        // A closed assigned app has no window to fold into, so its family button never
        // draws either — same rule as its missing column in Canopy.
        let foldFamilies = state.foldFamilies.filter(\.isRunning)
        let spine = min(240, width*0.36)
        let families: [Target]
        if searching {
            var seen = Set<UUID>()
            let owners = frameMatches.map(\.groupOwner).filter { seen.insert($0).inserted }
            families = owners.compactMap { owner in foldFamilies.first { $0.id.process == owner } }
        } else { families = foldFamilies }
        let highlightedOwner: UUID? = { if case .target(let id)? = frameHighlight { return frameMatches.first { $0.id == id }?.groupOwner }; return nil }()
        // Preview the right panel from whatever's highlighted (hover or Tab cursor), not
        // just a committed prefix, so windows appear as soon as an app is highlighted.
        let previewCode: String? = state.foldFamily?.foldAddress ?? {
            if case .branch(let code)? = frameHighlight { return code }
            return nil
        }()
        let family = searching ? families.first { $0.id.process == highlightedOwner } : families.first { $0.foldAddress == previewCode }
        let familyTargets = Dictionary(grouping: searching ? frameMatches : state.targets, by: \.groupOwner)
        let availableOwners = Set(familyTargets.compactMap { owner, targets in targets.contains(where: \.available) ? owner : nil })
        let scale = settings.appearance.scale.factor, familyWidth = spine-12
        let compactPane = width < 520
        let headingHeight: CGFloat = compactPane ? 26 : sectionHeight
        // The pointer region still uses the original spine width. A narrow spine changes
        // its internal arrangement instead of squeezing three overlapping columns into it.
        let stackedFamily = familyWidth < (40*scale-16)+max(28,14+9*scale)+48*scale+32
        let familyNameSize = stackedFamily ? min(13*scale,14) : 13*scale
        let familyHeight = stackedFamily ? max(68,14*scale+10+familyNameSize+24) : 40*scale
        let familyStride = familyHeight+8
        func heading(_ text: String, x: CGFloat, width: CGFloat) {
            let field = label(text, x: x, y: 0, width: width, section: true)
            guard compactPane else { return }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            field.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
            field.attributedStringValue = NSAttributedString(string: text.localizedUppercase, attributes: [
                .font: field.font as Any,
                .foregroundColor: NSColor(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? tokens.text : tokens.secondary),
                .kern: 0.7, .paragraphStyle: paragraph])
            field.frame.size.height = headingHeight
        }
        heading(String(localized: "Apps"), x: 0, width: spine-8)
        for (i, app) in families.enumerated() {
            let button = familyButtons[app.foldAddress] ?? {
                let button = ActionButton("") {}
                button.setButtonType(.momentaryPushIn); button.isBordered = false; button.wantsLayer = true
                button.layer?.cornerRadius = 8
                return button
            }()
            familyButtons[app.foldAddress] = button
            button.onPress = { [weak self] in self?.onKey?(.prefix(app.foldAddress),state.session) }
            button.onHover = { [weak self] in self?.hover(.branch(app.foldAddress), session: state.session) }
            button.navigationAction = .branch(app.foldAddress)
            if searching {
                let first = frameMatches.first { $0.groupOwner == app.id.process && $0.available }
                button.navigationAction = first.map { .target($0.id) }
                button.onPress = nil; button.onHover = nil
                if let first {
                    // The app spine navigates results without leaving the search field.
                    button.onPress = { [weak self] in self?.onKey?(.highlight(.target(first.id)),state.session) }
                    button.onHover = { [weak self] in
                        guard let self, highlightedOwner != app.id.process else { return }
                        hover(.target(first.id), session: state.session)
                    }
                }
            }
            let buttonFont = NSFont.systemFont(ofSize:13*settings.appearance.scale.factor)
            if button.font != buttonFont { button.font = buttonFont }
            button.frame = CGRect(x: 0, y: headingHeight+CGFloat(i)*familyStride, width: familyWidth, height: familyHeight)
            let focused = frameHighlight == .branch(app.foldAddress)
            let selected = app.id == family?.id || focused
            button.layer?.backgroundColor = (selected ? NSColor(tokens.selection.mixed(with:tokens.surface,amount:focused ? 0.88 : 0.94)) : themeRowFill(tokens, card: false)).cgColor
            // Keep the containing app visible while the child owns the stronger focus ring.
            let strong = settings.appearance.strongOutlines || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            button.layer?.borderColor = (focused ? NSColor(tokens.selection) : cardLine).cgColor
            button.layer?.borderWidth = strong ? 2 : selected ? 1 : 0
            button.isEnabled = (searching || !app.foldAddress.isEmpty) && availableOwners.contains(app.id.process)
            let itemCount = familyTargets[app.id.process]?.count ?? 0
            let hasMinimized = frameMinimizedOwners.contains(app.id.process)
            let minimizedContext = hasMinimized ? String(localized: "Contains minimized windows") : ""
            // Accessibility registration and tooltips are costly to rewrite; most frames only
            // move the highlight, so these change only when their text does.
            let spoken = String(localized: "\(app.foldAddress.uppercased()), \(app.app), \(itemCount) items") + (hasMinimized ? ", " + minimizedContext : "")
            let value = selected ? String(localized: "Selected") : ""
            button.setAccessibilityRole(.button)
            if button.accessibilityLabel() != spoken { button.setAccessibilityLabel(spoken) }
            if button.accessibilityValue() as? String != value { button.setAccessibilityValue(value) }
            if button.accessibilityIdentifier() != "family-\(app.foldAddress)" { button.setAccessibilityIdentifier("family-\(app.foldAddress)") }
            let tip = hasMinimized ? minimizedContext : nil
            if button.toolTip != tip { button.toolTip = tip }
            attachToBody(button)
            let iconSize = stackedFamily ? min(28,max(20,familyWidth*0.3)) : familyHeight-16
            let icon = familyIcons[app.foldAddress] ?? NSImageView()
            familyIcons[app.foldAddress] = icon
            let iconImage = icons[app.id.process] ?? Self.placeholderIcon
            if icon.image !== iconImage { icon.image = iconImage }
            icon.imageScaling = .scaleProportionallyUpOrDown
            // Re-adding an attached subview detaches and reattaches it; only add it once.
            if icon.superview !== button { button.addSubview(icon) }
            let address = familyAddresses[app.foldAddress] ?? makeKeyCapField()
            familyAddresses[app.foldAddress] = address
            address.stringValue = app.foldAddress.uppercased()
            let preferredKeySize = 14*scale
            let preferredKeyFont = keyCapFont(size: preferredKeySize)
            let preferredKeyWidth = ceil((address.stringValue as NSString).size(withAttributes: [.font: preferredKeyFont]).width)+14
            let keyWidth = min(familyWidth-16,max(28,preferredKeyWidth))
            let keyFontSize = preferredKeySize*min(1,max(1,keyWidth-14)/max(1,preferredKeyWidth-14))
            let keyHeight = keyFontSize+10
            address.font = keyCapFont(size: keyFontSize)
            styleKeyCap(address, tokens: tokens, strong: strong)
            address.frame = CGRect(x: familyWidth-8-keyWidth, y: stackedFamily ? familyHeight-8-keyHeight : (familyHeight-keyHeight)/2, width: keyWidth, height: keyHeight)
            icon.isHidden = stackedFamily && iconSize+keyWidth+22 > familyWidth
            icon.frame = CGRect(x: 8, y: stackedFamily ? familyHeight-8-max(iconSize,keyHeight)+(max(iconSize,keyHeight)-iconSize)/2 : (familyHeight-iconSize)/2, width: iconSize, height: iconSize)
            let badge = familyMinimizedBadges[app.foldAddress] ?? MinimizedBadge()
            familyMinimizedBadges[app.foldAddress] = badge
            badge.isHidden = !hasMinimized; badge.apply(tokens, strong: strong)
            badge.frame = CGRect(x: icon.isHidden ? 8 : icon.frame.maxX-12,
                                 y: icon.isHidden ? (button.isFlipped ? 8 : familyHeight-22)
                                    : (button.isFlipped ? icon.frame.maxY-12 : icon.frame.minY), width: 12, height: 12)
            if badge.superview !== button { button.addSubview(badge) }
            if address.superview !== button { button.addSubview(address) }
            let textX = 8+iconSize+8
            let name = familyLabels[app.foldAddress] ?? NSTextField(labelWithString: "")
            familyLabels[app.foldAddress] = name
            name.stringValue = app.app
            name.font = .systemFont(ofSize:familyNameSize)
            name.textColor = NSColor(tokens.text)
            name.lineBreakMode = .byTruncatingTail
            // A label drawn into the full button height hugs the top edge; size it to its text.
            let nameHeight = ceil(name.intrinsicContentSize.height)
            name.frame = stackedFamily
                ? CGRect(x: 8, y: 8, width: max(1,familyWidth-16), height: nameHeight)
                : CGRect(x: textX, y: (familyHeight-nameHeight)/2, width: max(20,familyWidth-textX-8-keyWidth-8), height: nameHeight)
            if name.superview !== button { button.addSubview(name) }
        }
        let liveFamilies = Set(families.map(\.foldAddress))
        familyButtons = familyButtons.filter { liveFamilies.contains($0.key) }
        familyIcons = familyIcons.filter { liveFamilies.contains($0.key) }
        familyMinimizedBadges = familyMinimizedBadges.filter { liveFamilies.contains($0.key) }
        familyLabels = familyLabels.filter { liveFamilies.contains($0.key) }
        familyAddresses = familyAddresses.filter { liveFamilies.contains($0.key) }
        guard let family else {
            heading(String(localized: "Windows & tabs"), x: spine+8, width: width-spine-8)
            let message = label(String(localized: "Choose an app to see its windows and tabs."), x: spine+8, y: headingHeight, width: width-spine-8)
            message.frame.size.height = 110 * settings.appearance.scale.factor
            let height = max(message.frame.maxY, headingHeight+CGFloat(families.count)*familyStride)
            frameRules.append((CGRect(x: spine-2, y: 0, width: 1, height: max(height, scroll.contentSize.height)), hairline))
            return height
        }
        let children = (searching ? frameMatches : state.targets).filter { $0.groupOwner == family.id.process }
        let childHeading = family.app
        heading(childHeading, x: spine+8, width: width-spine-8)
        let compact = width-spine-8 < 300, childHeight = compact ? tileHeight : rowHeight
        for (i, target) in children.enumerated() {
            // SelectionState also assumes the highlighted app's head at the root, so child
            // suffixes are actionable before explicit entry. Search displays stable full
            // identities instead: letters enter text there and Return selects the result.
            let suffix = target.address.hasPrefix(family.foldAddress) ? String(target.address.dropFirst(family.foldAddress.count)) : target.address
            let addressOverride = !searching && !suffix.isEmpty ? suffix : nil
            let row = row(target, state: state, icons: icons, addressOverride: addressOverride, outline: cardLine, radius: 8, tile: compact); attachToBody(row)
            row.frame = CGRect(x: spine+8, y: headingHeight+CGFloat(i)*(childHeight+8), width: width-spine-8, height: childHeight)
        }
        let height = headingHeight+max(CGFloat(families.count)*familyStride, CGFloat(children.count)*(childHeight+8))
        // The spine and the open app's windows are two panes; a rule between them says so.
        frameRules.append((CGRect(x: spine-2, y: 0, width: 1, height: max(height, scroll.contentSize.height)), hairline))
        return height
    }
    private func relay(_ state: SelectionState, width: CGFloat, icons: [UUID: NSImage]) -> CGFloat {
        let searching = state.query != nil, shown = searching ? frameMatches : frameDisplayTargets
        if searching {
            return grid(shown, width: width, y: 0, columns: max(1, Int(width/330)), state: state, icons: icons, outline: cardLine)
        }
        let current = shown.first { $0.id == state.focusHistory.current }
        let previous = state.returnTarget.flatMap { target in shown.first { $0.id == target.id } }
        // In compact previews each half-width card loses most of its title. Stack the pair
        // as full-width rows there, keeping the same current → previous navigation order.
        let stacked = width < 520 * settings.appearance.scale.factor
        let w = stacked ? width : (width-14)/2
        let pairHeight = stacked ? rowHeight : tileHeight
        let pairStride = sectionHeight+pairHeight+14
        // Enter's destination is the one card worth finding first, so it wears the accent.
        let returnLine = NSColor(tokens.surface.mixed(with:tokens.selection,amount:0.55))
        let pair: [Target?] = state.ordering == .stable ? [current, previous] : shown.prefix(2).map { Optional($0) }
        for (index, target) in pair.enumerated() {
            let x = stacked ? 0 : CGFloat(index)*(w+14)
            let y = stacked ? CGFloat(index)*pairStride : 0
            let caption: String
            if state.ordering == .stable {
                caption = index == 0 ? String(localized: "Current window") :
                    previous == nil ? String(localized: "Return unavailable") : String(localized: "Previous · ↵")
            } else {
                caption = target?.id == current?.id ? String(localized: "Current window") :
                    target?.id == previous?.id ? String(localized: "Previous · ↵") : state.ordering.title
            }
            label(caption, x: x, y: y, width: w, section: true)
            let cardFrame = CGRect(x: x, y: y+sectionHeight, width: w, height: pairHeight)
            if let target {
                let row = row(target, state: state, icons: icons, outline: target.id == previous?.id ? returnLine : cardLine, radius: 10, tile: !stacked); attachToBody(row)
                row.frame = cardFrame
            } else {
                let placeholder = Canvas(frame: cardFrame)
                placeholder.fill = themeRowFill(tokens, card: true); placeholder.cornerRadius = 10; placeholder.outline = cardLine
                placeholder.outlineWidth = settings.appearance.strongOutlines || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1
                attachToBody(placeholder)
                let message = searching ? String(localized: "Not in search results") :
                    index == 0 ? String(localized: "No current window") : String(localized: "No previous window yet.")
                let note = label(message, x: x+12, y: cardFrame.minY+max(8,(pairHeight-sectionHeight)/2), width: w-24)
                note.textColor = NSColor(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? tokens.text : tokens.secondary)
                note.frame.size.height = min(sectionHeight, pairHeight-16)
            }
        }
        let pairBottom = (stacked ? pairStride : 0)+sectionHeight+pairHeight
        let pairIDs = Set(pair.compactMap { $0?.id })
        let rest = shown.filter { !pairIDs.contains($0.id) }
        guard !rest.isEmpty else { return pairBottom }
        let shelf = pairBottom+18
        label(String(localized: "More · \(rest.count)"), x: 0, y: shelf, width: width, section: true)
        return grid(rest, width: width, y: shelf+sectionHeight, columns: max(1, Int(width/330)), state: state, icons: icons, outline: cardLine)
    }
    func dismiss() {
        actionStatus = nil; pendingMenuAction = nil
        menuGeneration &+= 1
        activeMenu?.cancelTracking()
        if trackingMenu { endMenu(session: lastState.session) }
        desktopSpotlight.dismiss()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        lastState.cancel()
        onSurfaces?([]); wheel.reset(); shownMode = nil
        panel.close(); plaques.values.forEach { $0.close() }; plaques.removeAll(); plaqueRows.removeAll(); previouslySearching = false; sessionHeight = 0
    }
    @discardableResult func showActionOutcome(_ message: String, action: SwitcherAction, target: TargetID) -> Bool {
        guard lastState.active, let pending = pendingMenuAction, pending.session == lastState.session,
              pending.action == action, pending.target == target else { return false }
        actionStatus = (lastState.session, message)
        present(lastState, icons: lastIcons, status: message)
        return true
    }
    func savePreview(to path: String) throws {
        // Render only our own views, including Beacons plaques; no display capture.
        let visible = [panel] + plaques.values.sorted { $0.frame.minX < $1.frame.minX }
        let bounds = visible.reduce(panel.frame) { $0.union($1.frame) }
        let rendered = visible.compactMap { window -> (CGRect, NSBitmapImageRep)? in
            guard let view = window.contentView else { return nil }; view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            withThemeSnapshotFallback(in: view) { view.cacheDisplay(in: view.bounds, to: bitmap) }
            return (window.frame, bitmap)
        }
        if rendered.count == 1, let png = rendered[0].1.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: path)); return
        }
        let image = NSImage(size: bounds.size); image.lockFocus()
        for (frame, bitmap) in rendered {
            bitmap.draw(in: CGRect(x: frame.minX-bounds.minX, y: frame.minY-bounds.minY, width: frame.width, height: frame.height))
        }
        image.unlockFocus()
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

// NSTextField's default cell only centers a single line of text horizontally;
// with a frame taller than the font's own line height (as the key-cap badges
// need, for hit-target/visual padding) the glyphs drift toward the top-left.
// This cell recenters the title rect vertically within whatever frame it's given.
private final class VerticallyCenteredKeyCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let size = cellSize(forBounds: rect)
        var titleRect = rect
        titleRect.origin.y = rect.origin.y + (rect.height - size.height) / 2
        titleRect.size.height = size.height
        return titleRect
    }
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
private func keyCapFont(size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
    .monospacedSystemFont(ofSize: size, weight: weight)
}
/// The cap's colour lives on its layer, not in the cell: a cell-drawn background is a square
/// the layer's corner radius can only clip, and own-view renders do not apply that clip.
@MainActor private func styleKeyCap(_ field: NSTextField, tokens: ThemeTokens, strong: Bool) {
    field.textColor = NSColor(tokens.keyText); field.drawsBackground = false
    field.wantsLayer = true; field.layer?.cornerRadius = 5; field.layer?.cornerCurve = .continuous
    field.layer?.backgroundColor = NSColor(tokens.key).cgColor
    field.layer?.borderWidth = strong ? 2 : 0.5
    field.layer?.borderColor = NSColor(tokens.keyText).withAlphaComponent(strong ? 1 : 0.25).cgColor
}
@MainActor private func makeKeyCapField() -> NSTextField {
    let field = NSTextField(labelWithString: "")
    let cell = VerticallyCenteredKeyCell()
    cell.isEditable = false; cell.isSelectable = false; cell.isBezeled = false; cell.isBordered = false
    cell.usesSingleLineMode = true; cell.lineBreakMode = .byClipping; cell.alignment = .center
    field.cell = cell
    return field
}
/// A quiet Dock-style minus, drawn rather than relying on colour or dimming the
/// whole icon. The parent row/group speaks the state; the badge is decorative.
private final class MinimizedBadge: NSView {
    private var fill = NSColor.windowBackgroundColor, ink = NSColor.secondaryLabelColor
    private var strong = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = .init("minimized-indicator"); setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func apply(_ tokens: ThemeTokens, strong: Bool) {
        self.strong = strong
        fill = NSColor(tokens.surface); ink = NSColor(strong ? tokens.text : tokens.secondary)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
        fill.setFill(); circle.fill()
        ink.withAlphaComponent(strong ? 1 : 0.65).setStroke()
        circle.lineWidth = strong ? 1.5 : 0.75; circle.stroke()
        let minus = NSBezierPath(); minus.lineWidth = strong ? 2 : 1.5; minus.lineCapStyle = .round
        minus.move(to: NSPoint(x: bounds.width*0.3, y: bounds.midY))
        minus.line(to: NSPoint(x: bounds.width*0.7, y: bounds.midY))
        ink.setStroke(); minus.stroke()
    }
}

private final class TargetRow: SessionButton {
    override var isFlipped: Bool { false }
    private let icon = NSImageView(), heading = NSTextField(labelWithString: ""), detail = NSTextField(labelWithString: ""), address = makeKeyCapField()
    // A corner badge on the icon, not just detail text, so "will launch" reads at a
    // glance instead of requiring the secondary label to be read.
    private let launchBadge = NSImageView()
    private let minimizedBadge = MinimizedBadge()
    /// Marks the window that had focus when the switcher opened.
    private let currentDot = NSView()
    var style = AppearancePreferences()
    var tile = false { didSet { if tile != oldValue { needsLayout = true } } }
    var compact = false { didSet { if compact != oldValue { needsLayout = true } } }
    var grouped = false
    private struct Binding: Equatable {
        var target: Target
        var image: ObjectIdentifier?
        var matches: Bool
        var selected: Bool
        var tokens: ThemeTokens
        var addressOverride: String?
        var typed: Int
        var current: Bool
        var outline: NSColor?
        var radius: CGFloat
        var style: AppearancePreferences
        var compact: Bool
        var grouped: Bool
        var contrast: Bool
        var reduceTransparency: Bool
        var containsMinimizedWindows: Bool
    }
    private var binding: Binding?
    private var boundFonts: (compact: Bool, scale: Double)?
    private var boundToolTip: String?, boundSpoken: String?, boundAddress: String?, boundSelected: Bool?
    private var showsPlaceholder = false, boundTyped = false, isCurrent = false
    override init(frame: NSRect) {
        super.init(frame: frame); title = ""; isBordered = false; wantsLayer = true; layer?.cornerRadius = 7; layer?.cornerCurve = .continuous
        target = self; action = #selector(press)
        currentDot.wantsLayer = true; currentDot.layer?.cornerRadius = 2; currentDot.isHidden = true
        heading.font = .systemFont(ofSize: 13, weight: .medium); heading.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: 11); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingMiddle
        address.font = keyCapFont(size: 14); address.alignment = .center
        icon.imageScaling = .scaleProportionallyUpOrDown
        launchBadge.image = NSImage(systemSymbolName: "arrow.up.forward.app.fill", accessibilityDescription: nil)
        launchBadge.imageScaling = .scaleProportionallyDown; launchBadge.wantsLayer = true
        launchBadge.layer?.cornerRadius = 7; launchBadge.setAccessibilityElement(false); launchBadge.isHidden = true
        minimizedBadge.isHidden = true
        for view in [icon, heading, detail, address, launchBadge, minimizedBadge, currentDot] { addSubview(view) }
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }
    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        // Keep both lines together: centering independent, oversized text fields
        // creates a visible gap and makes the icon look lower than the title.
        let headingHeight = ceil(heading.intrinsicContentSize.height)
        let detailHeight = detail.isHidden ? 0 : ceil(detail.intrinsicContentSize.height)
        let textGap: CGFloat = detail.isHidden ? 0 : 2
        let textHeight = headingHeight+textGap+detailHeight
        // Native application artwork includes transparent padding inside its
        // image bounds, so reserve a slightly larger box than the visible icon.
        let iconSize: CGFloat = (compact ? 32 : 36)+(style.scale.factor-1)*12
        let codeWidth = max(compact ? 28 : 34, min(tile ? bounds.width-20 : bounds.width*0.50, CGFloat(address.stringValue.count)*(compact ? 8 : 9)*style.scale.factor+12))
        let keyHeight = (compact ? 12 : 14)*style.scale.factor+(compact ? 10 : 12)
        if tile {
            icon.isHidden = w-codeWidth-26 < iconSize
            let topHeight = max(icon.isHidden ? 0 : iconSize,keyHeight)
            let topBottom = h-10-topHeight
            icon.frame = CGRect(x:7,y:topBottom+(topHeight-iconSize)/2,width:iconSize,height:iconSize)
            address.frame = CGRect(x:w-codeWidth-10,y:topBottom+(topHeight-keyHeight)/2,width:codeWidth,height:keyHeight)
            heading.frame = CGRect(x:10,y:topBottom-6-headingHeight,width:w-20,height:headingHeight)
            detail.frame = CGRect(x:10,y:heading.frame.minY-textGap-detailHeight,width:w-20,height:detailHeight)
        } else {
            icon.isHidden = false
            let iconX: CGFloat = compact ? 4 : 7
            let textX = iconX+iconSize+6
            let textY = (h-textHeight)/2
            icon.frame = CGRect(x:iconX,y:(h-iconSize)/2,width:iconSize,height:iconSize)
            address.frame = CGRect(x: w-codeWidth-10, y: (h-keyHeight)/2, width: codeWidth, height: keyHeight)
            heading.frame = CGRect(x:textX,y:textY+detailHeight+textGap,width:max(20,w-codeWidth-textX-24),height:headingHeight)
            detail.frame = CGRect(x:textX,y:textY,width:max(20,w-codeWidth-textX-24),height:detailHeight)
        }
        let badgeSize: CGFloat = 14
        launchBadge.frame = CGRect(x: icon.frame.maxX-badgeSize+2, y: icon.frame.minY-4, width: badgeSize, height: badgeSize)
        // Long addresses can hide tile artwork. Keep its state marker in the free
        // leading corner rather than hiding the only visual minimized cue with it.
        let minimizedSize: CGFloat = compact ? 12 : 14
        minimizedBadge.frame = CGRect(x: icon.isHidden ? 10 : icon.frame.maxX-minimizedSize,
                                     y: icon.isHidden ? icon.frame.midY-minimizedSize/2 : icon.frame.minY,
                                     width: minimizedSize, height: minimizedSize)
        // A tile's icon sits in the corner the dot would need, so only list rows carry it.
        currentDot.frame = CGRect(x: 2, y: (h-4)/2, width: 4, height: 4); currentDot.isHidden = tile || !isCurrent
    }
    func bind(_ target: Target, image: NSImage?, matches: Bool, selected: Bool, tokens: ThemeTokens, addressOverride: String? = nil,
              typed: Int = 0, current: Bool = false, outline: NSColor? = nil, radius: CGFloat = 7,
              containsMinimizedWindows: Bool = false) {
        let next = Binding(target: target, image: image.map(ObjectIdentifier.init), matches: matches,
                           selected: selected, tokens: tokens, addressOverride: addressOverride,
                           typed: typed, current: current, outline: outline, radius: radius,
                           style: style, compact: compact, grouped: grouped,
                           contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                           reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                           containsMinimizedWindows: containsMinimizedWindows)
        guard next != binding else { return }
        binding = next
        let oldHeading = heading.stringValue, oldDetail = detail.stringValue, oldAddress = address.stringValue
        let scale = style.scale.factor
        let fontsChanged = boundFonts?.compact != compact || boundFonts?.scale != scale
        if boundFonts?.compact != compact || boundFonts?.scale != scale {
            heading.font = .systemFont(ofSize:(compact ? 11 : 13) * scale,weight:.medium)
            detail.font = .systemFont(ofSize:(compact ? 9 : 11) * scale)
            address.font = keyCapFont(size:(compact ? 12 : 14)*scale)
            boundFonts = (compact, scale)
        }
        heading.textColor = NSColor(tokens.text); detail.textColor = NSColor(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? tokens.text : tokens.secondary)
        let strong = style.strongOutlines || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        styleKeyCap(address, tokens: tokens, strong: strong)
        if heading.stringValue != target.title { heading.stringValue = target.title }
        let state = !target.available ? String(localized: "Unavailable") : !target.isRunning ? String(localized: "Launch") : target.minimized ? String(localized: "Minimized") : target.hidden ? String(localized: "Hidden app") : target.elsewhere ? String(localized: "Elsewhere") : ""
        let context = target.group.isEmpty || target.group == target.app ? target.app : target.group.hasPrefix(target.app + " · ") ? target.group : target.app + " · " + target.group
        let visibleContext = grouped ? (target.group == target.app ? "" : target.group.replacingOccurrences(of: target.app + " · ", with: "", options: .anchored)) : target.title == target.app && context == target.app ? "" : context
        let detailText = [visibleContext, state].filter { !$0.isEmpty }.joined(separator: " · ")
        detail.isHidden = detailText.isEmpty
        if detail.stringValue != detailText { detail.stringValue = detailText }
        let shown = addressOverride ?? target.address, shownText = shown.isEmpty ? "—" : shown.uppercased()
        if typed > 0, typed < shownText.count {
            let centered = NSMutableParagraphStyle(); centered.alignment = .center; centered.lineBreakMode = .byClipping
            let text = NSMutableAttributedString(string: shownText, attributes: [.font: address.font as Any, .foregroundColor: NSColor(tokens.keyText), .paragraphStyle: centered])
            text.addAttribute(.foregroundColor, value: NSColor(tokens.keyText).withAlphaComponent(0.4), range: NSRange(location: 0, length: typed))
            address.attributedStringValue = text
        } else if address.stringValue != shownText || boundTyped { address.stringValue = shownText }
        boundTyped = typed > 0 && typed < shownText.count
        isCurrent = current; currentDot.layer?.backgroundColor = NSColor(tokens.selection).cgColor
        if let image { if icon.image !== image { icon.image = image } }
        else if !showsPlaceholder || icon.image == nil { icon.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil) }
        showsPlaceholder = image == nil
        launchBadge.isHidden = !target.available || target.isRunning
        launchBadge.contentTintColor = NSColor(tokens.surface)
        launchBadge.layer?.backgroundColor = NSColor(tokens.selection).cgColor
        minimizedBadge.isHidden = !target.available || !target.isRunning || !(target.minimized || containsMinimizedWindows)
        minimizedBadge.apply(tokens, strong: strong)
        alphaValue = matches ? 1 : 0.4; isEnabled = target.available
        layer?.backgroundColor = (selected ? NSColor(tokens.selection.mixed(with:tokens.surface,amount:0.88)) : themeRowFill(tokens, card: outline != nil)).cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = strong ? 2 : selected || outline != nil ? 1 : 0; layer?.borderColor = (selected ? NSColor(tokens.selection) : outline ?? NSColor.separatorColor).cgColor
        // Tooltip and accessibility registration are the costly part of a rebind; most frames
        // only move the highlight, so they are rewritten only when their text changed.
        let minimizedContext = containsMinimizedWindows ? String(localized: "Contains minimized windows") : ""
        let spokenState = [state, minimizedContext].filter { !$0.isEmpty }.joined(separator: ", ")
        let tip = "\(context) — \(target.title) · \(target.address.uppercased())\(spokenState.isEmpty ? "" : " · " + spokenState)"
        if tip != boundToolTip { toolTip = tip; boundToolTip = tip }
        let filteredSuffix = matches ? "" : String(localized: ", filtered out")
        let spoken = "\(target.address.uppercased()), \(context), \(target.title)\(spokenState.isEmpty ? "" : ", " + spokenState)\(filteredSuffix)"
        if spoken != boundSpoken { setAccessibilityLabel(spoken); boundSpoken = spoken }
        if target.address != boundAddress { setAccessibilityIdentifier("target-\(target.address)"); boundAddress = target.address }
        if selected != boundSelected { setAccessibilityValue(selected ? "Selected" : ""); boundSelected = selected }
        currentDot.isHidden = tile || !current
        if fontsChanged || oldHeading != heading.stringValue || oldDetail != detail.stringValue || oldAddress != address.stringValue {
            needsLayout = true
        }
    }
}

private final class BranchTile: SessionButton {
    override var isFlipped: Bool { false }
    private let addressLabel = makeKeyCapField()
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var scale: Double = 1
    private var styledScale: Double?
    init(address: String, detail: String, onPress: @escaping () -> Void) {
        super.init(frame: .zero); self.onPress = onPress
        title = ""; isBordered = false; wantsLayer = true
        layer?.cornerRadius = 9; layer?.cornerCurve = .continuous; layer?.borderWidth = 1; layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addressLabel.stringValue = address; addressLabel.font = keyCapFont(size: 14)
        detailLabel.stringValue = detail; detailLabel.font = .systemFont(ofSize: 12); detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3; detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(addressLabel); addSubview(detailLabel); target = self; action = #selector(press)
        toolTip = address + " · " + detail
    }
    func update(address: String, detail: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        if addressLabel.stringValue != address { addressLabel.stringValue = address; needsLayout = true }
        if detailLabel.stringValue != detail { detailLabel.stringValue = detail }
    }
    /// The same tint and outline a highlighted target row gets, so a branch reads as selected
    /// in the theme's colour rather than the system accent.
    func highlight(_ tokens: ThemeTokens) {
        layer?.backgroundColor = NSColor(tokens.selection.mixed(with:tokens.surface,amount:0.88)).cgColor
        layer?.borderColor = NSColor(tokens.selection).cgColor
    }
    func applyStyle(_ tokens:ThemeTokens,outline:NSColor,scale:Double,strong:Bool) {
        self.scale = scale
        layer?.backgroundColor = themeRowFill(tokens, card: true).cgColor
        // Neutral by default; the caller overrides to an accent border only for the
        // actually-highlighted tile (see the `highlightedAction` check after this call),
        // so unselected tiles no longer look pre-selected.
        layer?.borderColor = outline.cgColor; layer?.borderWidth = strong ? 2 : 1
        if styledScale != scale {
            addressLabel.font = keyCapFont(size:14*scale); detailLabel.font = .systemFont(ofSize:12*scale)
            styledScale = scale; needsLayout = true
        }
        styleKeyCap(addressLabel, tokens: tokens, strong: strong)
        detailLabel.textColor = NSColor(tokens.secondary)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }
    override func layout() {
        super.layout()
        addressLabel.frame = CGRect(x: 12, y: bounds.height-12-24*scale, width: min(bounds.width-24,max(34,CGFloat(addressLabel.stringValue.count)*9*scale+14)), height: 24*scale)
        detailLabel.frame = CGRect(x: 12, y: 10, width: bounds.width-24, height: max(20, bounds.height-28-24*scale))
    }
}

extension NSColor {
    convenience init(_ rgb: RGB) { self.init(srgbRed:rgb.r,green:rgb.g,blue:rgb.b,alpha:1) }
    var rgb: RGB { let c = usingColorSpace(.sRGB) ?? .black; return RGB(r:c.redComponent,g:c.greenComponent,b:c.blueComponent) }
}

struct EventRoute: @unchecked Sendable { let event: NSEvent? }
