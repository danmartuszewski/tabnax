import AppKit

/// A bounded, noninteractive header; actions remain native, keyboard-accessible menu items.
@MainActor final class StatusMenuHeaderView: NSView {
    static let width: CGFloat = 292
    private let titleLabel = NSTextField(labelWithString: "Tabnax")
    private let contextLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var needsAccessibility = false
    private var cardFrame = NSRect.zero
    // Inputs from the last `update()` call that actually rebuilt the labels/layout, so a
    // repeat call with the same inputs (e.g. every time the status menu opens, which is far
    // more often than these actually change) can skip the rebuild and `needsDisplay` entirely.
    private var lastMode: String?
    private var lastShortcut: String?
    private var lastMessage: String?
    private var lastAccessibilityTrusted: Bool?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 100))
        autoresizingMask = [.width]
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        contextLabel.font = .systemFont(ofSize: 11)
        contextLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping
        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.setAccessibilityElement(false)
        for view in [titleLabel, contextLabel, statusIcon, statusLabel, detailLabel] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(mode: String, shortcut: String, message: String, accessibilityTrusted: Bool) {
        guard lastMode != mode || lastShortcut != shortcut || lastMessage != message || lastAccessibilityTrusted != accessibilityTrusted else { return }
        lastMode = mode; lastShortcut = shortcut; lastMessage = message; lastAccessibilityTrusted = accessibilityTrusted
        needsAccessibility = !accessibilityTrusted
        // Matches ModePresenter's switcher-panel handling of the same system setting.
        let secondaryText: NSColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .labelColor : .secondaryLabelColor
        contextLabel.textColor = secondaryText; detailLabel.textColor = secondaryText
        contextLabel.stringValue = shortcut
        contextLabel.setAccessibilityLabel(String(localized: "Open switcher: \(shortcut)"))
        let ready = accessibilityTrusted && message == "Ready"
        statusIcon.isHidden = ready; statusLabel.isHidden = ready
        statusLabel.stringValue = needsAccessibility ? String(localized: "Accessibility required") : ready ? String(localized: "Ready to switch") : String(localized: "Status")
        detailLabel.stringValue = needsAccessibility
            ? String(localized: "Enable Tabnax in System Settings, then click Retry in Tabnax Settings.")
            : ready ? "" : message
        detailLabel.isHidden = detailLabel.stringValue.isEmpty
        let symbol = needsAccessibility ? "exclamationmark.triangle.fill" : ready ? "checkmark.circle.fill" : "info.circle"
        statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        statusIcon.contentTintColor = needsAccessibility ? .systemOrange : ready ? .systemGreen : .secondaryLabelColor
        resizeToFit()
    }

    private func resizeToFit() {
        // Measure wrapped copy instead of letting diagnostic text widen the entire menu.
        let textWidth = bounds.width - 62
        let detailHeight = detailLabel.isHidden ? 0 : ceil(detailLabel.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)).height ?? 0)
        let cardHeight = statusLabel.isHidden ? 0 : 36 + (detailHeight > 0 ? detailHeight + 5 : 0)
        setFrameSize(NSSize(width: bounds.width, height: cardHeight == 0 ? 58 : 61 + cardHeight + 8))
        titleLabel.frame = NSRect(x: 18, y: 10, width: bounds.width - 36, height: 19)
        contextLabel.frame = NSRect(x: 18, y: 32, width: bounds.width - 36, height: 16)
        cardFrame = NSRect(x: 10, y: 58, width: bounds.width - 20, height: cardHeight)
        statusIcon.frame = NSRect(x: 21, y: 69, width: 14, height: 14)
        statusLabel.frame = NSRect(x: 42, y: 68, width: textWidth, height: 17)
        detailLabel.frame = NSRect(x: 42, y: 90, width: textWidth, height: detailHeight)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !statusLabel.isHidden else { return }
        let tint: NSColor = needsAccessibility ? .systemOrange : .secondaryLabelColor
        tint.withAlphaComponent(needsAccessibility ? 0.09 : 0.06).setFill()
        NSBezierPath(roundedRect: cardFrame, xRadius: 7, yRadius: 7).fill()
    }
}
