# Item 5 — App/window exclusions and foreground shortcut exceptions

Implemented on 2026-09-22 in the existing untracked checkout, preserving items 2 and 3. No staging, commits, history initialization, resets, cleanup, worktrees, installation/deployment, real preference changes, permission changes or login registration. The original KB analysis was not edited. Profiles, the dedicated search shortcut and ordering remain outside this item.

## Delivered

- New **Exclusions** settings pane: independent app exclusions, scoped window/tab title rules, and foreground shortcut exceptions. Choose a `.app` to read its durable bundle ID, or type an ID for a closed/uninstalled app. Duplicate/invalid IDs cannot be added. App names are display-only; IDs are exact and case-sensitive. Rules remain when an app quits, moves or is uninstalled.
- Case-insensitive literal **Contains**, whole-title **Equals**, and whole-title **Wildcard** (`*`, `?`, and escaped literal star/question mark/backslash). Spaces and accents are significant. No regex or bracket classes. Empty/whitespace-only patterns, control characters, over-256-character patterns, invalid scopes and unsupported/trailing escapes cannot be saved. Matching uses bounded-pattern dynamic programming rather than regex backtracking. Exact semantics appear in the pane and macos/README.md.
- App exclusions cover native windows, app rows, browser tabs and direct launch targets. Title rules affect individual native-window/tab titles only; sibling windows and app rows remain available. Tabs match their own titles, not a native browser window’s title, because there is no exact cross-protocol window identity to propagate that rule safely. Missing bundle IDs never borrow identity from display names; all-app title rules still work.
- Both runtime and settings preview filter after tab-owner resolution and label mapping. Reservations and exact target IDs survive exclusions, Undo and rule removal. Search, navigation, all six layouts and spotlight use the filtered snapshot. Explicitly suppressed targets are removed from an open session instead of appearing as unavailable ghosts after a title change. Native focus and launch registries reject excluded IDs.
- Schema-v1 settings remain compatible; absent lists default empty. Malformed entries are ignored independently, retaining valid siblings and unrelated preferences. Changes save immediately, dismiss the live switcher, refresh previews and support Undo. Restore defaults clears all lists.
- Reusable `ShortcutExceptionRouter` / `ShortcutExceptionGate` separates foreground policy from any particular activation shortcut. Main-actor NSWorkspace frontmost KVO and activation/deactivation/launch/termination notifications initialize policy before registration, resample actual foreground instead of trusting stale notification payloads, ignore our panels and spotlight previews, and conservatively suspend during app transitions. Same-PID activation recovery and selection of an already-previewed exception app are handled without requiring a new activation notification.
- Carbon fallback **actually unregisters**, restores on leaving the exception, rejects stale registration-generation callbacks, and waits for physical trigger-key release before registering. Deferred registration retries resample foreground too. The tap passes the original key-down/repeat/key-up sequence across rule/focus changes; previously owned sequences remain owned. Recorder precedence, modifier tracking, mouse cancellation, passive-key focus guards and manually opened switcher navigation remain intact. Unregister failures keep the registration tracked, log the error and retry.

## Changed paths

- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Exclusions.swift` (new)
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Settings.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Selection.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/ExclusionTests.swift` (new)
- `macos/Tabnax/ShortcutExceptions.swift` (new)
- `macos/Tabnax/InputRouter.swift`
- `macos/Tabnax/AppDelegate.swift`
- `macos/Tabnax/SettingsController.swift`
- `macos/Tabnax.xcodeproj/project.pbxproj`
- `macos/TabnaxTests/NativeContractTests.swift`
- `macos/TabnaxUITests/TabnaxUITests.swift`
- `macos/README.md`, `docs/ARCHITECTURE.md`
- This record and `item-5-settings.png` (fictional, app-owned native settings render).

## Verification

- **`make check`: passed**, including repository/link policy, Python, JavaScript, browser companions and settings-model checks. Log: `/tmp/tabnax-item5-check.log`.
- **`make test-native`: passed — 112 core tests; 133 native tests executed, 132 passed / 1 Accessibility-dependent skip / zero failures.** Final bundle: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_17-05-14-+0200.xcresult`. Log: `/tmp/tabnax-item5-final-native.log`.
- **New settings UI tests: 2 passed / zero failures**, run alone. Bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-59-40-+0200.xcresult`. Log: `/tmp/tabnax-item5-ui.log`. Tests cover invalid IDs, app exclusion versus independent exception, noninstalled ID persistence, remove/Undo/restart, preview filtering, wildcard validation, scoped sibling preservation, rule editing and persistence. The app/exception flow attaches the settings accessibility tree.
- **Real Carbon reservation probe passed** in the native suite: temporarily registered four-modifier F20, verified a competing exclusive registration failed while reserved, succeeded in an exception, and failed again after restoration. The test probes for existing collisions before use and unregisters all test resources. No key events were posted and no user apps were activated. This verifies OS registration ownership rather than only callback suppression.
- Rendered the Exclusions pane using the existing `--render-settings`, `--pane 6`, and a new `pl.tabnax.tests.<UUID>` domain. Inspected `item-5-settings.png`: seven-pane toolbar, inputs, matching explanations, validation and preview fit; the independent exceptions editor remains reachable by scrolling. The UI tests reuse the fully-visible-control reveal helper.

UI command:

```sh
xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/UIDerivedData \
  TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting \
  -only-testing:TabnaxUITests/NativeSettingsUITests/testAppExclusionsAndShortcutExceptionsSaveIndependentlyWithUndo \
  -only-testing:TabnaxUITests/NativeSettingsUITests/testTitleRuleValidationEditingPersistenceAndSiblingPreview test
```

Regression coverage includes all six layouts' exact IDs/direct addresses, native/tab ownership, title-only siblings, launch rows, missing IDs, live-title filtering, migration, invalid patterns, persistence/Undo, foreground initialization, preview/panel distinction, app changes during registration, stale deactivation and Carbon callbacks, same-PID transitions, deferred registration races, full passed/owned key sequences, shortcut recording and existing focus guards. The final native suite includes the later routing corrections; they did not change settings UI. The UI flows passed on their first completed run. An initial core fixture contained a prohibited format-control character and was corrected; all final checks pass. Initial SwiftPM sandbox/Swift 6 compilation failures were resolved before reporting results.

## Limitations and follow-up

- The host lacks Accessibility permission for the existing controlled cross-app window fixture; that one native test remains explicitly skipped. No permission was requested or changed. Exclusion/input tests use fictional targets and direct router replay. Actual VM, remote-desktop, game and Secure Input key delivery, including OS notification timing under load, was not exercised; an already-authorized test host should cover those combinations. The real Carbon reservation probe did run successfully.
- No live IME composition or VoiceOver session was exercised. Native editor routing and existing accessibility tests remain unchanged; new controls have unique identifiers and accessible labels. The full UI suite was not repeated; the parent plans its cumulative run after the remaining items.
- A future dedicated activation/search shortcut should share `ShortcutExceptionRouter.gate` and the policy’s registration decision, including delayed retry resampling; ignoring a Carbon callback alone is insufficient. The shortcut itself was not added here.
- App/title exclusions control Tabnax target visibility. An allowed app row can still activate that app according to normal macOS behavior; these preferences do not block access to content.

Public API references: Apple’s [frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) documents the keyboard-receiving app and KVO support. Carbon `RegisterEventHotKey` / `UnregisterEventHotKey` and their non-thread-safe annotations were checked in the installed public `HIToolbox/CarbonEvents.h` SDK header; all Carbon registration work stays on the main actor. Only public AppKit, Quartz, Carbon and existing AX APIs are used.
