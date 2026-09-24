# Item 6 — Optional traversal ordering

Implemented on 2026-09-22 in the existing untracked checkout, preserving items 2, 3 and 5. The source audit confirmed that FocusHistory previously supplied initial highlighting/return behavior, with a special Relay current/previous presentation, but no selectable traversal order. No commits, staging, history initialization, resets, cleanup, worktrees, installation/deployment, real preference changes, permission changes or login registration. The original KB analysis was not edited. Dedicated filtering activation and simultaneous multi-display presentation remain separate tasks.

## Delivered

- General → Windows → **Traversal order**: Stable (default), Most recently used, Alphabetical, Window state. Additive schema-v1 persistence, missing/unknown/malformed values defaulting to Stable, Undo, restore-defaults and a live settings preview.
- Recency uses current exact window, then observed recent windows, then stable unknown targets/tabs/apps. No process/title/geometry identity substitution. Alphabetical uses natural app/title comparison. State uses ordinary → elsewhere → minimized → hidden → unavailable → closed, with stable ties; existing inclusion/exclusion filters still apply.
- Sorting occurs after label allocation. Every opening captures target, group and address-branch ranks plus the return/preview-origin history. Live metadata and recency updates keep those ranks; removed/excluded leading children cannot move their group or overflow cell. New targets still wait for the next opening. Selection/navigation alone never records real recency.
- Shore/Canopy/Fold/Lattice keep app groups together, using the first sorted child for group position; Stable preserves Fold's original app spine. Lattice keeps shared overflow after app-owned cells, held/empty cells in alphabet order, and unaddressed rows after the grid. Canopy lateral navigation excludes invisible closed apps from column sizes. Fold family release retains its established recent-child choice.
- Beacons keeps spatial plaques in place and makes the optional-order bank the same traversal sequence with plaque targets omitted. Strong-match search also uses a single ranked bank across windows/tabs/apps. Relay keeps two lead cards; Stable preserves current/previous, optional ordering uses the first two sorted targets. Relay Enter retains previous-window semantics; pointer/direct letters/modifier release use their exact targets.
- Fuzzy match strength and optional learned-choice bonuses retain precedence. Frozen order breaks equal-score ties; strongest matching children still rank groups. Metadata may change a search match's eligibility/strength, but cannot change its ordering tie-breaker.
- Invisible closed-app launchers no longer occupy keyboard cycling stops. Their exact direct launch letters remain available in all six modes. This corrects the pre-existing direct-view equivalent of item 3's invisible search selection issue.
- Focus discovery now captures a coordinator generation token before AX work and requires the same non-nil token on completion. A preview read cannot become real history after cancellation. Dispatched preview activation provenance also survives menu opening/cancellation and failed selection, until verified selection or a different external activation replaces it. Verified final focus outcomes still record exact observed windows; previews do not. Recency remains runtime-only (current plus at most 32 previous windows).

## Changed paths

- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Ordering.swift` (new)
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Selection.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Navigation.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Settings.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/OrderingTests.swift` (new)
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/AppShortcutTests.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/ModeTests.swift`
- `macos/Tabnax/InputRouter.swift`, `ModePresenter.swift`, `SettingsController.swift`, `AppDelegate.swift`, `FocusCoordinator.swift`, `WindowCatalogue.swift`
- `macos/TabnaxTests/NativeContractTests.swift`
- `macos/TabnaxUITests/TabnaxUITests.swift`
- `macos/README.md`, `macos/MODE-COVERAGE.md`, `macos/Packages/TabnaxCore/README.md`
- `docs/ARCHITECTURE.md`, `docs/PRIVACY.md`
- This verification record and isolated own-view renders listed below.

## Verification

- **`make check`: passed.** Log: `/tmp/tabnax-item6-check-final.log`.
- **`make test-native`: passed — 119 core tests; 137 native tests executed, 136 passed / 1 Accessibility-dependent skip / zero failures.** Log: `/tmp/tabnax-item6-native-complete.log`. Bundle: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_17-31-44-+0200.xcresult`.
- Core regressions cover all four orders/all six modes, natural numeric names, unknown and pruned history, exact selection/cycling both directions, hidden/minimized/elsewhere/unavailable/closed targets, browser ownership, group order and Canopy lateral movement, shared overflow, live metadata/history/exclusion reconciliation, direct labels, strong search ranking/ties, schema compatibility and malformed values.
- Native regressions compare rendered row/cell/spine order to traversal, cycle and accessibility-press exact rows across every order/layout, verify actual InputRouter Command–Tab cycling and modifier-release selection in both activation behaviors, settings persistence/preview/Undo, and discovery token invalidation, including cancelled menus, late preview activation and resuming real external observation. Existing appearance, action, focus, exclusion and performance tests remain passing.
- **Targeted UI: 3 passed / zero failures.** All four ordering choices, relaunch persistence and restore-defaults; real arrow-key cycling and Return selection with alphabetical ties in all six layouts; existing strong fuzzy ranking/closed-app rejection/Return flow in all six layouts. UI row accessibility descriptions are attached to the bundle. Log: `/tmp/tabnax-item6-ui.log`. Bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_17-23-28-+0200.xcresult`.
- **Native own-view renders:** rendered and visually inspected all six fictional demo layouts, after UI automation completed: `item-6-shore.png` (recent), `item-6-beacons.png` (alphabetical), `item-6-canopy.png` (state), `item-6-lattice.png` (alphabetical), `item-6-fold.png` (recent), `item-6-relay.png` (alphabetical). Stable direct labels, initial highlight, branch placement, group layouts and footer controls remain readable and aligned. Beacons exports only its own bank/plaques on a transparent canvas; no desktop capture. Renders use `--render-preview <path> --mode <mode> --order <order> --test-domain pl.tabnax.tests.<UUID>`. The order override is Debug-only and test-domain gated. Log: `/tmp/tabnax-item6-renders.log`.

UI command (run alone, after native testing finished):

```sh
xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/UIDerivedData \
  TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting \
  -only-testing:TabnaxUITests/NativeSettingsUITests/testTraversalOrderChoicesPersistAndRestoreDefaults \
  -only-testing:TabnaxUITests/TabnaxUITests/testOrderedSearchCyclesAndSelectsInEveryMode \
  -only-testing:TabnaxUITests/TabnaxUITests/testFuzzyRankingAndEnterSelectTheVisibleResultInEveryMode test
```

## Corrections and limitations

- Initial sandboxed SwiftPM execution could not start its nested sandbox. Reported test results used reviewed execution permissions and the existing isolated build/test facilities.
- Targeted iteration corrected new test assumptions about Lattice branch controls and pass-through modifier-release events. The first full run caught an accidental mode-reconfiguration session dismissal; preserving the existing configure-mode lifecycle fixed it. The next full run identified an old Beacons caption assertion, updated to expect the deliberately combined ranked “Targets” bank. Final full native checks pass, including the later review fix retaining dispatched preview provenance across cancellation and failed selection. UI tests/renders preceded that backend-only guard; UI behavior did not change.
- This host lacks Accessibility permission for the controlled cross-app fixture; it remains explicitly skipped. No permission was requested or changed. Actual focus effects on real hidden/minimized/other-Space windows are not newly verified; isolated model/router tests verify their exact identities and selection requests. Public AX/AppKit focus paths remain in place.
- No live IME composition, VoiceOver session or physical multi-display/Space transition was performed. Native field-editor and accessibility-selection paths are preserved and covered by isolated UI/native tests. Beacons' spatial plaques intentionally retain geometric placement; only their bank subsequence has a linear visual order.
- Full UI automation is reserved for the parent's final cumulative run; this item runs relevant targeted flows. No outstanding implementation follow-up is known; rerun the skipped cross-app fixture on an already authorized host before claiming empirical focus coverage.
