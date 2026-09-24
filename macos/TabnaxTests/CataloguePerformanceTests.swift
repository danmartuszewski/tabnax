import XCTest
import AppKit
import ApplicationServices
@testable import Tabnax
import TabnaxCore

final class CataloguePerformanceTests: XCTestCase {
    @MainActor func testWakeRecoveryRetriesAfterAnInitiallyIncompleteWindowList() {
        var callbacks: [(TimeInterval, @MainActor () -> Void)] = []
        let recovery = CatalogueRecoveryRefresh { callbacks.append(($0, $1)) }
        var reportedWindows = ["Main display"]
        var cachedWindows = reportedWindows
        recovery.restart { cachedWindows = reportedWindows }
        XCTAssertEqual(callbacks.map(\.0), [0.5, 1.5, 3, 6])
        callbacks[0].1()
        XCTAssertEqual(cachedWindows, ["Main display"])
        reportedWindows.append("External display")
        callbacks[1].1()
        XCTAssertEqual(cachedWindows, reportedWindows)
        XCTAssertEqual(callbacks.count, 4, "Recovery must stop without idle polling")
    }

    @MainActor func testDisplayRecoveryReplacesOlderBurstAndStopCancelsQueuedRefreshes() {
        var callbacks: [@MainActor () -> Void] = []
        let recovery = CatalogueRecoveryRefresh { _, action in callbacks.append(action) }
        var oldReads = 0, newReads = 0
        recovery.restart { oldReads += 1 }
        let old = callbacks; callbacks.removeAll()
        recovery.restart { newReads += 1 }
        old.forEach { $0() }
        XCTAssertEqual(oldReads, 0)
        callbacks[0]()
        XCTAssertEqual(newReads, 1)
        recovery.cancel()
        callbacks.dropFirst().forEach { $0() }
        XCTAssertEqual(newReads, 1)
    }

    private func workerQueue() -> OperationQueue {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }
    private func handle() -> AXHandle {
        AXHandle(AXUIElementCreateApplication(Foundation.ProcessInfo.processInfo.processIdentifier))
    }

    @MainActor func testTitleNotificationsCoalesceBeforeReadingOffMain() async {
        let id = TargetID(process: UUID(), window: UUID()), handle = handle()
        let reads = Locked(0), offMain = Locked(true)
        let reader = CatalogueTitleReader(workers: workerQueue()) { _ in
            reads.withValue { $0 += 1 }; offMain.withValue { $0 = $0 && !Thread.isMainThread }
            return "Latest title"
        }
        let received = expectation(description: "One latest title")
        reader.onRead = { request, title in
            XCTAssertEqual(request.id, id); XCTAssertEqual(title, "Latest title")
            received.fulfill()
        }
        for _ in 0..<20 { reader.enqueue(id: id, pid: 1, handle: handle) }
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(reads.withValue { $0 }, 1)
        XCTAssertTrue(offMain.withValue { $0 })
    }

    @MainActor func testNewTitleNotificationRejectsAnOlderInFlightRead() async {
        let id = TargetID(process: UUID(), window: UUID()), handle = handle()
        let started = expectation(description: "First read is blocked")
        let latest = expectation(description: "Only the replacement title is delivered")
        let release = DispatchSemaphore(value: 0), reads = Locked(0)
        let reader = CatalogueTitleReader(workers: workerQueue()) { _ in
            let index = reads.withValue { $0 += 1; return $0 }
            if index == 1 { started.fulfill(); _ = release.wait(timeout: .now() + 3) }
            return index == 1 ? "Obsolete" : "Newest"
        }
        var titles: [String] = []
        reader.onRead = { _, title in titles.append(title); latest.fulfill() }
        reader.enqueue(id: id, pid: 1, handle: handle)
        await fulfillment(of: [started], timeout: 3)
        for _ in 0..<10 { reader.enqueue(id: id, pid: 1, handle: handle) }
        release.signal()
        await fulfillment(of: [latest], timeout: 3)
        XCTAssertEqual(titles, ["Newest"])
        XCTAssertEqual(reads.withValue { $0 }, 2)
    }

    @MainActor func testResetRejectsOldLifetimeWithoutDiscardingNewReads() async {
        let id = TargetID(process: UUID(), window: UUID()), handle = handle()
        let started = expectation(description: "Old lifetime read started")
        let latest = expectation(description: "New lifetime delivered")
        let release = DispatchSemaphore(value: 0), reads = Locked(0)
        let reader = CatalogueTitleReader(workers: workerQueue()) { _ in
            let index = reads.withValue { $0 += 1; return $0 }
            if index == 1 { started.fulfill(); _ = release.wait(timeout: .now() + 3) }
            return index == 1 ? "Old lifetime" : "New lifetime"
        }
        var titles: [String] = []
        reader.onRead = { _, title in titles.append(title); latest.fulfill() }
        reader.enqueue(id: id, pid: 1, handle: handle)
        await fulfillment(of: [started], timeout: 3)
        reader.reset()
        reader.enqueue(id: id, pid: 1, handle: handle)
        release.signal()
        await fulfillment(of: [latest], timeout: 3)
        XCTAssertEqual(titles, ["New lifetime"])
        XCTAssertEqual(reads.withValue { $0 }, 2)
    }

    @MainActor func testRemovedWindowRejectsItsInFlightTitle() async {
        let removed = TargetID(process: UUID(), window: UUID())
        let live = TargetID(process: UUID(), window: UUID()), handle = handle()
        let started = expectation(description: "Removed window read started")
        let received = expectation(description: "Live window delivered")
        let release = DispatchSemaphore(value: 0), reads = Locked(0)
        let reader = CatalogueTitleReader(workers: workerQueue()) { _ in
            let index = reads.withValue { $0 += 1; return $0 }
            if index == 1 { started.fulfill(); _ = release.wait(timeout: .now() + 3) }
            return "Title"
        }
        var delivered: [TargetID] = []
        reader.onRead = { request, _ in delivered.append(request.id); received.fulfill() }
        reader.enqueue(id: removed, pid: 1, handle: handle)
        await fulfillment(of: [started], timeout: 3)
        reader.invalidate(removed)
        reader.enqueue(id: live, pid: 1, handle: handle)
        release.signal()
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(delivered, [live])
        XCTAssertNil(reader.versions[removed])
    }

    @MainActor func testDiscoveryPreservesOnlyTitlesUpdatedSinceItStarted() {
        let id = TargetID(process: UUID(), window: UUID())
        let original = WindowRecord(id: id, handle: handle(), title: "Discovery title", minimized: false, available: true)
        var current = original; current.title = "Newer notification title"
        let retained = WindowCatalogue.preservingNewerTitles([original], current: [current], startedVersions: [id: 1], currentVersions: [id: 2])
        XCTAssertEqual(retained.first?.title, current.title)
        let accepted = WindowCatalogue.preservingNewerTitles([original], current: [current], startedVersions: [id: 2], currentVersions: [id: 2])
        XCTAssertEqual(accepted.first?.title, original.title)
        XCTAssertTrue(WindowCatalogue.preservingNewerTitles([], current: [current], startedVersions: [id: 1], currentVersions: [id: 2]).isEmpty,
            "Keeping a newer title must never resurrect a window discovery retired.")
    }

    @MainActor func testDiscoveryPublicationsCoalesceAndCancellationAllowsANewBatch() async {
        let batcher = CataloguePublicationBatcher()
        let first = expectation(description: "One publication for a burst")
        var publications = 0
        for _ in 0..<20 { batcher.schedule { publications += 1; first.fulfill() } }
        await fulfillment(of: [first], timeout: 3)
        XCTAssertEqual(publications, 1)

        batcher.schedule { XCTFail("An immediate update must cancel the obsolete publication") }
        batcher.cancel()
        let replacement = expectation(description: "New publication remains scheduled")
        batcher.schedule { publications += 1; replacement.fulfill() }
        await fulfillment(of: [replacement], timeout: 3)
        XCTAssertEqual(publications, 2)
    }

    func testRefreshPrioritizesForegroundThenRecentLifetimesAndDeduplicatesProcesses() {
        let first = UUID(), second = UUID(), third = UUID(), oldLifetime = UUID()
        var history = FocusHistory()
        history.observe(TargetID(process: oldLifetime, window: UUID()))
        history.observe(TargetID(process: first, window: UUID()))
        history.observe(TargetID(process: second, window: UUID()))
        history.observe(TargetID(process: second, window: UUID()))
        let processes: [pid_t: UUID] = [10: first, 20: second, 30: third, 5: UUID()]
        XCTAssertEqual(WindowCatalogue.refreshOrder(processes: processes, frontmostPID: 30, history: history), [30, 20, 10, 5])
        XCTAssertEqual(WindowCatalogue.refreshOrder(processes: processes, frontmostPID: 20, history: history), [20, 10, 5, 30])
        XCTAssertEqual(WindowCatalogue.refreshOrder(processes: processes, frontmostPID: 999, history: .init()), [5, 10, 20, 30])
    }
}
