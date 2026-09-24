# Functionality and settings review — 19 September 2026

Reviewed the native app, pure selection/settings models, browser adapters and companions, native renderer, development runner, and existing verification records. The scope is the current implementation, including the shared target view and six themes added concurrently in this workspace. Historical HTML prototypes were treated as design references, not shipping functionality.

The review found and corrected functional defects. Automated verification establishes the application logic and controlled native behavior; browser-owned consent, installed login behavior and physical hardware compatibility remain separate checks. The workspace has no Git repository; no commit was created.

## Corrections

| Area | Failure | Correction and regression evidence |
| --- | --- | --- |
| Typed characters | App letters and generated overflow letters outside the configured alphabet were swallowed. | Accept the full A–Z address vocabulary, matching physical-key behavior. Native tests type both a fixed external letter and a generated overflow sequence through the actual router. |
| Assigned app launching | Lattice removed closed apps from its cells; Fold and Canopy removed them from their targets. | Closed assigned apps remain visible and navigable in every mode. Core tests cover direct letters, keyboard highlight selection, search and Fold family clicks. Missing apps retain their unavailable state. |
| Singleton Fold family | Clicking a family with one exact-address child sent a prefix request that could never match a descendant. | A Fold family click selects its available exact child. Multi-child families retain their two-stage behavior. |
| Canopy letter reset | Canopy displayed grouped addresses but reset the flat pool. | Canopy and Fold reset their shared grouped namespace; preview/discard keeps the live allocation intact. Fixed app reservations remain preserved. |
| Browser preview | Live browser tabs were mapped without their real app owner; sample tabs had no app containers. Grouped previews could show blank addresses or omit families. | Live and preview snapshots share owner resolution. Samples include their browser app containers. Tests verify nonempty grouped addresses and duplicate running bundle IDs. |
| Appearance Undo | Undo changed the saved appearance and window but left the preview editing the previous light/dark tone. | Discard/Undo resynchronizes the preview tone with the restored setting. |
| Position reset | The reset button stayed enabled at the default position when the shared display choice differed from the default. | The button compares the anchor and inset it actually resets; the shared display choice remains intact. |
| Browser approval/refresh | Asynchronous approval results did not publish status or fetch newly approved tabs. Revocation could leave tabs apparently available. | Publish permission changes immediately, refresh after approval and configuration changes, ignore older passive probes after explicit setup, and reject read completions after revocation. |
| Browser selection eligibility | A previously routed tab could still dispatch after range/enable settings changed. | Cancel pending browser focus on preference changes and require the current target to be available and included. Initialize the active browser from the foreground app when discovering connections. |
| Safari after idle | Heartbeat backoff could reach 5 seconds while native selection expired after 3 seconds. | Cap idle command collection at 1 second; a deterministic transport test verifies command delivery, immediate result replies, metadata-free heartbeats and disconnect cleanup. This bounds transport waiting, not arbitrary browser activation latency. |
| Settings guidance | App instructions referred to removed “3 / Apps” scopes; validation still required two modifiers in its error message. | Help and usage documentation now describe the shared view, grouped behavior, current alphabet bounds, global display choice and single-modifier support. |
| Integration fixture | Default Debug fixture signing rejected Xcode's injected debug dylib, preventing launcher/focus tests from starting. | Disable the fixture's debug dylib, retaining its hardened-runtime setting. Both controlled integration tests run successfully. |
| UI test isolation | Multiple development copies shared the UI test application's bundle ID, making attachment and relaunch unreliable. | UI tests build under `build/UIDerivedData` with a separate application/extension bundle identity. Normal Debug and Release identities remain unchanged. |

Native key-cap creation also explicitly declares its main-actor requirement, eliminating the associated Release concurrency warnings. Existing UI checks were updated for the current shared target layout, renamed theme controls, visible menu items, scrolling and Touch Bar duplicates.

## Settings coverage

“Automated” means exercised in pure/native tests and, where listed, XCUITest. It does not imply that every OS permission state or hardware arrangement was reproduced.

| Pane | Controls / functionality | Verification |
| --- | --- | --- |
| General | Record shortcut; Command–Tab button; suggested shortcut; cancellation; validation; stale recorder callbacks | Native router/recorder tests and UI persistence flow. Suggested chords still use two modifiers; custom non-navigation chords accept one. |
| General | Press to open / Hold to show; modifier side | Actual event-router replay covers latch/hold, left/right/either, repeat, trigger cycling, modifier release, no release selection after typing/actions, and tap recovery. |
| General | Mouse Off / Click / Click + wheel | Native accessibility actions remain enabled with Mouse Off; UI click gating and wheel highlight; pure gesture ownership, momentum, horizontal-motion and boundary tests. Physical trackpads/remappers remain external checks. |
| General | Include minimized windows / Include windows of hidden apps | Native preview filtering, saved preferences, Undo, and retained addresses. The controlled fixture exercises minimizing/restoring actual windows. Fixed app assignments retain their intended hidden-app exception. |
| General | Launch at login; observed registration status; Open Login Items | Registration/unregistration wiring reviewed; failure preserves the saved preference in native tests. Actual login/approval/revocation on an installed signed build is **not verified**. |
| General | Accessibility status; Open System Settings; Retry; Restart | Wiring reviewed and existing trusted fixture exercises AX control. No permissions changed. Denied/revoked normal-launch recovery and actual Restart against a user draft were not exercised. |
| Letters | Right/Left/Both/All/Custom; 6–26 unique letters; reorder; Remove I/O; Restore default order | Validation/allocation tests and UI custom edit/restore/apply/relaunch. Too-short or duplicate alphabets cannot apply. |
| Letters | Stable / Name initials first / Always two letters | Core capacity, prefix, mnemonic, retention, assignment-conflict and policy-change tests. Fold/Canopy use their own mnemonic grouping contract. |
| Letters | Physical positions / Typed characters | All physical A–Z positions and real router character events, including outside-alphabet fixed and overflow letters. Real non-US layouts, dead keys and IME still need hardware checks. |
| Letters | Reset assignments; staged changes; Apply/Discard across panes | Native transaction/reset/pin tests and UI cross-pane draft/persistence tests. Canopy now targets the grouped namespace. |
| Apps | Enable fixed letters; application picker; choose/remove letter; conflict restrictions | Native assignment/reservation/multiple-instance tests; native picker and letter editing in XCUITest; Apply, persistence, disable and Discard. |
| Apps | Launch assigned apps when closed | Both switches required; unavailable/replaced paths rejected; stable bundle identity; six-mode reachability. Controlled Launch Services fixture verifies real launch, existing-process activation and cancellation. Preview never launches. |
| Position | Shared display choice; mode; all nine anchors; inset 12–64 in steps of 4; per-mode reset | Core usable-frame/illustration tests across every mode/anchor, native persistence/Undo, UI mode/anchor/display/inset/reset/relaunch. Real mixed-display topology remains external. |
| Appearance | Six themes; System/Light/Dark; separate light/dark editing; key/selection colors | Native theme/renderer and persistence tests; UI theme selection, relaunch, Undo and restore. Core contrast tests and custom color resolution. Compositor output uses a documented solid fallback for own-view exports. |
| Appearance | Per-color reset; Reset this theme; label sizes; stronger outlines | Scoped core resets preserve other tones/themes; native persistence/Undo; renderer responds to sizes/outlines and system contrast. Hardware display/VoiceOver checks remain external. |
| Browser tabs | Include tabs; All available / Choose browsers; seven browser toggles; All / Active browser / Active window | Browser catalogue fixture verifies inclusion, ranges, private exclusion, stable IDs and immediate permission publications. Native preview tests and UI disable/subset/range/persistence/reset flow. |
| Browser tabs | Seven connection status/setup controls | Installed Apple-event dictionaries compile; framed protocol/backpressure and Gecko/Safari companion harnesses pass. **Live browser tab switching and consent/distribution are not certified by these tests.** |
| Shared | Restore defaults; bounded Undo; persistence; migration; malformed/future data | Native persistence/transaction/failure tests, UI restore and relaunch. Undecodable/future documents remain protected; individual supported cosmetic entries follow the existing validation fallback policy. |

## Switching functionality

| Function | Verification |
| --- | --- |
| Six modes and mixed target view | Core/native tests cover direct selection, app containers, launcher targets, unavailable/exhausted targets, prefixes, Lattice branches and Fold singleton/multiple children. |
| Search and navigation | Native layout tests cover typing, clearing, no results and Escape in all modes; core tests cover group order, highlighted targets and Relay search selection. |
| Immediate keyboard selection | Actual router callback replay verifies complete addresses without a frame, swallowed repeats/key-up and modifier interactions. |
| Exact focus, restore and history | Controlled duplicate-title windows independently report real key-window status. Native tests cover minimize, normal quit refusal/completion and identity/process-lifetime checks. |
| Browser identity and privacy | Private tabs excluded, duplicate titles retain distinct IDs, moved-tab selection, stale generations and cancellation covered by protocol/harness tests. Browser approval remains required. |
| Development rebuild/reload | Six runner tests cover source changes, ignored output, build coalescing, replacement and launch-failure rollback. |

## Results and evidence

Final run identifiers, counts and render artifacts are recorded below after verification completes.

Logs are kept under `macos/build/functionality-review-*.log`. Earlier failed runs are retained to show fixture, selector and app-identity problems; they are not represented as passing runs.

## Remaining external checks

- Browser-specific Automation approval, Safari extension approval and Firefox/Zen installation/signing; live exact selection after movement/closure/restart and across profiles/workspaces.
- Real launch-at-login behavior and approval/revocation with a signed installed app.
- Physical global shortcuts, non-US keyboards/IME, accessibility tools, Secure Input, hardware mouse/trackpad gestures and remappers.
- Multiple displays, Spaces/full screen, Stage Manager, mixed scaling and hot-plugging.
- Broader third-party AX compatibility, sustained resource use and measured input-to-focus latency.
- Developer ID signing/notarization, quarantine and signed-update permission continuity.

These are explicit limits of the evidence, not settings marked as universally working. Builds and tests do not grant OS permissions or publish/install a release.
