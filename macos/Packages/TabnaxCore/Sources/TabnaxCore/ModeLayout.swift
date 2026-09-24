import Foundation
import CoreGraphics

/// Shared by the live panel and the scaled desktop in Position settings.
public enum SwitcherGeometry {
    public static func size(mode: DisplayMode, count: Int, rowStride: CGFloat = 60) -> CGSize {
        let width: CGFloat = [.shore:410,.beacons:750,.canopy:1080,.lattice:1080,.fold:820,.relay:830][mode]!
        let height: CGFloat = [.shore:CGFloat(min(12,max(1,count)))*rowStride+196,.beacons:336,.canopy:616,.lattice:506,.fold:636,.relay:646][mode]!
        return CGSize(width:width,height:height)
    }
    public static func previewFrame(placement: Placement, mode: DisplayMode, count: Int, screen: CGRect, visible: CGRect, canvas: CGSize) -> CGRect {
        guard screen.width > 0, screen.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
        let actual = placement.frame(size:size(mode:mode,count:count),visible:visible)
        let scale = min(canvas.width/screen.width,canvas.height/screen.height)
        return CGRect(x:(canvas.width-screen.width*scale)/2+(actual.minX-screen.minX)*scale,
                      y:(canvas.height-screen.height*scale)/2+(screen.maxY-actual.maxY)*scale,
                      width:actual.width*scale,height:actual.height*scale)
    }
}

/// Why a window couldn't be given an on-screen plaque and was routed to the bank instead.
public enum BankReason: Sendable {
    /// The window exists but AX reports it hidden or unavailable.
    case occluded
    /// The window is minimized or off-screen entirely.
    case offScreen
    /// No usable frame/screen could be resolved, or the screen has no room for a plaque.
    case ambiguousPosition
    /// A valid plaque position was found but it overlaps a reserved area or another plaque.
    case colliding
}

public struct BankEntry: Sendable {
    public let id: TargetID
    public let reason: BankReason
    public init(id: TargetID, reason: BankReason) { self.id = id; self.reason = reason }
}

public struct BeaconPlan: Sendable {
    public var plaques: [TargetID: CGRect]
    public var bank: [BankEntry]
    /// Frames and displays use the same coordinate system. Placement never queries the OS.
    public static func make(targets: [Target], frames: [TargetID: CGRect], screens: [CGRect], reserved: CGRect, plaqueHeight: CGFloat = 66) -> Self {
        var plaques: [TargetID: CGRect] = [:], bank: [BankEntry] = []
        for target in targets {
            guard target.available, !target.hidden else {
                bank.append(BankEntry(id: target.id, reason: .occluded)); continue
            }
            guard !target.minimized, target.onScreen else {
                bank.append(BankEntry(id: target.id, reason: .offScreen)); continue
            }
            guard let bounds = frames[target.id], let screen = screens.max(by: {
                      area($0.intersection(bounds)) < area($1.intersection(bounds))
                  }), area(screen.intersection(bounds)) > 0 else {
                bank.append(BankEntry(id: target.id, reason: .ambiguousPosition)); continue
            }
            guard screen.width >= 310, screen.height >= max(66,plaqueHeight)+24, plaques.count < 24 else {
                bank.append(BankEntry(id: target.id, reason: .ambiguousPosition)); continue
            }
            let width = min(330, screen.width - 24), height = min(max(66,plaqueHeight),screen.height-24)
            let x = max(screen.minX + 12, min(bounds.minX + 12, screen.maxX - width - 12))
            let y = max(screen.minY + 12, min(bounds.maxY - height - 8, screen.maxY - height - 12))
            let plaque = CGRect(x: x, y: y, width: width, height: height)
            guard !plaque.intersects(reserved), !plaques.values.contains(where: { $0.insetBy(dx: -8, dy: -8).intersects(plaque) }) else {
                bank.append(BankEntry(id: target.id, reason: .colliding)); continue
            }
            plaques[target.id] = plaque
        }
        return Self(plaques: plaques, bank: bank)
    }
    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
