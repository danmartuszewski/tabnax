# Item 2 — Window actions in the switcher

Implemented on 2026-09-22 in the existing untracked checkout. No staging, commits, resets, cleanup, worktrees, installation, login registration or permission changes. The source KB analysis was not edited.

## Delivered

- Shared footer ellipsis / Command–Period menu in Shore, Beacons, Canopy, Lattice, Fold and Relay, including search. Native NSMenu keyboard and accessibility support; disabled entries include their reason.
- Close, minimize, restore, hide/unhide app, zoom, fullscreen toggle and normal quit. Close uses the exact window's close control and dismisses the switcher to expose save/cancel prompts. Other applicable actions leave it open and report the result. Existing Command-Q and Option restore behavior is preserved.
- Window operations never resolve an app row, browser-tab row or Fold family into a different window. Existing app/family restore semantics remain. Browser app actions use the resolved process owner; hide/unhide is checked live.
- Frozen menu action IDs, process-lifetime/AX-handle checks, live capability checks and no global shortcut or private API fallback. New commands use public close/zoom/fullscreen controls and writable minimized state. Window support depends on the owning app.
- Menu opening disarms hold/latch modifier-release selection, including pointer-down and delayed presentation. Pending keystrokes are consumed until NSMenu is ready. Tracking owns native menu input and outside clicks, suppresses hover and spotlight, and preserves the native search editor. Commands reject stale sessions. Subsequent explicit navigation resumes preview/selection.
- General → Windows → Show window actions menu saves immediately, defaults to enabled when older documents are decoded, and preserves other settings. Turning it off leaves quit and Option restore intact.
- Repaired both existing appearance UI tests by scrolling the settings column before querying lazy theme controls, including after relaunch/reset, and explicitly activating the isolated test app. No product theme changes were made for those tests.

## Changed paths

- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Navigation.swift`
- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Settings.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/SwitcherActionTests.swift`
- `macos/Tabnax/WindowActions.swift` (new)
- `macos/Tabnax/FocusCoordinator.swift`
- `macos/Tabnax/InputRouter.swift`
- `macos/Tabnax/ModePresenter.swift`
- `macos/Tabnax/AppDelegate.swift`
- `macos/Tabnax/SettingsController.swift`
- `macos/Tabnax.xcodeproj/project.pbxproj`
- `macos/Fixtures/WindowFixture.swift`
- `macos/TabnaxTests/NativeContractTests.swift`
- `macos/TabnaxUITests/TabnaxUITests.swift`
- `macos/README.md`, `macos/MODE-COVERAGE.md`, `docs/ARCHITECTURE.md`
- This verification record, `item-2-menu-accessibility.txt` (final UI evidence), and `item-2-shore.png` / `item-2-fold.png` (isolated native renders).

## Verification

- `make check`: passed (publication/link policy, Python, JavaScript, browser companion and settings model checks).
- `make test-native`: **99 core tests passed; 118 native tests executed, 117 passed and one Accessibility-dependent skip; zero failures**. Final result bundle: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-18-22-+0200.xcresult`.
- Targeted `xcodebuild` UI run: **4 passed, 0 failures**, covering both repaired appearance tests, action-setting persistence and action menus/search across all six modes. Result bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-06-03-+0200.xcresult`.
- Full UI run: **13 passed / 3 failed**. It exposed an ambiguous preview Search lookup (fixed to preserve/replace existing query text), an unsupported panel screenshot lookup (replaced with menu accessibility evidence), and a transient failure of the unchanged prefix/Escape test. Final targeted rerun: **3 passed, 0 failures**, including all six action-menu/search layouts, corrected browser-preview navigation and the unchanged prefix/Escape test. Together, all 16 UI tests have passing evidence; the full suite was not repeated after these test-only corrections. Rerun bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-19-40-+0200.xcresult`. Full-run bundle: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_16-12-10-+0200.xcresult`.

UI command:

```sh
xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/UIDerivedData \
  TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting \
  -only-testing:TabnaxUITests test
```

The targeted run used the same command with these selectors: `TabnaxUITests/TabnaxUITests/testWindowActionsMenuAndSearchInEveryMode`, `TabnaxUITests/NativeSettingsUITests/testWindowActionsSettingPersistsAndCanBeRestored`, `TabnaxUITests/NativeSettingsUITests/testAppearanceThemesUndoAndResetRemainUsable`, and `TabnaxUITests/NativeSettingsUITests/testThemePickerSavesAndRestoresEveryPreset`.

Regression coverage includes all-mode target applicability, search/browser ownership, no retargeting, settings migration, hold/latch routing, menu readiness and key ownership, pointer gating, stale sessions, immutable native NSMenu dispatch and disabled explanations, idempotent restore, live unsupported controls, reused process IDs and existing quit/restore behavior. A native menu-dispatch test found a selector-name collision with NSObject; renaming the callback fixed it. UI tests found search selection being reset after a menu; removing the unnecessary responder reset fixed it.

## Limitations and follow-up

- The test host lacks Accessibility permission. The controlled cross-app fixture is explicitly skipped; no permission was requested/granted for testing. The fixture now tests exact duplicate-title minimize/restore, hide/unhide, zoom/unzoom, fullscreen in/out, cancelled close followed by successful close, and cancelled normal quit. Rerun it on an already authorized test host before treating those cross-app effects as empirically verified. Unit tests verify the command path and public control choice without touching user windows.
- No force-close/force-quit, synthetic global shortcut, title/geometry window lookup, or alternate-window fallback was introduced. Native apps without enabled AX controls show a disabled reason. Fullscreen may change Spaces according to macOS.
- Automated UI uses demo targets and isolated `pl.tabnax.tests.*` preference domains; it does not perform operations on real user apps. Screen-wide XCUI screenshots on this multi-display machine captured an unrelated display, so those preliminary screenshots are not included as evidence; final attachments contain action-menu accessibility descriptions. A panel screenshot lookup was unavailable on this host and was removed from the test. No preliminary desktop screenshots are included in this record. Final per-mode disabled action titles are collected in `item-2-menu-accessibility.txt`.
- The first sandboxed native invocation failed because SwiftPM could not start its nested sandbox. The requested Xcode runs succeeded with reviewed sandbox escalation. One preliminary UI attempt was interrupted by another foreground app, and a simultaneous native run interrupted a later preliminary flow; final UI validation runs alone. No real IME composition session or live VoiceOver session was exercised; the code preserves native field-editor ownership, and UI tests verify insertion-point/text preservation.

Public API reference: Apple's [AXUIElement documentation](https://developer.apple.com/documentation/applicationservices/axuielement) and [full-screen button attribute](https://developer.apple.com/documentation/applicationservices/kaxfullscreenbuttonattribute), cross-checked against the installed public SDK headers. The implementation uses `AXUIElementIsAttributeSettable`, `AXUIElementCopyActionNames`, `AXUIElementPerformAction`, `AXUIElementSetAttributeValue`, and normal `NSRunningApplication` hide/unhide/terminate.

## Native layout inspection

Rendered all six modes with the existing `--render-preview <path> --mode <mode> --test-domain pl.tabnax.tests.<UUID>` facility. Outputs are `macos/build/actions-{shore,beacons,canopy,lattice,fold,relay}.png`. Inspected each: the action button stays in the footer without overlapping Search, help, close or selection hints. The previews contain fictional targets only. Representative local renders: `item-2-shore.png` and `item-2-fold.png` beside this record (excluded from the public file set).
