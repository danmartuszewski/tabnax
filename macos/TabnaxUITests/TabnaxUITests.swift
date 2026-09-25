import XCTest

final class TabnaxUITests: XCTestCase {
    @MainActor func testPreviewTargetsAndImmediateOverflow() {
        let app = XCUIApplication(); app.launchArguments = ["--demo","--mode","shore","--test-domain","pl.tabnax.tests.\(UUID().uuidString)"]; app.launch()
        let first = app.buttons["target-j"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["target-pj"].exists)
        app.typeText("pj")
        XCTAssertFalse(first.waitForExistence(timeout: 1))
        app.terminate()
    }
    @MainActor func testPrefixEscapeThenCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--demo","--mode","shore","--test-domain","pl.tabnax.tests.\(UUID().uuidString)"]; app.launch()
        XCTAssertTrue(app.buttons["target-j"].waitForExistence(timeout: 5))
        app.typeText("p")
        XCTAssertTrue(app.buttons["target-pj"].waitForExistence(timeout:3))
        XCTAssertFalse(app.buttons["target-j"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["target-j"].waitForExistence(timeout:3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.buttons["target-j"].exists)
        app.terminate()
    }
}

final class NativeSettingsUITests: XCTestCase {
    /// Theme tiles are lazy and below the spotlight controls. Scroll the settings
    /// column before querying/clicking them, including after relaunch and resets.
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, down: Bool = true) {
        app.activate()
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 5))
        let column = app.scrollViews.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
        for _ in 0..<18 {
            if element.exists && element.isHittable, let viewport = column?.frame,
               element.frame.minY >= viewport.minY + 8, element.frame.maxY <= viewport.maxY - 8 { return }
            column?.scroll(byDeltaX: 0, deltaY: down ? -240 : 240)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)")
    }
    @MainActor func testCompactDraftValidationAndActionsSurviveEveryTab() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings","--compact","--pane","1","--test-domain","pl.tabnax.tests.\(UUID())"]
        app.launch()
        let alphabet = app.textFields["selection-alphabet"]
        XCTAssertTrue(alphabet.waitForExistence(timeout:5))
        alphabet.click(); alphabet.typeKey("a",modifierFlags:.command); alphabet.typeText("ABCDEF")
        let apply = app.buttons["apply-labels"]
        for pane in [5,2,3,4,0,1] {
            let tab = app.buttons["settings-pane-\(pane)"]
            XCTAssertTrue(tab.isHittable); tab.click()
            XCTAssertTrue(apply.isHittable)
            XCTAssertTrue(apply.isEnabled)
            XCTAssertTrue(app.buttons["Discard"].isHittable)
            if pane == 2 || pane == 3 { XCTAssertFalse(app.popUpButtons["display-mode"].isEnabled) }
        }
        alphabet.click(); alphabet.typeKey("a",modifierFlags:.command); alphabet.typeText("ABC")
        XCTAssertFalse(apply.isEnabled)
        XCTAssertTrue((app.staticTexts["selection-error"].value as? String ?? "").contains("6–26"))
        app.buttons["settings-pane-5"].click()
        XCTAssertFalse(apply.isEnabled)
        app.buttons["Discard"].click()
        XCTAssertFalse(apply.exists)
        app.buttons["settings-pane-1"].click()
        XCTAssertEqual(alphabet.value as? String,"JKLUIONMHP")
        app.terminate()
    }

    @MainActor func testThemePickerSavesAndRestoresEveryPreset() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings", "--pane", "3", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        for preset in ["graphite", "tabnax", "sage", "iris", "glass", "liquidGlass"] {
            let button = app.buttons["theme-\(preset)"]
            reveal(button, in: app)
            button.click()
            XCTAssertEqual(button.value as? String, "Selected")
            XCTAssertTrue(app.buttons["target-m"].exists, "Switching a theme must keep the preview targets.")
        }
        app.terminate(); app.launch()
        let saved = app.buttons["theme-liquidGlass"]
        reveal(saved, in: app)
        XCTAssertEqual(saved.value as? String, "Selected")
        XCTAssertTrue(app.buttons["target-m"].exists)
        app.terminate()
    }

    @MainActor private func chooseMode(_ name: String, in app: XCUIApplication) {
        reveal(app.popUpButtons["display-mode"],in:app,down:false)
        app.popUpButtons["display-mode"].click()
        let item = app.menuItems.matching(identifier:name).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(item, "Visible mode menu item missing: \(name)")
        item?.click()
    }
    @MainActor private func visibleTarget(in app: XCUIApplication) -> XCUIElement? {
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'target-'")).allElementsBoundByIndex.first { $0.isHittable }
    }

    @MainActor func testCommandTabShortcutChoiceRecordingAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings","--test-domain","pl.tabnax.tests.\(UUID())"]; app.launch()
        let commandTab = app.buttons["Use ⌘ Tab"]
        XCTAssertTrue(commandTab.waitForExistence(timeout:5)); commandTab.click()
        XCTAssertEqual(app.staticTexts["activation-shortcut"].value as? String,"⌘ Tab")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["activation-shortcut"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["activation-shortcut"].value as? String,"⌘ Tab")
        app.buttons["Use ⌃⌥ Space"].click()
        XCTAssertEqual(app.staticTexts["activation-shortcut"].value as? String,"⌃⌥ Space")
        let recorder = app.buttons["record-shortcut"]
        recorder.click(); app.staticTexts["activation-shortcut"].typeKey("k",modifierFlags:[.control,.shift])
        XCTAssertEqual(app.staticTexts["activation-shortcut"].value as? String,"⌃⇧ K")
        recorder.click(); app.staticTexts["activation-shortcut"].typeKey(.escape,modifierFlags:[])
        XCTAssertEqual(app.staticTexts["activation-shortcut"].value as? String,"⌃⇧ K")
        XCTAssertEqual(recorder.label,"Record shortcut…")
        app.terminate()
    }
    @MainActor func testAllPanesSelectionRecoveryAndPersistence() {
        let app = XCUIApplication()
        let domain = "pl.tabnax.tests.\(UUID().uuidString)"
        app.launchArguments = ["--settings","--test-domain",domain]; app.launch()
        XCTAssertTrue(app.buttons["settings-pane-0"].waitForExistence(timeout:5))
        for i in [1,5,2,3,4,0] { app.buttons["settings-pane-\(i)"].click(); XCTAssertTrue(app.windows["settings"].exists) }
        app.buttons["settings-pane-1"].click()
        let alphabet = app.textFields["selection-alphabet"]
        XCTAssertTrue(alphabet.waitForExistence(timeout:3))
        alphabet.click(); alphabet.typeKey("a",modifierFlags:.command); alphabet.typeText("QWERTY")
        XCTAssertTrue(app.buttons["selection-restore-order"].isEnabled)
        app.buttons["selection-restore-order"].click()
        XCTAssertEqual(alphabet.value as? String,"JKLUIONMHP")
        alphabet.click(); alphabet.typeKey("a",modifierFlags:.command); alphabet.typeText("QWERTY")
        XCTAssertFalse(app.checkBoxes["app-shortcuts-enabled"].exists)
        XCTAssertFalse(app.textFields["Complete letters"].exists)
        XCTAssertFalse(app.buttons["Preview pin"].exists)
        app.buttons["settings-pane-5"].click()
        XCTAssertFalse(app.textFields["selection-alphabet"].exists)
        app.checkBoxes["app-shortcuts-enabled"].click()
        app.buttons["settings-pane-0"].click()
        let apply = app.buttons["apply-labels"]
        XCTAssertTrue(apply.exists); apply.click()
        app.terminate(); app.launch(); app.buttons["settings-pane-1"].click()
        XCTAssertEqual(app.textFields["selection-alphabet"].value as? String,"QWERTY")
        app.buttons["settings-pane-5"].click()
        XCTAssertEqual((app.checkBoxes["app-shortcuts-enabled"].value as? NSNumber)?.intValue,1)
        app.checkBoxes["app-shortcuts-enabled"].click()
        app.buttons["settings-pane-1"].click(); app.buttons["Discard"].click()
        app.buttons["settings-pane-5"].click()
        XCTAssertEqual((app.checkBoxes["app-shortcuts-enabled"].value as? NSNumber)?.intValue,1)
        app.terminate()
    }
}

extension NativeSettingsUITests {
    @MainActor func testPositionPreviewTracksModeAnchorDisplayAndReset() {
        let app = XCUIApplication(); let domain = "pl.tabnax.tests.\(UUID())"
        app.launchArguments = ["--settings","--pane","2","--test-domain",domain]; app.launch()
        XCTAssertTrue(app.buttons["anchor-topLeft"].waitForExistence(timeout:5))
        for mode in ["Shore","Beacons","Canopy","Lattice","Fold","Relay"] {
            chooseMode(mode,in:app)
            app.buttons["anchor-topLeft"].click()
            XCTAssertTrue((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("Top left"),mode)
        }
        app.popUpButtons["position-display"].click(); app.menuItems["Main display"].click()
        XCTAssertTrue((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("Main display"))
        reveal(app.sliders["position-inset"],in:app)
        app.sliders["position-inset"].coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).click()
        XCTAssertFalse((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("24 pt"))
        reveal(app.buttons["anchor-bottomRight"],in:app,down:false)
        app.buttons["anchor-bottomRight"].click()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["position-preview-caption"].waitForExistence(timeout:5))
        XCTAssertTrue((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("Bottom right"))
        reveal(app.buttons["position-reset"],in:app)
        app.buttons["position-reset"].click()
        XCTAssertTrue((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("Middle right"))
        XCTAssertTrue((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("24 pt"))
        chooseMode("Shore",in:app)
        XCTAssertTrue((app.staticTexts["position-preview-caption"].value as? String ?? "").contains("Top left"))
        app.terminate()
    }
    @MainActor func testRealSwitcherShowsWindowsAndAppsAsPeers() {
        let app = XCUIApplication(); app.launchArguments = ["--demo","--mode","shore","--test-domain","pl.tabnax.tests.\(UUID())"]; app.launch()
        XCTAssertTrue(app.buttons["target-j"].waitForExistence(timeout:5))
        app.terminate()
    }
    @MainActor func testSixModeBrowserTabPreviews() {
        let app = XCUIApplication(); app.launchArguments = ["--settings","--pane","3","--test-domain","pl.tabnax.tests.\(UUID().uuidString)"]; app.launch()
        XCTAssertTrue(app.popUpButtons["display-mode"].waitForExistence(timeout:5))
        for mode in ["Shore","Beacons","Canopy","Lattice","Fold","Relay"] {
            chooseMode(mode,in:app)
            // Search uses the actual native layout and exposes real sample browser
            // tabs even when the direct view starts on a different app/overflow branch.
            let search = app.searchFields["switcher-search"]
            // A layout can preserve the previous search. Its native field has an
            // internal Search button too, so only use the toolbar while in direct mode.
            if !search.exists { app.buttons["Search"].click() }
            XCTAssertTrue(search.waitForExistence(timeout:3))
            search.click(); search.typeKey("a", modifierFlags: .command); search.typeText("Arc Assets")
            let tabs = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'target-' AND label CONTAINS 'Arc' AND label CONTAINS 'Assets'"))
            XCTAssertGreaterThan(tabs.count,0,"Browser tab missing in \(mode)")

        }
        app.terminate()
    }
    @MainActor func testMouseOffAndWheelNeverCommitPreview() {
        let app = XCUIApplication(); app.launchArguments = ["--settings","--test-domain","pl.tabnax.tests.\(UUID().uuidString)"]; app.launch()
        let popup = app.popUpButtons["mouse-control"]
        XCTAssertTrue(popup.waitForExistence(timeout:5)); popup.click(); app.menuItems["Off"].click()
        XCTAssertNotNil(visibleTarget(in:app)); visibleTarget(in:app)?.click()
        XCTAssertFalse(app.staticTexts["Preview selection accepted"].exists)
        popup.click(); app.menuItems["Click + wheel selection"].click()
        visibleTarget(in:app)?.scroll(byDeltaX:0,deltaY:-80)
        XCTAssertFalse(app.staticTexts["Preview selection accepted"].exists)
        XCTAssertNotEqual(app.buttons["target-j"].value as? String,"Selected")
        XCTAssertNotNil(visibleTarget(in:app)); visibleTarget(in:app)?.click()
        XCTAssertTrue(app.staticTexts["Preview selection accepted"].exists)
        app.terminate()
    }
}

extension NativeSettingsUITests {
    @MainActor func testAppAssignmentPickerLetterApplyPersistenceAndOffSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings","--pane","5","--test-domain","pl.tabnax.tests.\(UUID())"]; app.launch()
        let enabled = app.checkBoxes["app-shortcuts-enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["add-app-assignment"].isEnabled)
        enabled.click(); app.checkBoxes["launch-closed-apps"].click()
        app.buttons["add-app-assignment"].click()
        app.typeKey("g",modifierFlags:[.command,.shift])
        app.typeText("/System/Applications/TextEdit.app")
        app.typeKey(.return,modifierFlags:[])
        let add = app.buttons["OKButton"]
        XCTAssertTrue(add.waitForExistence(timeout:3)); add.click()
        let letter = app.menuButtons["app-letter-com.apple.TextEdit"]
        XCTAssertTrue(letter.waitForExistence(timeout:5)); letter.click(); app.menuItems["T"].click()
        XCTAssertFalse(app.buttons["target-t"].exists, "Closed assigned apps stay hidden while their letters remain available.")
        XCTAssertTrue(app.buttons["apply-labels"].isEnabled); app.buttons["apply-labels"].click()
        app.terminate(); app.launch()
        XCTAssertTrue(app.menuButtons["app-letter-com.apple.TextEdit"].waitForExistence(timeout:5))
        XCTAssertEqual((app.checkBoxes["app-shortcuts-enabled"].value as? NSNumber)?.intValue,1)
        XCTAssertEqual((app.checkBoxes["launch-closed-apps"].value as? NSNumber)?.intValue,1)
        XCTAssertFalse(app.buttons["target-t"].exists, "Closed assigned apps stay hidden while their letters remain available.")
        app.checkBoxes["launch-closed-apps"].click(); XCTAssertFalse(app.buttons["target-t"].exists)
        app.buttons["Discard"].click(); XCTAssertFalse(app.buttons["target-t"].exists, "Closed assigned apps stay hidden while their letters remain available.")
        app.checkBoxes["app-shortcuts-enabled"].click(); app.buttons["apply-labels"].click()
        XCTAssertFalse(app.buttons["add-app-assignment"].isEnabled)
        XCTAssertTrue(app.menuButtons["app-letter-com.apple.TextEdit"].exists)
        app.terminate()
    }
}

extension NativeSettingsUITests {
    @MainActor func testBrowserSettingsDisableSubsetRangeAndPersistence() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings","--pane","4","--test-domain","pl.tabnax.tests.\(UUID())"]; app.launch()
        let enabled = app.checkBoxes["Include browser tabs"]
        XCTAssertTrue(enabled.waitForExistence(timeout:5))
        let source = app.popUpButtons["browser-source"], range = app.popUpButtons["browser-range"]
        XCTAssertFalse(app.checkBoxes["browser-arc"].isEnabled)
        source.click()
        let choice = app.menuItems.matching(identifier:"Choose browsers…").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(choice); choice?.click()
        let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:app.checkBoxes["browser-arc"])
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed)
        XCTAssertEqual(source.value as? String,"Choose browsers…")
        app.checkBoxes["browser-zen"].click()
        range.click(); app.menuItems["Active browser window"].click()
        enabled.click()
        XCTAssertFalse(source.isEnabled); XCTAssertFalse(range.isEnabled)
        XCTAssertFalse(app.checkBoxes["browser-arc"].isEnabled)
        app.terminate(); app.launch()
        XCTAssertTrue(enabled.waitForExistence(timeout:5))
        XCTAssertEqual((enabled.value as? NSNumber)?.intValue,0)
        enabled.click()
        XCTAssertEqual((app.checkBoxes["browser-zen"].value as? NSNumber)?.intValue,0)
        XCTAssertEqual(range.value as? String,"Active browser window")
        app.buttons["Restore defaults…"].click(); app.sheets.buttons["Restore defaults"].click()
        XCTAssertEqual(range.value as? String,"All included browsers")
        XCTAssertFalse(app.checkBoxes["browser-arc"].isEnabled)
        app.terminate()
    }
    @MainActor func testAppearanceThemesUndoAndResetRemainUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings","--pane","3","--test-domain","pl.tabnax.tests.\(UUID())"]; app.launch()
        reveal(app.buttons["theme-iris"], in: app)
        for name in ["tabnax", "sage", "iris", "glass", "liquidGlass", "graphite"] {
            app.buttons["theme-\(name)"].click()
            XCTAssertEqual(app.buttons["theme-\(name)"].value as? String,"Selected")
        }
        app.buttons["theme-iris"].click()
        app.buttons["Undo"].click()
        XCTAssertEqual(app.buttons["theme-graphite"].value as? String,"Selected")
        app.buttons["theme-sage"].click()
        let appearance = app.radioButtons
        reveal(appearance["Dark"], in: app, down: false)
        appearance["Dark"].click()
        app.terminate(); app.launch()
        reveal(app.buttons["theme-sage"], in: app)
        XCTAssertEqual(app.buttons["theme-sage"].value as? String,"Selected")
        XCTAssertEqual((appearance["Dark"].value as? NSNumber)?.intValue,1)
        reveal(appearance["Light"], in: app, down: false)
        appearance["Light"].click()
        app.buttons["Restore defaults…"].click(); app.sheets.buttons["Restore defaults"].click()
        reveal(app.buttons["theme-graphite"], in: app)
        XCTAssertEqual(app.buttons["theme-graphite"].value as? String,"Selected")
        XCTAssertEqual((appearance["System"].value as? NSNumber)?.intValue,1)
        app.terminate()
    }
}

extension TabnaxUITests {
    @MainActor func testMouseSearchDoneAndPrefixBackKeepKeyboardSelectionUsable() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--mode", "shore", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        let searchButton = app.buttons["begin-search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.click()
        let search = app.searchFields["switcher-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.typeText("Review")
        XCTAssertTrue(app.buttons["target-po"].exists)
        searchButton.click()
        XCTAssertFalse(search.exists)
        app.typeText("p")
        let back = app.buttons["back-prefix"]
        XCTAssertTrue(back.waitForExistence(timeout: 3)); back.click()
        XCTAssertTrue(app.buttons["target-j"].exists)
        app.buttons["close-switcher"].click()
        XCTAssertFalse(app.buttons["target-j"].exists)
        app.terminate()
    }
}

extension TabnaxUITests {
    @MainActor func testWindowActionsMenuAndSearchInEveryMode() {
        for mode in ["shore", "beacons", "canopy", "lattice", "fold", "relay"] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--mode", mode, "--test-domain", "pl.tabnax.tests.\(UUID())"]
            app.launch()
            let button = app.buttons["switcher-actions"]
            XCTAssertTrue(button.waitForExistence(timeout: 5)); XCTAssertTrue(button.isHittable)
            button.click()
            let close = app.menuItems["action-closeWindow"]
            XCTAssertTrue(close.waitForExistence(timeout: 3)); XCTAssertFalse(close.isEnabled)
            XCTAssertEqual(app.menuItems.matching(NSPredicate(format: "identifier == %@ AND title CONTAINS %@", "action-closeWindow", "—")).count, 1, "Unavailable actions explain why")
            XCTAssertTrue(app.menuItems["action-toggleFullscreen"].exists)
            let menuEvidence = XCTAttachment(string: app.menuItems.matching(NSPredicate(format: "identifier BEGINSWITH 'action-'")).debugDescription)
            menuEvidence.name = "Window actions \(mode)"; menuEvidence.lifetime = .keepAlways; add(menuEvidence)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(button.exists, "Escape dismisses only the menu")
            app.buttons["begin-search"].click()
            let search = app.searchFields["switcher-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 3)); search.click(); search.typeText("Review")
            app.typeKey(".", modifierFlags: .command)
            XCTAssertTrue(close.waitForExistence(timeout: 3))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertEqual(search.value as? String, "Review")
            search.typeText(" changes")
            XCTAssertEqual(search.value as? String, "Review changes")
            app.buttons["begin-search"].click()
            XCTAssertTrue(button.exists)
            app.buttons["close-switcher"].click()
            XCTAssertFalse(button.exists)
            app.terminate()
        }
    }
}

extension NativeSettingsUITests {
    @MainActor func testWindowActionsSettingPersistsAndCanBeRestored() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        let toggle = app.checkBoxes["window-actions-enabled"]
        reveal(toggle, in: app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        toggle.click()
        app.terminate(); app.launch()
        reveal(toggle, in: app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        toggle.click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        app.terminate()
    }
}

extension TabnaxUITests {
    @MainActor func testFuzzyRankingAndEnterSelectTheVisibleResultInEveryMode() {
        for mode in ["shore", "beacons", "canopy", "lattice", "fold", "relay"] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--search-fixture", "--mode", mode, "--test-domain", "pl.tabnax.tests.\(UUID())"]
            app.launch(); app.activate()
            XCTAssertTrue(app.buttons["begin-search"].waitForExistence(timeout: 5))
            app.buttons["begin-search"].click()
            let search = app.searchFields["switcher-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 3)); search.click(); search.typeText("closedonly")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'target-'")).count, 0)
            search.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(search.exists, "Enter must not select an invisible closed-app result")
            search.typeKey("a", modifierFlags: .command); search.typeText("rc")
            let exactID = ["canopy", "fold"].contains(mode) ? "target-uj" : "target-i"
            let exact = app.buttons[exactID]
            XCTAssertTrue(exact.waitForExistence(timeout: 3), mode)
            XCTAssertEqual(exact.value as? String, "Selected", mode)
            XCTAssertTrue(exact.label.contains("Beta, rc"), mode)
            XCTAssertFalse(app.buttons["target-z"].exists, "The closed app must not appear or take the highlight")
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'target-'"))
            XCTAssertGreaterThan(rows.count, 1, "Abbreviated results remain available")
            let evidence = XCTAttachment(string: rows.debugDescription)
            evidence.name = "Ranked search \(mode)"; evidence.lifetime = .keepAlways; add(evidence)
            // The native editor owns text and Return; this is a real user key action.
            search.typeKey(.return, modifierFlags: [])
            XCTAssertFalse(search.waitForExistence(timeout: 1), mode)
            XCTAssertFalse(app.buttons["begin-search"].exists, "Enter commits the visible highlighted row")
            app.terminate()
        }
    }
}

extension NativeSettingsUITests {
    @MainActor func testRememberSearchChoicesRequiresOptInPersistsAndClears() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        let toggle = app.checkBoxes["remember-search-choices"]
        let clear = app.buttons["clear-search-choices"]
        reveal(toggle, in: app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        XCTAssertFalse(clear.isEnabled)
        toggle.click(); XCTAssertTrue(clear.isEnabled)
        app.terminate(); app.launch(); reveal(toggle, in: app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        reveal(clear, in: app); clear.click()
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        XCTAssertTrue(app.staticTexts["Remembered search choices cleared."].exists)
        toggle.click(); app.terminate(); app.launch(); reveal(toggle, in: app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0)
        XCTAssertFalse(clear.isEnabled)
        app.terminate()
    }
}

extension NativeSettingsUITests {
    @MainActor func testAppExclusionsAndShortcutExceptionsSaveIndependentlyWithUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings", "--pane", "6", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        let field = app.textFields["app-exclusion-bundle"]
        reveal(field, in: app)
        field.click(); field.typeText("bad id")
        XCTAssertFalse(app.buttons["add-app-exclusion"].isEnabled)
        field.typeKey("a", modifierFlags: .command); field.typeText("com.apple.Safari")
        app.buttons["add-app-exclusion"].click()
        let removed = app.buttons["remove-app-exclusion-com.apple.Safari"]
        XCTAssertTrue(removed.waitForExistence(timeout: 3))
        let previewSafari = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'target-' AND label CONTAINS 'Safari'"))
        XCTAssertEqual(previewSafari.count, 0)
        let exception = app.textFields["shortcut-exception-bundle"]
        reveal(exception, in: app)
        exception.click(); exception.typeText("test.UninstalledVM")
        let add = app.buttons["add-shortcut-exception"]
        reveal(add, in: app); add.click()
        let saved = app.buttons["remove-shortcut-exception-test.UninstalledVM"]
        reveal(saved, in: app, down: false)
        XCTAssertTrue(saved.exists)
        saved.click()
        app.buttons["Undo"].click()
        reveal(saved, in: app)
        XCTAssertTrue(saved.exists)
        app.terminate(); app.launch()
        reveal(removed, in: app)
        XCTAssertTrue(removed.exists)
        removed.click()
        XCTAssertGreaterThan(previewSafari.count, 0, "Removing an exclusion restores app rows and windows")
        reveal(saved, in: app)
        XCTAssertTrue(saved.exists, "Visibility changes cannot remove an independent shortcut exception")
        let evidence = XCTAttachment(string: app.windows["settings"].debugDescription)
        evidence.name = "Exclusions and independent saved exception"; evidence.lifetime = .keepAlways; self.add(evidence)
        app.terminate()
    }
    @MainActor func testTitleRuleValidationEditingPersistenceAndSiblingPreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings", "--pane", "6", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        let field = app.textFields["title-rule-pattern"]
        reveal(field, in: app)
        let picker = app.popUpButtons["title-rule-match"]
        picker.click(); app.menuItems["Wildcard"].click()
        field.click(); field.typeText("bad\\")
        let save = app.buttons["save-title-rule"]
        reveal(save, in: app)
        XCTAssertFalse(save.isEnabled)
        reveal(field, in: app, down: false)
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("Tabnax*")
        let bundle = app.textFields["title-rule-bundle"]
        reveal(bundle, in: app, down: false)
        bundle.click(); bundle.typeText("com.apple.dt.Xcode")
        reveal(save, in: app); save.click()
        let removed = app.buttons["remove-title-Tabnax*"]
        reveal(removed, in: app, down: false)
        XCTAssertTrue(removed.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'target-' AND label CONTAINS 'Xcode' AND label CONTAINS 'Tabnax'" )).count, 0)
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'target-' AND label CONTAINS 'Review changes'" )).count, 0)
        app.buttons["Edit title rule Tabnax*"].click()
        reveal(field, in: app)
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("Review*")
        reveal(save, in: app); save.click()
        app.terminate(); app.launch()
        let edited = app.buttons["remove-title-Review*"]
        reveal(edited, in: app)
        XCTAssertTrue(edited.exists)
        XCTAssertFalse(removed.exists)
        edited.click(); app.buttons["Undo"].click()
        reveal(edited, in: app)
        XCTAssertTrue(edited.exists)
        app.terminate()
    }
}

extension NativeSettingsUITests {
    @MainActor func testTraversalOrderChoicesPersistAndRestoreDefaults() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings", "--test-domain", "pl.tabnax.tests.\(UUID())"]
        app.launch()
        let picker = app.popUpButtons["traversal-order"]
        reveal(picker, in: app)
        XCTAssertEqual(picker.value as? String, "Stable")
        for title in ["Most recently used", "Alphabetical", "Window state"] {
            picker.click()
            let choice = app.menuItems.matching(identifier: title).allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(choice); choice?.click()
            XCTAssertEqual(picker.value as? String, title)
            app.terminate(); app.launch(); reveal(picker, in: app)
            XCTAssertEqual(picker.value as? String, title)
        }
        app.buttons["Restore defaults…"].click(); app.sheets.buttons["Restore defaults"].click()
        reveal(picker, in: app)
        XCTAssertEqual(picker.value as? String, "Stable")
        app.terminate(); app.launch(); reveal(picker, in: app)
        XCTAssertEqual(picker.value as? String, "Stable")
        app.terminate()
    }
}

extension TabnaxUITests {
    @MainActor func testOrderedSearchCyclesAndSelectsInEveryMode() {
        // This isolated fixture has Alpha's "Really cool notes" after "Remote
        // configuration" in catalogue order. Alphabetical order reverses the tie.
        for mode in ["shore", "beacons", "canopy", "lattice", "fold", "relay"] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--search-fixture", "--order", "alphabetical", "--mode", mode, "--test-domain", "pl.tabnax.tests.\(UUID())"]
            app.launch(); app.activate()
            XCTAssertTrue(app.buttons["begin-search"].waitForExistence(timeout: 5))
            app.buttons["begin-search"].click()
            let search = app.searchFields["switcher-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 3)); search.click(); search.typeText("Alpha")
            let grouped = ["canopy", "fold"].contains(mode)
            let appRow = app.buttons["target-j"]
            if !grouped {
                XCTAssertEqual(appRow.value as? String, "Selected")
                search.typeKey(.downArrow, modifierFlags: [])
            }
            let first = app.buttons[grouped ? "target-jk" : "target-l"]
            let second = app.buttons[grouped ? "target-jj" : "target-k"]
            XCTAssertTrue(first.waitForExistence(timeout: 3)); XCTAssertTrue(first.label.contains("Really cool notes"))
            XCTAssertEqual(first.value as? String, "Selected")
            search.typeKey(.downArrow, modifierFlags: [])
            XCTAssertEqual(second.value as? String, "Selected")
            search.typeKey(.upArrow, modifierFlags: [])
            XCTAssertEqual(first.value as? String, "Selected")
            let evidence = XCTAttachment(string: app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'target-'")).debugDescription)
            evidence.name = "Alphabetical traversal \(mode)"; evidence.lifetime = .keepAlways; add(evidence)
            search.typeKey(.return, modifierFlags: [])
            XCTAssertFalse(app.buttons["begin-search"].exists)
            app.terminate()
        }
    }
}

extension NativeSettingsUITests {
    @MainActor func testSearchShortcutOptInRecordingValidationPersistenceAndReset() {
        let app = XCUIApplication()
        app.launchArguments = ["--settings","--test-domain","pl.tabnax.tests.\(UUID())"]; app.launch()
        let enabled = app.checkBoxes["search-shortcut-enabled"], record = app.buttons["record-search-shortcut"]
        reveal(enabled,in:app); XCTAssertEqual((enabled.value as? NSNumber)?.intValue,0); enabled.click()
        XCTAssertEqual((enabled.value as? NSNumber)?.intValue,1)
        reveal(record,in:app); record.click()
        app.typeKey("k",modifierFlags:.shift)
        XCTAssertTrue(app.staticTexts["search-shortcut-recording-hint"].exists)
        app.typeKey(.space,modifierFlags:[.control,.option])
        XCTAssertTrue(app.staticTexts["search-shortcut-recording-hint"].exists, "Conflicting main chord must not be saved")
        app.typeKey("k",modifierFlags:[.control,.shift])
        XCTAssertEqual(app.staticTexts["search-activation-shortcut"].value as? String,"⌃⇧ K")
        record.click(); app.typeKey(.escape,modifierFlags:[])
        XCTAssertEqual(app.staticTexts["search-activation-shortcut"].value as? String,"⌃⇧ K")
        app.terminate(); app.launch(); reveal(enabled,in:app)
        XCTAssertEqual((enabled.value as? NSNumber)?.intValue,1)
        XCTAssertEqual(app.staticTexts["search-activation-shortcut"].value as? String,"⌃⇧ K")
        let reset = app.buttons["reset-search-shortcut"]; reveal(reset,in:app); reset.click()
        XCTAssertEqual(app.staticTexts["search-activation-shortcut"].value as? String,"⌃⇧ Space")
        XCTAssertEqual((enabled.value as? NSNumber)?.intValue,1)
        reveal(enabled,in:app); enabled.click()
        app.terminate(); app.launch(); reveal(enabled,in:app)
        XCTAssertEqual((enabled.value as? NSNumber)?.intValue,0)
        reveal(app.staticTexts["activation-shortcut"],in:app,down:false)
        XCTAssertEqual(app.staticTexts["activation-shortcut"].value as? String,"⌘ Tab")
        app.terminate()
    }
}

extension TabnaxUITests {
    @MainActor func testSearchShortcutImmediateTypingRepeatAndEscapeInEveryLayoutAndPath() {
        for fallback in [false,true] {
            for mode in ["shore","beacons","canopy","lattice","fold","relay"] {
                let app = XCUIApplication()
                app.launchArguments = ["--demo","--mode",mode,"--test-search-shortcut","--test-domain","pl.tabnax.tests.\(UUID())"] + (fallback ? ["--test-fallback"] : [])
                app.launch(); app.activate()
                let sink = app.textFields["shortcut-fixture-sink"]
                XCTAssertTrue(sink.waitForExistence(timeout:5)); sink.click()
                app.typeKey(.space,modifierFlags:[.control,.shift]); app.typeText("InputRouter")
                let search = app.searchFields["switcher-search"]
                XCTAssertTrue(search.waitForExistence(timeout:3),"\(mode), fallback=\(fallback)")
                XCTAssertEqual(search.value as? String,"InputRouter")
                XCTAssertEqual(sink.value as? String,"")
                app.typeKey(.space,modifierFlags:[.control,.shift])
                XCTAssertEqual(search.value as? String,"InputRouter", "Repeated invocation preserves native editor text")
                app.typeKey(.escape,modifierFlags:[])
                XCTAssertFalse(search.exists)
                app.typeKey(.escape,modifierFlags:[])
                sink.click(); app.typeKey(.space,modifierFlags:[.control,.shift]); app.typeText("InputRouter")
                XCTAssertTrue(search.waitForExistence(timeout:3))
                app.typeKey(.return,modifierFlags:[])
                XCTAssertFalse(search.waitForExistence(timeout:1))
                XCTAssertTrue((app.staticTexts["shortcut-fixture-result"].value as? String ?? "").contains("InputRouter"))
                XCTAssertEqual(sink.value as? String,"")
                app.terminate()
            }
        }
    }
}

extension NativeSettingsUITests {
    @MainActor func testSimultaneousDisplayOptInPersistsAcrossModesAndPositionReset() {
        let app = XCUIApplication(); app.launchArguments = ["--settings","--pane","2","--test-domain","pl.tabnax.tests.\(UUID())"]
        app.launch(); defer { app.terminate() }
        let toggle = app.checkBoxes["position-all-displays"]
        reveal(toggle,in:app); XCTAssertEqual((toggle.value as? NSNumber)?.intValue,0); toggle.click()
        app.terminate(); app.launch(); reveal(toggle,in:app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue,1)
        chooseMode("Beacons",in:app); reveal(toggle,in:app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue,1)
        // Position uses an illustration and must not open any external switcher panels.
        XCTAssertEqual(app.windows.matching(NSPredicate(format:"identifier BEGINSWITH 'switcher'")).count,0)
        toggle.click(); app.terminate(); app.launch(); reveal(toggle,in:app)
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue,0)
    }
}
extension TabnaxUITests {
    @MainActor func testSimultaneousSearchTypingMenusAndSelectionAcrossConnectedDisplays() throws {
        for mode in ["shore","beacons","canopy","lattice","fold","relay"] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo","--mode",mode,"--test-search-shortcut","--all-displays","--test-domain","pl.tabnax.tests.\(UUID())"]
            app.launch(); app.activate()
            let sink = app.textFields["shortcut-fixture-sink"]
            XCTAssertTrue(sink.waitForExistence(timeout:5)); sink.click()
            let count = Int(app.staticTexts["shortcut-fixture-display-count"].value as? String ?? "0") ?? 0
            guard count > 1 else { app.terminate(); throw XCTSkip("UI simultaneous-display check requires connected monitors") }
            app.typeKey(.space,modifierFlags:[.control,.shift]); app.typeText("Input")
            let fields = app.searchFields.matching(identifier:"switcher-search")
            XCTAssertTrue(fields.firstMatch.waitForExistence(timeout:3)); XCTAssertEqual(fields.count,count)
            let copies = fields.allElementsBoundByIndex.sorted { $0.frame.minX < $1.frame.minX }
            for copy in copies { XCTAssertEqual(copy.value as? String,"Input") }
            // Transfer to a different physical screen and type immediately after the click.
            copies[0].click(); app.typeKey(.end,modifierFlags:[]); app.typeText("Router")
            for copy in copies { XCTAssertEqual(copy.value as? String,"InputRouter",mode) }
            copies[copies.count-1].click(); app.typeKey(.end,modifierFlags:[]); app.typeText(".swift")
            for copy in copies { XCTAssertEqual(copy.value as? String,"InputRouter.swift",mode) }
            app.typeKey(.space,modifierFlags:[.control,.shift])
            XCTAssertEqual(copies.last?.value as? String,"InputRouter.swift")
            // Every footer owns an action menu; opening it must preserve the shared query.
            let actions = app.buttons.matching(identifier:"switcher-actions").allElementsBoundByIndex
            XCTAssertEqual(actions.count,count)
            for action in actions {
                action.click()
                let close = app.menuItems["action-closeWindow"]
                XCTAssertTrue(close.waitForExistence(timeout:2),mode)
                app.typeKey(.escape,modifierFlags:[])
                for copy in copies { XCTAssertEqual(copy.value as? String,"InputRouter.swift") }
            }
            // Wheel gestures in each bank stay inside the session and cannot commit it.
            for scroll in app.scrollViews.allElementsBoundByIndex {
                scroll.scroll(byDeltaX:0,deltaY:-60)
                XCTAssertEqual(fields.count,count)
                XCTAssertEqual(app.staticTexts["shortcut-fixture-selection-count"].value as? String,"0")
            }
            let evidence = XCTAttachment(string: copies.map { "\($0.frame): \($0.value ?? "")" }.joined(separator:"\n"))
            evidence.name = "Simultaneous search \(mode)"; evidence.lifetime = .keepAlways; add(evidence)
            copies[0].click(); app.typeKey(.return,modifierFlags:[])
            XCTAssertFalse(fields.firstMatch.waitForExistence(timeout:1))
            XCTAssertEqual(app.staticTexts["shortcut-fixture-selection-count"].value as? String,"1")
            XCTAssertTrue((app.staticTexts["shortcut-fixture-result"].value as? String ?? "").contains("InputRouter"))
            XCTAssertEqual(sink.value as? String,"")
            // Reopen, leave search from another copy and dismiss every surface together.
            sink.click(); app.typeKey(.space,modifierFlags:[.control,.shift])
            XCTAssertTrue(fields.firstMatch.waitForExistence(timeout:3))
            fields.allElementsBoundByIndex.last?.click(); app.typeKey(.escape,modifierFlags:[])
            XCTAssertFalse(fields.firstMatch.exists)
            let dismiss = app.buttons.matching(identifier:"close-switcher")
            XCTAssertEqual(dismiss.count,count); dismiss.allElementsBoundByIndex.last?.click()
            XCTAssertFalse(dismiss.firstMatch.exists)
            XCTAssertEqual(app.staticTexts["shortcut-fixture-selection-count"].value as? String,"1")
            app.terminate()
        }
    }
}
