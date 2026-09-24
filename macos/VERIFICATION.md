# Native settings verification — 17 September 2026

This record covers the current native settings implementation, separately from the browser design study and earlier native feasibility builds. Environment: Apple silicon, macOS 26.6.2, Xcode 27 / Swift 6.4; deployment target macOS 15 arm64. macOS 15 itself has not been exercised.

## Wake recovery (September 22)

System wake, display wake, and display arrangement changes now share the same catalogue invalidation and forced refresh path. A bounded recovery burst repeats discovery after 0.5, 1.5, 3, and 6 seconds because a successful early AX response can still omit windows while external displays settle. New events replace the previous burst; stopping the catalogue cancels queued callbacks. Forced refreshes requested during a busy discovery remain forced on the follow-up pass, bypassing any failure backoff established by the first read. Window identities and active-session shortcut rules remain unchanged.

Validation: native Debug build and all 9 `CataloguePerformanceTests` passed, including delayed recovery, burst replacement, and cancellation coverage. Physical sleep/wake with external displays has not been reproduced here. Check with windows on both laptop and external displays: sleep/wake, then open the switcher once after displays settle; repeat with display-only sleep and disconnect/reconnect. Opening before recovery completes can still show the cached session: newly discovered identities are intentionally admitted on the next opening.

## Display transitions (September 21)

Display changes now force catalogue and geometry refreshes, invalidate discovery and bounds reads from the previous display arrangement, and cancel pending focus work. Existing identities and letter books remain intact. Held codes retain their owners so a returning identity can recover its code even when the vocabulary is full. The missing-shortcut banner no longer claims that all letters are exhausted without evidence.

Core regressions cover 100 temporary-omission/restoration cycles, movement between external-display and laptop coordinates, catalogue reordering, shortcut stability and keyboard selection in all six layouts, and recovery from a fully reserved vocabulary without assigning held codes to new identities. Physical display unplug/replug with Arc remains a separate live check; the original screenshot's exact failure has not been reproduced on hardware.

Validation: 90 core tests passed; native build and test run succeeded with 109 tests passed and one skipped.

## Option restoration and minimized indicators (September 20)

Option now restores minimized windows instead of minimizing the highlight. Command release selects the restored window; visible windows are unchanged. App rows and Fold groups resolve an exact minimized child. A subtle minus badge identifies minimized windows in all six layouts, with group indicators, accessible state descriptions and live updates after restoration.

**78 core and 79 native tests passed, none skipped in the final native run.** The controlled fixture verified two-window restoration and repeated restore requests. Fourteen own-view previews were reviewed across the six layouts and compact/enlarged variants. Physical event-tap delivery was not exercised. See the [verification record and screenshots](verification/option-restore/README.md). The earlier minimize-action behavior below is historical and superseded.

## Cmd+Tab rendering performance (September 19)

The switcher prepares rows while hidden, retains its view hierarchy across openings, skips unchanged row bindings, moves AX title reads onto workers, batches ordinary discovery publications, and avoids redundant browser/startup refresh work. Session-correlated markers now separate activation recognition, main-actor delivery, and presentation preparation.

In optimized Canopy fixtures, first presentation after preparation fell from approximately **52 to 18 ms for 30 windows** and **94 to 28 ms for 100 windows**. Repeated presentation fell from approximately **6.7 to 1.2 ms** and **17.1 to 1.6 ms**, respectively. These measure presenter work, not physical key-to-visible-frame latency; preparation shifts work before activation.

**76 core tests and 72 native tests passed; one existing Accessibility-dependent native fixture was skipped.** Debug/Release builds passed, and all six native layout previews were rendered and visually inspected. Validation used an isolated app identity; the running development app and user preferences were not changed. [Implementation report and raw evidence](verification/performance-audit/IMPLEMENTATION.md).

## Exclusive fixed app letters (September 19)

Fixed app letters are reserved before automatic allocation in both the shared pool and the separate Fold/Canopy app-prefix book. Applying assignment changes rebuilds both books; ordinary catalogue publications and the closed-app launching toggle retain their cached allocations. Closed apps keep their reservations, session resets restore them, and removing or disabling assignments clears stale fixed-owner metadata. The grouped overflow filler also skips reserved letters outside a Pairs alphabet.

**69 core tests passed. All 44 native tests passed across the full run and the two fixture reruns, with none skipped.** New regressions cover G/O reservations with All letters, keyboard selection in every mode, closed apps and relaunches, owned browser tabs, draft isolation, reassignment/removal/disable, pool/Fold resets, conflicting Fold pins, and outside-alphabet overflow prefixes. The native settings regression exercises preview, Apply, persistence after restart, and reset in Shore, Fold and Canopy using isolated preferences.

Logs are `build/app-reservations-core-tests.log`, `build/app-reservations-native-tests.log`, and `build/app-reservations-fixture-tests.log`. The full native run passed all 42 non-fixture checks; the two fixture checks then passed after rebuilding the fixture with the existing `ENABLE_DEBUG_DYLIB=NO` signing workaround documented below. The rebuilt Debug app passed `codesign --verify --deep --strict`.

The running `build/RunDerivedData` development app was rebuilt, signature-verified and restarted through its existing Restart Tabnax control after confirming there was no pending settings draft. Before restart, the live Canopy preview used O for Podcasts and G for Google Chrome despite the saved Obsidian/O and Ghostty/G assignments. After restart, Podcasts used D and Google Chrome used L; neither reserved key was reused. No saved preference or OS permission was changed for this check.

## Switcher quit and minimize actions (September 19)

Command-Q now requests a normal quit of the highlighted app, window owner or resolved browser-tab owner. A fresh Option press minimizes the highlighted AX window, or the focused/main window of a highlighted app. Opening with an Option-based activation chord does not minimize anything. Search retains Option text-entry behavior. Closed apps, unavailable targets, unresolved browser owners and ambiguous overflow groups cannot dispatch an action. Releasing the activation modifiers after an action does not select or restore its target.

**63 core tests and 43 native tests passed, none skipped.** Coverage includes all six layouts, Fold app groups, search/browser ownership, stable letters after app termination, Command-Q versus plain Q, held/latching activation, repeat/key-up ownership, fresh Option presses, search handoff, unavailable identities and reused process IDs. The controlled duplicate-title fixture confirmed exact-window focus, two rapidly enqueued minimize requests against independent AppKit window reports, refusal of a first normal quit, and successful termination on the second request. The fixture waits for completed Dock-animation notifications rather than assuming AX request acceptance means its report is already updated.

The native result is `build/ActionDerivedData/Logs/Test/Test-Tabnax-2026.09.19_06-05-04-+0200.xcresult`. This separate build directory avoids interfering with concurrent development builds. The fixture was built with the existing `ENABLE_DEBUG_DYLIB=NO` workaround described below. The Shore preview (`verification/app-actions/shore.png`; local artifact, not published) was rendered from the app with isolated preferences and visually checked for readable shortcut hints. Physical keyboard delivery through a live system event tap and third-party save dialogs were not exercised; callback routing and normal quit cancellation were verified with controlled tests. No commit was created.

## Window-switching behaviour changes (September 18)

Switching now follows the conventions of the native switcher and comparable tools: most-recently-used history with the session opening on the previous window, modifier-owned hold with trigger re-press cycling, arrow-key navigation, swallowed stray keys, selectable windows on other Spaces ("Elsewhere"), tolerance of Accessibility timeouts, in-place event-tap recovery, a public Carbon hot-key fallback, an `AXFrontmost` fallback when activation is not observed, and admission of titled nonstandard-subrole windows. Typing after a switch only disarms the focus repair; it no longer cancels the switch. Only public APIs are used.

**56 core tests and 35 native tests passed, none skipped.** Seven new core tests cover history, opening position, Fold branch commit, arrows per layout and Elsewhere targets; five new router tests cover hold quick-tap, latch cycling and toggle, arrows and stray keys, passive-key repair disarming, and single tap-loss recovery. The live exact-window fixture test passed against the changed focus path.

The two fixture-dependent tests fail under `scripts/test.sh` as the project stands, independently of these changes: the `TabnaxFixture` Debug configuration enables the hardened runtime while signing with the team-less `Tabnax Dev` identity and leaving Xcode's debug dylib on, so library validation rejects `TabnaxFixture.debug.dylib` and the fixture never starts. The passing run above built with `ENABLE_DEBUG_DYLIB=NO` on the command line; the project file was not changed. The `Tabnax` target already sets this.

Not exercised live: travel to another Space or a full-screen window, whether background native tabs surface as "Elsewhere" rows, the hot-key path under real Secure Input, the `AXFrontmost` fallback against a genuinely unresponsive app, and nonstandard-subrole admission across third-party apps.

## Letters and Apps settings split (September 17)

The former Selection pane is split into **Letters** and **Apps**. General owns the default opening scope and separates window inclusion from Startup. Advanced session pins are expandable. Drafts and Apply/Discard survive pane navigation; pending resets retain their original label namespace when app edits change the preview scope.

**26 native tests passed, one existing Accessibility-dependent test skipped, and all three focused UI flows passed.** An initial launcher-fixture startup race was corrected with a readiness wait before the native rerun. The UI checks cover cross-pane drafts, Apply/Discard, persistence, the moved opening-view control, app assignment/launch settings, and all six browser-tab previews. [Review and eight renders](verification/settings-split/README.md) include the result identifiers and scope. No user preferences or permissions were changed.

## Development rebuild/reload runner (September 17)

`scripts/dev.sh` and the double-clickable `Run Tabnax.command` build the native app in separate development output, verify and stage the bundle, close only this project's app copies, and reopen Settings at a stable development path. The watcher ignores generated/editor state, debounces saves, detects edits made during compilation, and supports manual `r` + Enter and one-time `--once`. A project lock prevents duplicate runners. Ctrl-C is deferred during app replacement so the bundle cannot be left half moved.

**Six runner tests passed**, covering source additions/edits/removals, ignored output, save coalescing, edits during compilation, failed builds leaving the running bundle intact, successful replacement, and launch-failure rollback (including restoring a previously running Release on the first development launch). Run `/usr/bin/python3 -B macos/scripts/test_dev.py`.

Real macOS checks passed for initial build/reopen, automatic reload after a temporary source addition, a second edit during that build, fixture removal, manual reload, `--once`, duplicate-runner rejection, idle watching without rebuild loops, and stopping the watcher while the app remains open. The temporary source fixture was removed. The app's Settings window was observed through computer use. The rebuilt development app passed `codesign --verify --deep --strict`; no OS grants or saved preferences were changed. Build diagnostics remain in `build/dev/build.log`. Native compilation warnings and existing Accessibility requirements are unchanged.

## Persistent app letters and optional launcher (September 17)

Selection now includes an app picker, icon/name rows, conflict-aware letter menus, independent fixed-letter/launch switches, and a persistent Apply/Discard bar. Assignments survive relaunches by bundle identity. Fixed letters reserve their app namespace before automatic allocation, work outside the window alphabet, appear in every Apps display mode, and supply Fold app prefixes. Multiple instances of one bundle never share a complete address. Closed assigned apps appear only with both switches enabled; missing apps are unavailable. Preview actions never launch apps. Apps may be the default scope even with browser tabs disabled.

**38 core tests passed; 26 native tests passed, with one existing Accessibility-dependent exact-window fixture skipped. All nine UI flows passed across the full run and targeted correction run.** The new UI flow exercises the native app picker, letter editing, Apply, relaunch persistence, disabling launch, Discard and disabling fixed letters. Initial failures were in the test script: a Touch Bar duplicate of the dialog button and macOS checkbox values represented as numbers. The final targeted run passed after those assertions/selectors were corrected.

The controlled native fixture verified real Launch Services opening of a stopped app, activation of the same process on a second invocation, and cancellation before dispatch. Core tests cover legacy decoding, persistence, forced collisions, overflow conflicts, reservations across quit/relaunch, separate window meanings, multiple app instances, and all six Apps modes. Debug build passed. No user preferences, login items or OS grants were changed. Physical global-shortcut interception and exact-window focus retain their existing Accessibility requirements; no new permission grant is claimed.

Verification results (`verification/app-shortcuts/results.json`; local artifact, not published), test summary (`verification/app-shortcuts/test-summary.log`; local artifact, not published), light settings (`verification/app-shortcuts/selection-light.png`; local artifact, not published), and compact dark settings (`verification/app-shortcuts/selection-compact-dark.png`; local artifact, not published). These are app-owned view renders with isolated sample assignments. Final native and UI result bundles: `Test-Tabnax-2026.09.17_20-01-55-+0200.xcresult` and `Test-Tabnax-2026.09.17_20-03-24-+0200.xcresult` under `build/DerivedData/Logs/Test/`.

## App icon alignment correction (September 17)

Target rows now center app icons against the measured title/subtitle block with a consistent two-point line gap. Tile layouts keep the text directly below the icon/key row; Canopy headings share the target rows' icon and text columns. Native icon padding is accounted for, including compact Settings previews and enlarged labels. The shared renderer applies this to all six modes, windows, browser tabs, running apps and search results.

Debug and Release builds passed, and the Release signature passed `codesign --verify --deep --strict`. Three existing UI checks passed: six-mode browser-tab previews, mouse-off/wheel preview behavior, and immediate target/overflow selection. Result: `build/DerivedData/Logs/Test/Test-Tabnax-2026.09.17_19-50-15-+0200.xcresult`. [Visual evidence](verification/icon-alignment/README.md) contains 26 app-owned renders, including all six native modes, Windows/Tabs Settings previews, narrow Fold/Lattice branches and enlarged labels. No OS permissions or user preferences were changed for these checks.

## Settings design refinement (September 17)

The [design-parity review](verification/SETTINGS-POLISH.md) covers the shared scope tabs, desktop placement preview, directional anchor picker, refined settings chrome, letter keys, theme swatches, browser icons and compact renderer. Light/Dark/System now updates the Settings window as well as the switcher. Position uses an explicitly illustrated desktop and the actual placement calculation; it does not imply that the diagram mirrors the user's monitors.

**31 core tests and 22 native tests passed; one existing permission-dependent cross-app fixture test was skipped. All eight UI flows passed across the full run and targeted correction runs.** The full UI run first found that a link-styled reset action lacked its button role. That was corrected and the complete selection/recovery/persistence flow passed again; the Position flow was also repeated after the compact-view refinements. No OS permission was changed.

Evidence in `build/DerivedData/Logs/Test/`: native `Test-Tabnax-2026.09.17_19-36-08-+0200.xcresult`; full UI `Test-Tabnax-2026.09.17_19-28-27-+0200.xcresult`; corrected selection `Test-Tabnax-2026.09.17_19-30-54-+0200.xcresult`; final selection and Position `Test-Tabnax-2026.09.17_19-34-39-+0200.xcresult`. Xcode retained the latest three bundles; the original full-run console results are preserved in `verification/settings-polish-test-summary.log`. Twenty app-owned renders in `verification/settings-polish/` cover all five panes, six Position illustrations, six native modes, dark/light appearances, compact sizes and enlarged labels. These are view renders, not screen captures. Release build/signature and executable identity are recorded in `verification/settings-polish-results.json`.

## Command–Tab correction (September 17)

Command–Tab is now a supported activation chord. The recorder receives it from the existing session event tap before macOS handles the app-switcher shortcut. Settings also provides **Use ⌘ Tab**, which can save the choice without Accessibility access. Other navigation keys and ordinary single-modifier typing retain their previous restrictions. Recording stops when Settings loses key-window status or closes, and stale recording callbacks cannot change a later choice.

Validation after this correction: **30 core tests passed; 21 native tests passed, 1 permission-dependent fixture test skipped; 1 focused native UI test passed**. Coverage includes Command–Tab activation and exact selection in all six modes, persistence/Undo, cancellation, stale callbacks, repeat/key-up ownership, direct selection and restoration, and local shortcut recording. Native recording was also checked through computer use, then the original shortcut was restored. UI keyboard events must target the inert shortcut text: targeting the Record button makes XCTest click it again and cancel recording.

Results: `Test-Tabnax-2026.09.17_19-07-29-+0200.xcresult` and `Test-Tabnax-2026.09.17_19-13-04-+0200.xcresult` in `build/DerivedData/Logs/Test/`. Physical Command–Tab interception still requires the normal app's Accessibility permission and has not been asserted as a live pass. No OS permissions were changed. The earlier suite summary below describes the original settings implementation.

## Results

| Check | Current result |
| --- | --- |
| Swift 6 Debug app and embedded Safari extension | Built successfully |
| Pure Swift suite | **29 passed**, including settings, labels, contrast, placement, six-mode navigation, browser protocol and gesture ownership |
| Native XCTest suite | **18 passed, 1 skipped**, no failures; actual router, persistence/migration, draft isolation, recording suspension, browser wire/backpressure, accessible mouse-off targets and installed browser script compilation |
| XCTest-host exact-focus fixture | Skipped because that specific launch context lacks Accessibility |
| Direct executable fixture | **20/20 passed** with existing Accessibility; current report (`verification/settings-integration-results.json`; local artifact, not published) |
| Native UI suite | **5 passed**, no failures, in the final complete run; result summary (`verification/settings-test-results.json`; local artifact, not published) |
| Shared browser companion tests | Passed handshake, private exclusion, duplicate-title identities, exact tab/window selection, stale connections, pause/re-enable and cancellation |
| Native settings and mode renders | 23 native views rendered and visually reviewed; artifacts (`verification/settings/`; local artifact, not published) |
| Release build and signature | Passed; `codesign --verify --deep --strict` passed for local ad-hoc signatures; app/extension versions match; no XCTest bundle embedded |
| Normal-launch app permissions | Current rebuilt Debug app reports Accessibility required; direct-executable trust does not establish normal-launch trust |
| Live browser connections | Arc/Chrome report Automation approval required; Zen/Firefox/Safari require companion approval; Edge/Brave are installed but not running. No live-browser focus pass is claimed |

Build/test logs and xcresult bundles remain under local `macos/build/` and temporary build logs. The result summary (`verification/settings-test-results.json`; local artifact, not published) identifies the completed full-suite run. The final settings reopen/persistence test also passed after its activation adjustment. A further six-mode Windows/Tabs UI run passed after the Fold highlight correction. The finished Release app was opened and its native Accessibility-required state was verified; it remains a permission gate, not an assumed pass. No TCC records, browser permissions, login items or security preferences were changed to obtain a pass.

## What these tests establish

Core tests exercise prefix-free four-character stable allocation, pair capacity, held reservations, filters and target churn, app/window/tab namespaces, staged label changes and pins, retirement, future-version validation, scoped recovery, contrast for all presets and custom colors, all anchors against usable bounds, history semantics, search isolation, visible Lattice branches and Fold stages. Trackpad tests reject gestures entering halfway through, keep Fold’s starting region, ignore momentum and reset accumulated movement after session/prefix changes.

Native callback tests run the real `InputRouter` without posting system events. They cover complete final-key sequences before a frame, modifier-side filtering, hold cancellation, search handoff, autorepeat/key-up ownership and recorder suspension. They prove callback logic, not physical keyboard delivery or coexistence with another event tap.

Native control tests ensure Mouse Off still permits assistive activation in every mode. Persistence tests preserve legacy/corrupt/future settings and exercise Undo and failed runtime side effects. Browser tests compile production scripts against installed Arc/Chrome/Edge/Brave dictionaries without reading user tabs. Socket tests cover framed bounds, message order, disconnect and write backpressure. Node tests run the actual companion script against an isolated API harness; they do not replace installation in real browsers.

UI tests use isolated preferences and synthetic native previews. They exercise every pane, editing the alphabet with native Select All, Restore default order, Apply and persistence across relaunch, mouse Off, wheel highlighting without commitment, target clicks, all six Windows/Tabs views, Lattice branching and Fold families. Standalone tests verify immediate overflow and Escape back/close behavior.

The direct fixture harness opens, focuses, hides, minimizes and closes only its own identical-title test windows. Its independent `NSWindow.isKeyWindow` report confirms exact focus. It also checks production catalogue reconciliation, held identities, geometry, Fold addresses, six-mode preservation, Relay history and event-tap creation. The app’s AX launch context differs from XCTest and normal Launch Services; those results are not interchangeable. Harness elapsed samples include test polling and startup, not key-to-focus latency.

## Visual and implementation review

The [settings review](verification/SETTINGS-REVIEW.md) maps implemented behavior and records issues corrected during development: missing Edit responder commands, toolbar hit areas, Fold action roles, Lattice traversal, physical mouse gating, event-coordinate outside clicks, target retention after label exhaustion, scroller-gutter clipping and compact-frame sizing. The preview embeds the actual switcher renderer and cannot focus another application.

Renders use only owned AppKit views and isolated preferences. They cover five settings panes, all six modes in Tabnax green, light presets, enlarged labels and compact layouts. Partially visible rows inside a scroll viewport indicate additional content; address badges and controls must remain inside the viewport. Real display topology and hardware scroll devices are separate checks.

## Remaining external validation

| Area | Remaining work |
| --- | --- |
| Permissions | User approval for the exact normal-launch app and per-browser adapters; deny/revoke and signed-update recovery |
| Browser distribution | Signed Firefox/Zen add-on; signed Safari extension and release validation of its scoped Unix-socket entitlement; no add-on was published |
| Live browsers | Exact tab focus, closure/movement, browser restart, profiles, Arc/Zen workspace and split-view behavior after approvals |
| Physical input | Real keyboard/IME layouts, Mouse/Magic Mouse/trackpad, VoiceOver, Full Keyboard Access, Mouseless/remappers, Sticky/Slow Keys and Secure Input |
| Desktop arrangements | Mixed-scale/rotated/negative-origin displays, Dock/notch, unplug/replug, Spaces, full screen and Stage Manager |
| AX compatibility | Third-party app/modal/sheet behavior, slow/crashed apps, adversarial focus races and notification loss |
| Login item | Real registration/approval/revocation on a signed installed build; tests cover failure-preserves-settings behavior |
| Resource/performance | Idle CPU, wakeups, memory, long-running retention and physical key-to-focus distributions; architecture targets are not measured guarantees |
| Release | Developer ID, notarization/stapling, quarantine, clean download and signed replacement preserving permissions |

No universal exact-window guarantee, all-Spaces guarantee or production-release claim is made. Deferred product scope remains modifier-only activation, persistent app pins, global wheel capture, history/archive and remote debugging.

## Historical evidence

Earlier six-mode work produced mode-integration-results.json (`verification/mode-integration-results.json`; local artifact, not published), and the original Shore build produced exact-focus-results.json (`verification/exact-focus-results.json`; local artifact, not published). The earlier UI runner was blocked before execution; the settings work subsequently ran native UI tests successfully. Earlier performance smoke traces were not valid Release baselines and are not used here. The original mode renders under `verification/modes/` remain historical; use `verification/settings/` for this implementation.

Use [README.md](README.md) to reproduce builds, test suites, the controlled fixture and own-view renders. Nothing was committed or published as part of this task.
