# Item 3 — Fuzzy search and useful ranking

Implemented on 2026-09-22 in the existing untracked checkout, preserving item 2. No commits, staging, history initialization, resets, cleanup, worktrees, installation, real preference changes, permission changes or login registration. The original KB analysis is unchanged. No URL/domain protocol work was included.

## Delivered

- Field-local fuzzy search for app, title and context, including initials/camel-case boundaries and nonconsecutive characters in order. Every term must match. Case, accents, character width, formatting separators and separator-only queries retain their normalization rules. Meaningful symbols cannot be skipped by fuzzy gaps; fields cannot be joined. Transposed, inserted or substituted letters are not silently corrected.
- Whole-field, prefix, word-prefix and substring matches rank ahead of initials and loose subsequences. Equal scores retain stable catalogue ordering. Shore, Canopy, Lattice and Fold rank groups by the strongest matching child and rank their children; Beacons and Relay use flat ranked results. Empty/whitespace queries retain the existing unranked search presentation. Search does not change direct labels or target identity.
- `displayMatches` supplies both search rendering and navigation. Canopy columns and Fold's spine use this order; Relay search no longer applies a separate current/previous ordering. Unavailable rows stay disabled. Closed app targets have no search row and cannot be selected through Enter, pointer/highlight, or the selection API while searching. Their existing direct-address launch behavior is preserved.
- General → Search → **Remember search choices** defaults to off, including missing/malformed values in schema-v1 settings. Opt-in stores at most 128 recent query/target digest pairs using system CryptoKit SHA-256 with a random salt and length-framed fields. No readable query, title, app or context history is persisted in this store. Hints modestly improve ranking within a match tier; they never resolve or change identity. Fingerprints are not encryption.
- **Clear remembered choices**, off and restore-defaults remove stored choices and rotate the generation. Undo restores the preference only. Generation and revision guards prevent delayed callbacks or older settings snapshots from resurrecting cleared data or overwriting newer choices. Corrupt/oversized memory is discarded independently of settings. Settings previews do not record choices.
- Search normalization is cached on target metadata, results are cached across navigation, and memory lookups hash the query once per rerank. Native field-editor/IME routing, focus/spotlight, public target selection and all six direct layouts remain intact.

## Changed paths

- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Search.swift` (new)
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Selection.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Navigation.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Settings.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/SearchTests.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/AppShortcutTests.swift`
- `macos/Tabnax/Support.swift`
- `macos/Tabnax/InputRouter.swift`
- `macos/Tabnax/AppDelegate.swift`
- `macos/Tabnax/ModePresenter.swift`
- `macos/Tabnax/SettingsController.swift`
- `macos/TabnaxTests/NativeContractTests.swift`
- `macos/TabnaxUITests/TabnaxUITests.swift`
- `macos/README.md`, `macos/MODE-COVERAGE.md`, `macos/Packages/TabnaxCore/README.md`
- `docs/ARCHITECTURE.md`, `docs/PRIVACY.md`
- This record and `item-3-canopy.png` / `item-3-fold.png` (fictional, app-owned renders).

## Verification

- **`make check`: passed**, including publication/link policy, Python, JavaScript, browser companion and settings model checks. Final log: `/tmp/tabnax-item3-check.log`.
- **`make test-native`: passed — 106 core tests; 122 native tests executed, 121 passed / 1 skipped / zero failures.** Final result bundle: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-41-22-+0200.xcresult`. Final log: `/tmp/tabnax-item3-final-native.log`.
- **Native targeted run: 10 passed**, covering existing filtering layout checks, rendered order versus keyboard/pointer/Enter in all modes, and opt-in persistence/clear/disable/undo. Bundle: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-33-45-+0200.xcresult`. The subsequent full run additionally covers input-router selection → saved choice → next-opening ranking and out-of-order persistence callbacks.
- **Settings UI rerun: 2 passed**, new opt-in/persistence/clear/off controls plus the previous task's window-actions setting. Bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-36-53-+0200.xcresult`.
- **Final search UI run: 1 passed across all six modes.** A real Return key with a query matching only a closed app leaves search open with zero visible rows. The test then enters `rc`, verifies the strongest visible Beta result is selected ahead of Alpha abbreviations, and presses Return to commit. Result-row accessibility descriptions are attached to the bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-39-40-+0200.xcresult`.
- Rendered and inspected Canopy and Fold with `--render-preview`, `--search-fixture`, `--search rc`, the corresponding mode and a unique `pl.tabnax.tests.*` domain. Both show Beta before Alpha and select the exact `rc` result, keeping full stable addresses and clear search/footer controls. Screenshots are beside this record.

UI command base (run alone, never alongside native XCTest or other app launches):

```sh
xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/UIDerivedData \
  TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting \
  -only-testing:TabnaxUITests/TabnaxUITests/testFuzzyRankingAndEnterSelectTheVisibleResultInEveryMode test
```

The settings run used the same base with selectors `TabnaxUITests/NativeSettingsUITests/testRememberSearchChoicesRequiresOptInPersistsAndClears` and `TabnaxUITests/NativeSettingsUITests/testWindowActionsSettingPersistsAndCanBeRestored`. The native targeted run used `build/DerivedData` and selectors `TabnaxTests/FilteringLayoutTests` / `TabnaxTests/SearchChoicePersistenceTests` without the UI bundle override.

Coverage includes normalization (including full-width formatting separators), realistic exact/prefix/initials/subsequence ranking, typo and symbol boundaries, all-term/field separation, browser-owned grouped rows, unavailable/disappeared targets, metadata churn, stable labels/direct launching, default/malformed preference migration, bounded/deduplicated/private memory encoding, stronger-match precedence, persistence across restart, Clear/off/reset/Undo and stale callbacks.

## Corrections and limitations

- The old closed-app test explicitly expected Enter to select an invisible search result. It now asserts empty display/navigation and no selection, while retaining all its direct-launch checks.
- The initial new settings UI flow failed because a partially clipped checkbox was reported hittable and its click missed. The existing reveal helper now also requires the entire control to be inside the scroll viewport. Both the new setting and the previous window-actions setting passed afterward. Initial UI bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-35-02-+0200.xcresult` (search flow passed; settings flow failed). No failing product assertion remains.
- The host lacks Accessibility permission for the controlled cross-app window fixture, so the existing integration test remains explicitly skipped. No permission was requested or changed. Native selection, UI input and persistence use fictional targets and isolated preference domains; real window focus effects and a live IME/VoiceOver session were not re-exercised for this item.
- The first sandboxed SwiftPM invocation could not start its nested sandbox. All reported test results used reviewed execution permissions afterward.
- Full UI automation was not repeated for this item; three relevant UI tests have passing evidence. The parent should perform the planned final cumulative full UI run after task 6. The final native run includes the later memory revision guard; UI behavior was unchanged by that guard.
