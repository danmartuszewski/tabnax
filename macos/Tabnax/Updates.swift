import AppKit
import Sparkle

/// Sparkle-backed update checks for signed releases. Debug builds and builds without a
/// Sparkle public key have no updater, so development copies never replace themselves.
@MainActor final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Called when a scheduled check finds an update, or when the user has seen it.
    var onPendingUpdateChange: ((Bool) -> Void)?

    static var isConfigured: Bool {
        #if DEBUG
        return false
        #else
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        return !key.isEmpty && !feed.isEmpty
        #endif
    }

    func start() {
        guard Self.isConfigured, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // A menu-bar app has no Dock icon, so scheduled updates are surfaced in the status
    // menu instead of a window appearing behind the user's work.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !state.userInitiated { onPendingUpdateChange?(true) }
        if handleShowingUpdate { NSApp.activate() }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onPendingUpdateChange?(false)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onPendingUpdateChange?(false)
    }
}
