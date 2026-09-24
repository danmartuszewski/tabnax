import Foundation

/// Presentation only. Addresses are allocated before ordering and never reassigned here.
public enum TraversalOrder: String, Codable, CaseIterable, Sendable {
    case stable, recent, alphabetical, state
    public var title: String {
        switch self {
        case .stable: "Stable"
        case .recent: "Most recently used"
        case .alphabetical: "Alphabetical"
        case .state: "Window state"
        }
    }
    public var explanation: String {
        switch self {
        case .stable: "Keep the existing catalogue order. Relay keeps its current and previous window cards first."
        case .recent: "Current window first, then observed recent windows. Windows without history, tabs and app rows keep their stable relative order afterward."
        case .alphabetical: "Sort by app name, then window or tab title, using natural text order."
        case .state: "Ordinary windows first, then other Spaces, minimized windows, hidden apps and unavailable targets. Ties keep their stable order."
        }
    }
    internal func sorted(_ targets: [Target], history: FocusHistory) -> [Target] {
        guard self != .stable else { return targets }
        let recent = Dictionary(uniqueKeysWithValues: ([history.current].compactMap { $0 } + history.recent).enumerated().map { ($1, $0) })
        func stateRank(_ t: Target) -> Int {
            if !t.isRunning { return 5 }
            if !t.available { return 4 }
            if t.hidden { return 3 }
            if t.minimized { return 2 }
            if t.elsewhere { return 1 }
            return 0
        }
        return targets.enumerated().sorted { a, b in
            switch self {
            case .stable: break
            case .recent:
                let ar = recent[a.element.id] ?? .max, br = recent[b.element.id] ?? .max
                if ar != br { return ar < br }
            case .alphabetical:
                let app = a.element.app.localizedStandardCompare(b.element.app)
                if app != .orderedSame { return app == .orderedAscending }
                let title = a.element.title.localizedStandardCompare(b.element.title)
                if title != .orderedSame { return title == .orderedAscending }
            case .state:
                let ar = stateRank(a.element), br = stateRank(b.element)
                if ar != br { return ar < br }
            }
            return a.offset < b.offset
        }.map(\.element)
    }
}
