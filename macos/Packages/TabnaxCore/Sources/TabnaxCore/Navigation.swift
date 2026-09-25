import Foundation

public enum NavigationAction: Equatable, Hashable, Sendable {
    case target(TargetID), branch(String)
}
public struct NavigationItem: Equatable, Sendable {
    public let action: NavigationAction
    public init(_ action: NavigationAction) { self.action = action }
}
public enum SwitcherAction: String, CaseIterable, Sendable {
    case quitApplication, restoreWindow, closeWindow, minimizeWindow, hideApplication, unhideApplication, zoomWindow, toggleFullscreen
    public var title: String { switch self {
    case .quitApplication: "Quit App"
    case .restoreWindow: "Restore Window"
    case .closeWindow: "Close Window"
    case .minimizeWindow: "Minimize Window"
    case .hideApplication: "Hide App"
    case .unhideApplication: "Unhide App"
    case .zoomWindow: "Zoom Window"
    case .toggleFullscreen: "Toggle Full Screen"
    } }
}

public struct SwitcherActionItem: Equatable, Sendable {
    public let action: SwitcherAction
    public let target: TargetID?
    public var disabledReason: String?
    public init(action: SwitcherAction, target: TargetID?, disabledReason: String? = nil) {
        self.action = action; self.target = target; self.disabledReason = disabledReason
    }
}

public extension SelectionState {
    /// Actions use the actual highlight, including pointer/search selection. An overflow
    /// cell is ambiguous; only Fold's app branches identify a single application.
    var highlightedTarget: Target? {
        guard active, let highlightedAction else { return nil }
        switch highlightedAction {
        case .target(let id): return targets.first { $0.id == id }
        case .branch(let code):
            return mode == .fold ? snapshot.apps.first { $0.foldAddress == code } : nil
        }
    }
    func actionTarget(for action: SwitcherAction) -> TargetID? { actionTarget(for: action, highlighted: highlightedTarget) }
    /// Takes the highlight so a whole menu resolves it (a full navigation pass) only once.
    private func actionTarget(for action: SwitcherAction, highlighted: Target?) -> TargetID? {
        guard let target = highlighted, target.available, target.isRunning else { return nil }
        switch action {
        case .quitApplication, .hideApplication, .unhideApplication:
            // Browser connections have their own lifetime identity. Never confuse it
            // with the real process that owns the selected tab.
            guard !snapshot.tabs.contains(where: { $0.id == target.id }) || target.owner != nil else { return nil }
            return TargetID(process: target.groupOwner)
        case .closeWindow, .minimizeWindow, .zoomWindow, .toggleFullscreen:
            // No most-recent-window fallback: app rows, tabs and branches are not windows.
            return snapshot.windows.first { $0.id == target.id }?.id
        case .restoreWindow:
            // Only catalogue windows can be restored. A tab's ID is not an AX window,
            // and restoring a visible window must never minimize it or another window.
            if target.id.window != nil {
                return snapshot.windows.first { $0.id == target.id && $0.minimized }?.id
            }
            let windows = snapshot.windows.filter {
                $0.groupOwner == target.groupOwner && $0.minimized && $0.available && $0.isRunning
            }
            // App rows and Fold families restore one exact child: most recently used,
            // falling back to stable catalogue order when it has no observed history.
            for id in [focusHistory.current].compactMap({ $0 }) + focusHistory.recent {
                if windows.contains(where: { $0.id == id }) { return id }
            }
            return windows.first?.id
        }
    }

    var actionMenuItems: [SwitcherActionItem] {
        let highlightedTarget = highlightedTarget
        let hidden = highlightedTarget?.hidden == true || snapshot.apps.contains { $0.id.process == highlightedTarget?.groupOwner && $0.hidden }
        let actions: [SwitcherAction] = [.closeWindow, .minimizeWindow, .restoreWindow,
            hidden ? .unhideApplication : .hideApplication,
            .zoomWindow, .toggleFullscreen, .quitApplication]
        return actions.map { action in
            let id = actionTarget(for: action, highlighted: highlightedTarget)
            let reason: String?
            if id != nil { reason = nil }
            else if highlightedTarget == nil { reason = "Highlight a single window or app" }
            else if highlightedTarget?.isRunning == false { reason = "App is not running" }
            else if highlightedTarget?.available == false { reason = "Target is no longer available" }
            else if action == .restoreWindow { reason = "No minimized window to restore" }
            else if [.quitApplication, .hideApplication, .unhideApplication].contains(action) { reason = "Browser owner is unavailable" }
            else if snapshot.tabs.contains(where: { $0.id == highlightedTarget?.id }) { reason = "Browser tab has no exact window target" }
            else { reason = "Highlight an individual window" }
            return SwitcherActionItem(action: action, target: id, disabledReason: reason)
        }
    }

    var navigationItems: [NavigationItem] { memoized(\.navigationItems) { computeNavigationItems() } }
    private func computeNavigationItems() -> [NavigationItem] {
        // Search keeps each mode's layout, so its results are walked in that layout's order.
        if query != nil {
            return displayMatches.filter(\.available).map { .init(.target($0.id)) }
        }
        if mode == .fold && foldFamily == nil {
            let owners = Set(matches.lazy.filter(\.available).map(\.groupOwner))
            return foldFamilies.filter { app in app.isRunning && owners.contains(app.id.process) }.map { .init(.branch($0.foldAddress)) }
        }
        if mode == .lattice {
            let cells = latticeCells.compactMap { cell -> NavigationItem? in
                if let t = cell.target, t.available, t.isRunning { return .init(.target(t.id)) }
                return cell.descendants.contains(where: { $0.available && $0.isRunning }) ? .init(.branch(cell.address)) : nil
            }
            // Unaddressed targets remain reachable after short-label exhaustion.
            return cells + appGroupedOrder(matches).filter { $0.address.isEmpty && $0.available && $0.isRunning }.map { .init(.target($0.id)) }
        }
        return displayMatches.filter(\.available).map { .init(.target($0.id)) }
    }
    /// Keeps each app's targets together: groups in first-seen order, or by `rank` when given.
    internal static func groupedByOwner(_ targets: [Target], rank: [UUID: Int]? = nil) -> [Target] {
        var order: [UUID] = [], grouped: [UUID: [Target]] = [:]
        for t in targets { let group = t.groupOwner; if grouped[group] == nil { order.append(group) }; grouped[group, default: []].append(t) }
        if let rank {
            let seen = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            order.sort { (rank[$0] ?? .max, seen[$0]!) < (rank[$1] ?? .max, seen[$1]!) }
        }
        return order.flatMap { grouped[$0] ?? [] }
    }
    /// Sizes of Canopy's app columns, in the order `navigationItems` walks them.
    var navigationGroupSizes: [Int] {
        guard mode == .canopy else { return [] }
        var sizes: [Int] = [], last: UUID?
        for target in appGroupedOrder(matches).filter({ $0.available && $0.isRunning }) {
            if target.groupOwner == last { sizes[sizes.count - 1] += 1 } else { sizes.append(1); last = target.groupOwner }
        }
        return sizes
    }
    internal func appGroupedOrder(_ matches: [Target]) -> [Target] {
        // Removing the first window of an app must not move its remaining results
        // behind another app. Keep the group order from the unfiltered catalogue.
        let rank = ownerRanks.isEmpty ? Dictionary(targets.enumerated().map { ($1.groupOwner, $0) }, uniquingKeysWith: { first, _ in first }) : ownerRanks
        return Self.groupedByOwner(matches, rank: rank)
    }
    internal func relayOrder(_ targets: [Target]) -> [Target] {
        let first = [focusHistory.current,focusHistory.previous].compactMap { id in targets.first { $0.id == id } }
        let ids = Set(first.map(\.id)); return first + targets.filter { !ids.contains($0.id) }
    }
    var highlightedAction: NavigationAction? {
        if let pointerFocus { return pointerFocus }
        let items = navigationItems
        return items.indices.contains(cursor) ? items[cursor].action : nil
    }
}
/// A gesture selects only its highlighted stop. Momentum is ignored, and deltas
/// are already expressed in the direction of AppKit's scrolling content.
public struct WheelNavigation: Sendable {
    private var accumulated: Double = 0
    private var direction: Double = 0
    public init() {}
    public mutating func reset() { accumulated = 0; direction = 0 }
    public mutating func steps(delta: Double, precise: Bool, momentum: Bool, horizontal: Double = 0) -> Int {
        guard !momentum, delta.isFinite, horizontal.isFinite, abs(delta) > abs(horizontal), delta != 0 else { return 0 }
        let sign: Double = delta > 0 ? 1 : -1
        if sign != direction { accumulated = 0 }; direction = sign
        if !precise { return delta > 0 ? 1 : -1 }
        accumulated += delta
        let count = max(-5,min(5,Int(accumulated/40)))
        accumulated -= Double(count)*40
        return count
    }
}

public enum WheelPhase: Sendable { case unphased, mayBegin, began, changed, ended, cancelled }
/// Phased trackpad gestures keep the region where they began. Entering the
/// switcher halfway through a gesture must not change its selection.
public struct WheelGesture: Sendable {
    private var owner: String?
    private var phased = false
    private var wheel = WheelNavigation()
    public init() {}
    public mutating func reset() { owner = nil; phased = false; wheel.reset() }
    public mutating func navigate(region: String?, phase: WheelPhase, delta: Double, precise: Bool, momentum: Bool, horizontal: Double = 0) -> (region: String, steps: Int)? {
        if phase == .mayBegin || phase == .began { reset(); if phase == .began { owner = region; phased = true } }
        if phase == .ended || phase == .cancelled { reset(); return nil }
        guard let region, !momentum else { return nil }
        if phase == .unphased {
            phased = false
            if owner != region { wheel.reset(); owner = region }
        } else if phase == .mayBegin || !phased || owner == nil { return nil }
        guard let owner else { return nil }
        let steps = wheel.steps(delta:delta,precise:precise,momentum:false,horizontal:horizontal)
        return steps == 0 ? nil : (owner,steps)
    }
}
