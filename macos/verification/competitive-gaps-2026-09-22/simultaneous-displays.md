# Simultaneous display switcher

Implemented in the existing untracked checkout on 2026-09-22, preserving all five previous tasks. No staging, commits, history changes, worktrees, installation/deployment, real settings, permission or login-registration changes. The coordinator README and original KB analysis remain untouched.

## Delivered

- Position → **Show simultaneously on every display**, off by default, including absent/malformed schema-v1 values. The existing Show on choice selects initial input ownership. Per-mode anchor/inset and theme remain shared; each panel clamps to its own usable AppKit bounds. Embedded/settings/export previews remain single.
- A single coordinator with non-recursive surface renderers publishes the same selection, direct addresses, prefix/query, fuzzy ranking, exclusions, frozen ordering and actions to every copy. Every bank/plaque is included in the router's mouse regions; each panel handles native keyboard, mouse, hover, wheel and menus.
- One native editor/input owner. Clicking another copy completes marked text in the old editor and transfers its current string and selection before the destination accepts input. Query edit revisions acknowledge asynchronous/coalesced updates, including repeated text and the 1,024-character limit; older publications cannot overwrite immediate typing after handoff. Repeated search activation preserves the current owner and editor.
- Exclusive native action/help menu tracking across all copies; pointer-down disarms release selection. Peer hover/selection and desktop spotlight pause while a menu owns input. Menu commands retain exact IDs/session guards. Accepted action outcomes appear everywhere; stale outcomes and delayed menu callbacks cannot reopen a dismissed session.
- Beacons repeats its complete target bank and creates each physical plaque once, using separate bank/plaque rows and avoiding every bank footprint. Desktop spotlight has one controller across the desktop. Dismissal closes all banks, plaques and spotlight surfaces. Display changes and wake cancel the router/focus session; reopening uses the current display inventory, including addition/removal, negative coordinates and mixed scaling. An empty display inventory cannot create an offscreen panel.

## Changed paths in this task

- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Settings.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Selection.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/SettingsTests.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/SearchTests.swift`
- `macos/Tabnax/ModePresenter.swift`
- `macos/Tabnax/DesktopSpotlight.swift`
- `macos/Tabnax/AppDelegate.swift`
- `macos/Tabnax/SettingsController.swift`
- `macos/TabnaxTests/NativeContractTests.swift`
- `macos/TabnaxUITests/TabnaxUITests.swift`
- `macos/README.md`, `macos/MODE-COVERAGE.md`, `docs/ARCHITECTURE.md`
- This record, `connected-displays.json`, and `display-0.png` / `display-1.png` / `display-2.png` (fictional, app-owned Fold renders).

## Verification

- **`make check`: passed**, including publication/local-link policy, Python tests, browser companion/Safari transport and settings model checks. Log: `/tmp/tabnax-final-check.log`.
- **`make test-native`: passed — 124 core tests; 155 native tests executed, 154 passed / 1 Accessibility-dependent skip / zero failures.** This cumulative run includes all prior action, fuzzy-search, exclusion, ordering and dedicated-shortcut work, plus eight new multi-display native tests and two new core tests. Log: `/tmp/tabnax-final-native.log`. Bundle: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_18-15-09-+0200.xcresult`.
- **Targeted UI: 2 passed / zero failures**, covering settings opt-in/persistence and all six layouts on all three physical displays, with native action menus, wheel regions, transfer typing and single selection. Log: `/tmp/tabnax-multi-ui-final.log`. Bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_18-10-11-+0200.xcresult`.
- Focused native iteration: eight tests passed for multi-display behavior and existing first-frame submission; after adding query edit revisions, the three affected query/topology tests passed. Final full native coverage includes those revisions. Logs: `/tmp/tabnax-multi-targeted-final.log`, `/tmp/tabnax-multi-revisions.log`.
- First complete UI run: **25 tests passed / 1 Position navigation test failed (three assertions)**. The added controls/help made the slider and final mode picker require explicit scrolling. The test now reuses the fully-visible-control reveal helper for the inset slider, anchor, reset button and mode picker; it passed alone afterward. Log: `/tmp/tabnax-position-ui-fix.log`. Targeted bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_18-29-43-+0200.xcresult`.
- **Final complete UI suite: 26 passed / zero failures / zero skips**, run alone after the targeted Position repair. This includes all prior settings and switching features, both shortcut paths × all six layouts, and the new three-display flow. Product code is unchanged from the passing core/native gate. Log: `/tmp/tabnax-final-ui-complete.log`. Bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_18-30-56-+0200.xcresult`. The initial full run is retained in `/tmp/tabnax-final-ui.log` / `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_18-15-52-+0200.xcresult`.

Native coverage includes all six layouts × nine anchors × three synthetic screens, shared exact target/address lists and ranked search, exclusions and browser ownership, recent ordering, editor ownership, marked-text handoff, deferred query publications, repeated/truncated queries, prefix and exact pointer selection, exclusive menus/stale completion, default/embedded single presentation, topology changes and complete dismissal.

Actual connected-display checks use real visible NSWindows on three displays (IDs 3, 1 and 2; backing scales 1×, 2× and 2×, including negative origins). For every mode they assert panel count, each window's reported NSScreen ID/frame, bounds containment, one editor, shared `rc` query/highlight, unique desktop spotlight and Beacons surfaces, exact selection from a secondary copy and complete dismissal. `connected-displays.json` contains the measured frames. The three app-owned Fold PNGs were visually inspected: identical targets, direct addresses, highlight, search and footer; raster resolution follows each display's backing scale. These renders contain only app-owned views.

UI checks use `--demo --test-search-shortcut --all-displays --test-domain pl.tabnax.tests.<UUID>`, the actual router/presenter and fictional targets. They cover the opt-in settings persistence, all six layouts on every connected screen, immediate typing after clicking other copies, repeat activation, each native action menu and wheel region, exact single selection, empty background text sink and closing all copies. Accessibility text attachments record every search copy; there are no desktop screenshots in the evidence delivered here.

UI command (run alone; no concurrent native tests or app launches):

```sh
xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/UIDerivedData \
  TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting \
  -only-testing:TabnaxUITests test
```

Targeted UI used the same command with selectors `TabnaxUITests/NativeSettingsUITests/testSimultaneousDisplayOptInPersistsAcrossModesAndPositionReset` and `TabnaxUITests/TabnaxUITests/testSimultaneousSearchTypingMenusAndSelectionAcrossConnectedDisplays`. Native targeted runs used `build/DerivedData`, no UI bundle override, and `TabnaxTests/MultiDisplayContractTests` plus the existing renderer first-frame check. `make test-native` ran the complete core suite, built the independent fixture and ran all native tests.

## Corrections and limits

- Initial sandboxed Xcode dependency resolution could not write its compiler caches. Reported native/UI runs use reviewed execution permissions. Initial new-test compilation mistakes were corrected. The first UI run's 19 assertions were test mistakes: Position was queried for a native preview rather than its illustration, and menu labels were queried with the wrong capitalization. Text transfer, shared results, single selection and dismissal already passed; the corrected flow uses stable menu identifiers.
- Native tests deliberately hold query publications while transferring marked text and typing immediately. They exercise AppKit marked ranges, not a live IME candidate window. Physical alternate layouts, VoiceOver, hardware trackpad momentum and Secure Input remain separate integration checks.
- Real simultaneous presentation was verified on this host's three active displays. Physical unplug/replug, sleep/wake, mirrored-display mode and fullscreen/Spaces transitions were not induced. Topology/empty-inventory dismissal and reopening are deterministic native tests; wake hooks use public NSWorkspace notifications. Panels retain the existing public all-Spaces/fullscreen-auxiliary behavior, but those hardware/Space transitions still need manual checks before claiming empirical coverage.
- The existing controlled cross-app window-action/focus fixture requires Accessibility permission, which this host lacks. No permission was requested or changed. Real third-party close/minimize/fullscreen/focus effects remain that fixture's limitation; all new selection/actions use fictional targets or frozen command models.

Public API scope: existing nonactivating AppKit panels, `NSScreen` frames/device descriptions/backing scales, native `NSSearchField`/`NSTextView` editors and public NSWorkspace wake notifications. Wake notification availability was checked against the installed SDK's `NSWorkspace.h`; no private display/Spaces API, display reconfiguration, event posting to user apps or permission mutation was added.
