import XCTest
@testable import Tabnax
import TabnaxCore

final class BrowserPerformanceTests: XCTestCase {
    @MainActor func testIdenticalRefreshesDoNotRepublishTargets() {
        let catalogue = BrowserCatalogue(observesSystem:false)
        let tabs = [BrowserTabRecord(id:"1",window:"1",title:"Example")]
        catalogue.seedForTesting(.chrome,tabs:tabs)
        let original = catalogue.targets
        var changes = 0
        catalogue.onChange = { changes += 1 }

        catalogue.refresh()
        catalogue.refreshForOpening()
        catalogue.updateTabsForTesting(.chrome,tabs:tabs)

        XCTAssertEqual(changes,0)
        XCTAssertEqual(catalogue.targets,original)
    }

    @MainActor func testStatusOnlyChangesDoNotRepublishTargets() {
        let catalogue = BrowserCatalogue(observesSystem:false)
        catalogue.seedForTesting(.chrome,tabs:[])
        var changes = 0, statusChanges = 0
        catalogue.onChange = { changes += 1 }
        catalogue.onStatusChange = { statusChanges += 1 }

        catalogue.permissionForTesting(-1743,browser:.chrome)
        catalogue.permissionForTesting(-1743,browser:.chrome)
        XCTAssertEqual(catalogue.status[.chrome],"Automation approval required")
        XCTAssertEqual(statusChanges,1)
        catalogue.permissionForTesting(0,browser:.chrome)

        XCTAssertEqual(statusChanges,2)
        XCTAssertEqual(changes,0)
        XCTAssertTrue(catalogue.targets.isEmpty)
    }

    @MainActor func testRouteMetadataStaysCurrentWithoutRemappingUnchangedTargets() throws {
        let catalogue = BrowserCatalogue(observesSystem:false)
        var tab = BrowserTabRecord(id:"1",window:"1",title:"Example",group:"Research")
        catalogue.seedForTesting(.chrome,tabs:[tab])
        let original = try XCTUnwrap(catalogue.targets.first)
        var changes = 0
        catalogue.onChange = { changes += 1 }

        // Moving a grouped tab keeps its displayed group/name but changes the
        // window that the focus request must address.
        tab.window = "2"
        catalogue.updateTabsForTesting(.chrome,tabs:[tab])
        XCTAssertEqual(changes,0)
        XCTAssertEqual(catalogue.targets,[original])
        XCTAssertEqual(catalogue.tabForTesting(original.id)?.window,"2")

        tab.title = "Updated title"
        catalogue.updateTabsForTesting(.chrome,tabs:[tab])
        XCTAssertEqual(changes,1)
        XCTAssertEqual(catalogue.targets.first?.id,original.id)
        XCTAssertEqual(catalogue.targets.first?.title,"Updated title")

        catalogue.updateTabsForTesting(.chrome,tabs:[])
        XCTAssertEqual(changes,2)
        XCTAssertTrue(catalogue.targets.isEmpty)
        XCTAssertFalse(catalogue.owns(original.id))
    }

    @MainActor func testActivationOnlyRepublishesWhenRangeEligibilityChanges() {
        let catalogue = BrowserCatalogue(observesSystem:false)
        catalogue.seedForTesting(.chrome,tabs:[.init(id:"1",window:"1",title:"Example")])
        let identities = catalogue.targets.map(\.id)
        var changes = 0
        catalogue.onChange = { changes += 1 }

        catalogue.activateBrowserForTesting(.chrome)
        catalogue.activateBrowserForTesting(.safari)
        XCTAssertEqual(changes,0,"The all-browser range does not depend on the foreground app.")

        var preferences = BrowserPreferences()
        preferences.range = .activeBrowser
        catalogue.configure(preferences)
        XCTAssertEqual(changes,1)
        XCTAssertTrue(catalogue.targets.allSatisfy(\.excluded))
        catalogue.activateBrowserForTesting(.chrome)
        XCTAssertEqual(changes,2)
        XCTAssertTrue(catalogue.targets.allSatisfy(\.available))
        catalogue.activateBrowserForTesting(.chrome)
        XCTAssertEqual(changes,2)

        preferences.enabled = false
        catalogue.configure(preferences)
        XCTAssertEqual(changes,3)
        catalogue.activateBrowserForTesting(.safari)
        catalogue.refreshForOpening()
        XCTAssertEqual(changes,3)
        XCTAssertEqual(catalogue.targets.map(\.id),identities)
        XCTAssertTrue(catalogue.targets.allSatisfy { $0.excluded && !$0.available })

        preferences.enabled = true
        preferences.range = .all
        catalogue.configure(preferences)
        XCTAssertEqual(changes,4)
        XCTAssertEqual(catalogue.targets.map(\.id),identities)
        XCTAssertTrue(catalogue.targets.allSatisfy(\.available))
    }

    @MainActor func testUnchangedActivationStillCancelsAnUnrelatedFocusRequest() {
        let gate = Locked<UInt64>(0)
        let catalogue = BrowserCatalogue(focusGate:gate,observesSystem:false)
        var preferences = BrowserPreferences()
        preferences.enabled = false
        catalogue.configure(preferences)
        catalogue.expectFocusForTesting(.chrome)

        // Both old and new activeBrowser are nil, and browser tabs are disabled.
        catalogue.activateBrowserForTesting(nil)

        XCTAssertEqual(gate.withValue { $0 },1)
        catalogue.activateBrowserForTesting(nil)
        XCTAssertEqual(gate.withValue { $0 },1,"The completed cancellation must not repeat.")
    }
}
