import AppKit
import QuartzCore
import TabnaxCore

/// The panels never activate or receive input. Window raising is coordinated on
/// the focus lane before presentation. The switcher stays above the dimming.
@MainActor final class DesktopSpotlight {
    private(set) var panels: [NSPanel] = []

    static func windowFrame(for state: SelectionState, primaryTop: CGFloat, requiresVisibility: Bool = true) -> CGRect? {
        guard state.active, case .target(let id) = state.highlightedAction,
              let target = state.snapshot.windows.first(where: { $0.id == id }),
              target.available, target.isRunning, (!requiresVisibility || target.onScreen),
              !target.hidden, !target.minimized, !target.elsewhere,
              let bounds = target.bounds, usable(bounds) else { return nil }
        let frame = CGRect(x: bounds.minX, y: primaryTop-bounds.maxY, width: bounds.width, height: bounds.height)
        return usable(frame) ? frame : nil
    }

    private static func usable(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite && rect.width > 1 && rect.height > 1
    }

    func present(_ state: SelectionState, preferences: DesktopSpotlightPreferences,
                 accent: NSColor, strong: Bool, screens: [CGRect], ready: Bool = true, reduceMotion: Bool? = nil) {
        guard preferences.enabled, state.active, let primary = screens.first else { dismiss(); return }
        let switcherOnly = preferences.mode == .switcherOnly
        let targetFrame = Self.windowFrame(for: state, primaryTop: primary.maxY, requiresVisibility: false)
        guard switcherOnly || targetFrame.map({ frame in screens.contains { $0.intersects(frame) } }) == true else { dismiss(); return }
        let frame = switcherOnly ? CGRect.zero : targetFrame!
        let screens = screens.filter(Self.usable)
        let revealed = !switcherOnly && ready && Self.windowFrame(for: state, primaryTop: primary.maxY) != nil
        let duration = preferences.transitionDuration(reduceMotion: reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        while panels.count > screens.count { panels.removeLast().close() }
        while panels.count < screens.count {
            let panel = SpotlightPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.identifier = .init("desktop-spotlight-\(panels.count)")
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue-1)
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false; panel.isExcludedFromWindowsMenu = true
            panel.animationBehavior = .none
            panel.contentView = DesktopSpotlightView()
            panels.append(panel)
        }
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen, display: false)
            let view = panel.contentView as! DesktopSpotlightView
            view.configure(windowFrame: frame.offsetBy(dx: -screen.minX, dy: -screen.minY),
                           opacity: preferences.activeOpacity, accent: accent, strong: strong,
                           revealed: revealed, transitionDuration: duration)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    func dismiss() {
        panels.forEach { ($0.contentView as? DesktopSpotlightView)?.cancelTransition(); $0.close() }
    }
}

private final class SpotlightPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Coordinates are local AppKit points; the same drawing also powers the settings
/// example. A spanning window keeps its real corners instead of gaining a border
/// at the seam between displays.
@MainActor final class DesktopSpotlightView: NSView {
    private(set) var windowFrame = CGRect.zero
    private(set) var opacity = 0.35
    private var accent = NSColor.controlAccentColor
    private var strong = false
    private(set) var revealed = false
    let revealCover = CAShapeLayer()
    private let outline = CAShapeLayer(), outlineShadow = CAShapeLayer()
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for shape in [revealCover, outlineShadow, outline] {
            shape.fillColor = NSColor.clear.cgColor
            layer?.addSublayer(shape)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }

    func configure(windowFrame: CGRect, opacity: Double, accent: NSColor, strong: Bool,
                   revealed: Bool = true, transitionDuration: Double = 0) {
        let changedFrame = self.windowFrame != windowFrame
        let reveal = revealed && (!self.revealed || changedFrame)
        guard changedFrame || self.opacity != opacity || self.accent != accent || self.strong != strong || self.revealed != revealed else { return }
        self.windowFrame = windowFrame; self.opacity = opacity; self.accent = accent; self.strong = strong
        self.revealed = revealed
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let hole = CGPath(roundedRect: windowFrame, cornerWidth: 10, cornerHeight: 10, transform: nil)
        let border = CGPath(roundedRect: windowFrame.insetBy(dx: 2, dy: 2), cornerWidth: 8, cornerHeight: 8, transform: nil)
        revealCover.path = hole; revealCover.fillColor = NSColor.black.withAlphaComponent(opacity).cgColor
        for shape in [outlineShadow, outline] { shape.path = border }
        outlineShadow.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
        outlineShadow.lineWidth = strong ? 7 : 5
        outline.strokeColor = accent.cgColor; outline.lineWidth = strong ? 4 : 3
        for shape in [revealCover, outlineShadow, outline] {
            shape.removeAllAnimations()
            shape.opacity = revealed ? (shape === revealCover ? 0 : 1) : 0
        }
        if reveal && transitionDuration > 0 {
            for shape in [revealCover, outlineShadow, outline] {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = shape === revealCover ? 1 : 0
                animation.toValue = shape.opacity
                animation.duration = transitionDuration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shape.add(animation, forKey: "windowReveal")
            }
        }
        CATransaction.commit()
        needsDisplay = true
    }

    func cancelTransition() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for shape in [revealCover, outlineShadow, outline] { shape.removeAllAnimations(); shape.opacity = 0 }
        CATransaction.commit()
        revealed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let hole = NSBezierPath(roundedRect: windowFrame, xRadius: 10, yRadius: 10)
        let shade = NSBezierPath(rect: bounds)
        if revealed { shade.append(hole); shade.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(opacity).setFill(); shade.fill()
    }
}

/// Fictional windows only; settings never dims or captures the user's desktop.
@MainActor final class DesktopSpotlightSampleView: NSView {
    private var replayToken = 0
    private let switcherSample = SwitcherOnlySampleView()
    let spotlight = DesktopSpotlightView()
    private var preferences = DesktopSpotlightPreferences()
    private var accent = NSColor.controlAccentColor
    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(spotlight)
        addSubview(switcherSample)
        switcherSample.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("Programmatic views only") }
    func configure(preferences: DesktopSpotlightPreferences, accent: NSColor, replayToken: Int = 0) {
        if self.preferences != preferences { spotlight.cancelTransition() }
        self.preferences = preferences; self.accent = accent
        spotlight.isHidden = !preferences.enabled
        switcherSample.isHidden = !preferences.enabled || preferences.mode != .switcherOnly
        needsLayout = true
        if self.replayToken != replayToken, preferences.mode == .selectedWindow {
            self.replayToken = replayToken
            layoutSubtreeIfNeeded()
            spotlight.cancelTransition()
            spotlight.configure(windowFrame: selectedFrame, opacity: preferences.resolvedOpacity, accent: accent, strong: false,
                                transitionDuration: preferences.transitionDuration(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        }
    }
    private var selectedFrame: CGRect { CGRect(x: bounds.width*0.43, y: 15, width: bounds.width*0.49, height: bounds.height-30) }
    override func layout() {
        super.layout()
        spotlight.frame = bounds
        spotlight.configure(windowFrame: selectedFrame, opacity: preferences.activeOpacity, accent: accent, strong: false,
                            revealed: preferences.mode == .selectedWindow)
        switcherSample.frame = CGRect(x: (bounds.width-170)/2, y: (bounds.height-44)/2, width: 170, height: 44)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.44, green: 0.56, blue: 0.64, alpha: 1).setFill(); bounds.fill()
        for (rect, title) in [(CGRect(x: 18, y: 24, width: bounds.width*0.48, height: bounds.height-42), String(localized: "Other window")),
                              (selectedFrame, String(localized: "Selected window"))] {
            NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            (title as NSString).draw(at: CGPoint(x: rect.minX+12, y: rect.maxY-25), withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.darkGray])
            NSColor.lightGray.withAlphaComponent(0.45).setFill()
            for offset in [38.0, 50.0, 62.0] where rect.height > offset+8 {
                CGRect(x: rect.minX+12, y: rect.maxY-offset, width: rect.width-30, height: 3).fill()
            }
        }
    }
}

@MainActor private final class SwitcherOnlySampleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        (String(localized: "Window switcher") as NSString).draw(at: CGPoint(x: 20, y: 15), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
    }
}
