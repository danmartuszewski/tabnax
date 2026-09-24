# Dedicated opt-in search shortcut

Implemented on 2026-09-22 in the existing untracked checkout, preserving items 2, 3, 5 and 6. No staging, commits, history initialization, resets, cleanup, worktrees, installation/deployment, real preference changes, permission changes or login registration. The original KB analysis is unchanged. Simultaneous multi-display presentation remains the next task.

## Delivered

- General → **Open in search**: separate enable control, recorded chord, independent modifier side and scoped chord reset. Suggested Control–Shift–Space; disabled for new/migrated settings. Disabling retains the chord; Restore defaults disables it; Undo/persistence preserve the independent main activation.
- Validation rejects overlapping key/modifier/side combinations when enabled. Either-side overlaps either left or right; disjoint left/right are valid. Invalid/conflicting recordings retain the previous saved value and keep the recorder available; Escape cancels, cancelled/stale recording sessions cannot overwrite settings. Recording suspends both tap activation and both fallback registrations; deferred retries still resample exceptions.
- Shift-only printable chords are rejected for both shortcuts, including Space and non-letter printable keys. Shift/function keys remain valid. Legacy saved Shift-only main chords recover to Control–Option–Space on decoding while preserving behavior, modifier side and unrelated settings. They do not make settings globally read-only. If recovery conflicts with an enabled search chord, search is disabled. Missing/malformed new search settings cannot opt the user in.
- The event-tap and Carbon paths share search activation behavior: first frame is already searching; hold, latch and quiet-return cannot close or select on modifier release. Invocation from an active direct view enters search in the same session, retaining frozen ordering and target addresses. Repeating refocuses without clearing the query/highlight or composition; trigger autorepeat is inert. Enter selects the visible result, Escape exits search and a second Escape closes.
- Early tap key-downs are queued to the native field editor until it is focused, retaining original events and repeat/key-up ownership. Subsequent text uses ordinary AppKit/IME handling, never address parsing. Repeated invocation does not select all; presentation updates preserve marked text, and IME retains Return/Escape while composing.
- Both shortcuts use the existing foreground exception gate, permission lifecycle, recorder suspension and deferred retry policy. Eligible either-side chords have independent Carbon signatures plus registration generations. Handlers return `eventNotHandledErr` for other identities instead of consuming sibling callbacks. Command–Tab and side-specific chords remain tap-only; supported fallback chords keep search latched during Secure Input.
- Added a Debug-only, isolated UI fixture using the actual router/presenter or the actual Carbon application dispatcher, with fictional targets, a background text sink and no global event tap/hotkey registration. It requires a `pl.tabnax.tests.*` domain. It does not call `beginSearch` to simulate activation.

## Changed paths

- `macos/Packages/TabnaxCore/Sources/TabnaxCore/Settings.swift`
- `macos/Packages/TabnaxCore/Tests/TabnaxCoreTests/SettingsTests.swift`
- `macos/Tabnax/InputRouter.swift`
- `macos/Tabnax/AppDelegate.swift`
- `macos/Tabnax/ModePresenter.swift`
- `macos/Tabnax/SettingsController.swift`
- `macos/TabnaxTests/NativeContractTests.swift`
- `macos/TabnaxUITests/TabnaxUITests.swift`
- `macos/README.md`, `macos/MODE-COVERAGE.md`, `docs/ARCHITECTURE.md`
- This record.

## Verification

- **`make check`: passed.** Publication/link policy, Python, JavaScript, browser companions and settings models. Log: `/tmp/tabnax-search-check.log`.
- **`make test-native`: passed — 122 core tests; 147 native tests executed, 146 passed / 1 Accessibility-dependent skip / zero failures.** This includes 10 new native shortcut tests. Log: `/tmp/tabnax-search-native.log`. Result: `macos/build/DerivedData/Logs/Test/Test-Tabnax-2026.09.22_17-52-13-+0200.xcresult`.
- **Targeted UI: 2 passed / zero failures**, run alone. Settings opt-in, invalid/overlapping recordings, cancellation, persistence, reset, disable and main-chord preservation; plus immediate typing, repeat, Enter/Escape and no text leakage across **all six layouts × both paths**. Log: `/tmp/tabnax-search-ui-final.log`. Result: `macos/build/UIDerivedData/Logs/Test/Test-Tabnax-2026.09.22_17-49-26-+0200.xcresult`.
- **Real Carbon registration and dispatch tests passed.** Two temporary four-modifier F19/F20 reservations, pre-probed for conflicts, both register and release for a foreground exception. Actual `EventHotKeyID` events sent through `SendEventToEventTarget` reach exactly their own installed handler; unknown identities remain unhandled, stale generations cannot fire, and both OS reservations return after leaving the exception. Every temporary registration is released. No events are posted to other applications.
- Native event-tap replay covers both hold/latch settings, quiet return, modifier release, full trigger ownership, same-session search entry, side-specific routing, exception pass-through across focus changes, suspension/recording and menu ownership. Immediate text and Enter go through the native editor in every layout and select the exact expected ID. Marked-text coverage uses a real `NSTextView` marked range and confirms repeat preserves it and leaves Return/Escape to composition. Native persistence covers legacy recovery, conflicts, stale recording, reset and Undo.

UI command (run alone):

```sh
xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath macos/build/UIDerivedData \
  TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting \
  -only-testing:TabnaxUITests/NativeSettingsUITests/testSearchShortcutOptInRecordingValidationPersistenceAndReset \
  -only-testing:TabnaxUITests/TabnaxUITests/testSearchShortcutImmediateTypingRepeatAndEscapeInEveryLayoutAndPath test
```

## Corrections, limits and follow-up

- Initial sandboxed Xcode dependency resolution could not write external compiler caches; reported runs used reviewed execution permissions. Preliminary compilation errors in the new test fixture were corrected before execution. The first UI execution failed on test assumptions (checkbox values are numeric, and “Release” matched no demo target); corrected to numeric values and the existing InputRouter sample. Both final flows pass. Native marked-text handling was tightened before the final UI/native runs. The last two native-only ownership/side regression tests were added afterward and included in the final full native suite.
- The host lacks Accessibility permission for the existing controlled cross-app fixture, which remains explicitly skipped. No permission was requested or changed. Physical global interception, real Secure Input delivery, VM/remote/game foreground timing, physical alternate keyboard layouts, and a live IME candidate/VoiceOver session were not exercised. The two activation dispatch paths and native marked-text mechanics are covered in isolation, not claimed as live hardware verification. An already-authorized test host should run those remaining integration checks before release.
- The cumulative full UI suite remains the parent's planned gate after simultaneous displays. This task ran its changed settings/input flows only. Prior full native coverage, including main activation, menu ownership, exclusions, frozen ordering, focus and spotlight, passes. No other gap item was implemented.
