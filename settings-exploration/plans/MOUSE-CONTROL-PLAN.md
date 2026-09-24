# Optional mouse control — implementation plan

Prepared 17 September 2026. Status: **planned; mouse preferences and wheel selection are not implemented by this document**. The request is to open Tabnax with its shortcut, then optionally use clicks or a scroll wheel, with a consistent contract across Shore, Beacons, Canopy, Lattice, Fold and Relay.

| Phase | Steps | Done | Status |
| --- | ---: | ---: | --- |
| Phase 0: prerequisites and event-routing checks | 2 | 1 | Source audit complete; native probes pending |
| Phase 1: preferences and shared interaction state | 3 | 0 | Planned |
| Phase 2: native controls and six-mode previews | 4 | 0 | Planned |
| Phase 3: integration, accessibility and acceptance | 3 | 0 | Planned |
| Phase 4: optional enhancements | 2 | 0 | Deferred; not required for initial delivery |
| **Total** | **14** | **1** | **Initial delivery requires Phases 0–3** |

Workspace: `.`. Native app and settings study are in the same workspace, under `macos/` and `settings-exploration/`. No Git repository was detected at the workspace root during this audit; no branch or commit is created by this plan. Recheck repository state and concurrent edits before implementation.

## Intended experience

1. Open Tabnax with the existing shortcut. The panel appears at its saved position; opening does not choose whatever happens to be beneath the pointer.
2. Click a window/tab to select it, or click a branch to open its next stage.
3. If wheel selection is enabled, scroll over the switcher to move a visible highlight. Scrolling alone never focuses an application, activates a tab or changes Relay history.
4. Click the intended target to commit. Enter follows the visible mode command: normally choose the highlighted item; in Relay’s window view it remains **Return to previous window**.
5. Letters, search, Escape and Backspace continue to work. Moving the pointer never rewrites a label or changes a partially typed address.

This is optional mixed keyboard/mouse navigation. It adds neither automatic focus-on-hover nor selection-on-shortcut-release.

## Scope and current evidence

**Included in initial delivery:** one shared mouse preference; physical primary-click selection; ordinary content scrolling or opt-in wheel selection; visible hover/navigation feedback; all six mode contracts; exact-identity selection through the existing focus path; settings persistence; equivalent browser-study behavior; automated and native device acceptance checks.

**Deferred:** native Hold to show until its activation engine exists and is verified; wheel selection while the pointer is outside Tabnax. These are separately gated Phase 4 tasks.

**Out of scope:** drag to rearrange or move real windows/tabs, closing targets with middle-click, right-click menus, wheel-triggered focus, hover dwell activation, pointer warping, gestures that replace system gestures, per-app mouse profiles, browser adapter implementation, a new accessibility permission flow, and production distribution/deployment.

The two implementations are at different stages. Keep their capabilities explicit:

| Area | Observed implementation | Planning consequence |
| --- | --- | --- |
| Native presenter | `ModePresenter.swift` creates nonactivating panels, `TargetRow`/`ActionButton` controls, an `NSScrollView`, Fold branches and Lattice cells | Build on these controls; do not replace selection with synthetic clicks on other apps |
| Native input | `InputRouter.swift` watches mouse-down events to supersede pending focus; outside dismissal checks the later pointer position against all visible `NSApp.windows` | Replace this broad, delayed classification with the exact switcher-surface/session contract below |
| Native selection | `SelectionState` owns active state, prefix, query and an integer cursor. Next/previous wraps; Relay Enter has a dedicated meaning | Introduce identity-based actionable navigation; do not blindly map wheel events to the current integer cursor |
| Native settings | `SettingsController.swift` and `Preferences` in `Support.swift` have no mouse preference. Activation is latched | Add mouse preferences independently of Apply & Reset Addresses; do not advertise native hold support |
| Native scopes | Windows and Running apps; `1` / `2` | Cover both. Do not silently repurpose `2` to mean Tabs |
| Settings study | Windows and Browser tabs; all seven sample browsers; targets are clickable even outside an armed preview; wheel scrolling is ordinary DOM scrolling | Add a real active-session gate for simulated target selection and the same mouse choices. Scope buttons and settings remain usable while the preview is idle |
| Browser integration | Tab fixtures are not native browser adapters | Cover tab interaction in the study and specify adapter integration acceptance; native browser support is a separate dependency |

Sources inspected: [native input](../../macos/Tabnax/InputRouter.swift), [presenter](../../macos/Tabnax/ModePresenter.swift), [selection state](../../macos/Packages/TabnaxCore/Sources/TabnaxCore/Selection.swift), [native settings](../../macos/Tabnax/SettingsController.swift), [preferences](../../macos/Tabnax/Support.swift), [native coverage](../../macos/MODE-COVERAGE.md), [browser controller](../app.js), and [six-mode study contract](../SIX-MODE-COVERAGE.md). The existing 481 study assertions describe the earlier implementation; they are not evidence that this new option works.

## Settings, defaults and copy

Put the control in **General → Mouse & trackpad**, after Activation. In the current native settings window, use an equivalent compact group below the activation choice; adopting the complete five-pane design is not a prerequisite.

| Choice | Physical clicks inside the switcher | Wheel over switcher content | Default |
| --- | --- | --- | --- |
| **Off** | Target, branch and scope clicks do not navigate or select | No target navigation or content-wheel scrolling | Optional keyboard-only interaction |
| **Click to select** | Target selects; branch opens; scope button changes scope | Normal content scrolling; no selection-cursor movement | **Default**, preserving current click/scroll behavior |
| **Click + wheel selection** | Same click behavior | Move the navigation highlight; reveal the highlighted item as needed | User opts in |

Use a single three-choice popup, rather than a master checkbox plus combinations that can conflict. Mouse movement may show a modest hover outline in the two enabled choices, but never changes the navigation highlight by itself. Off removes physical target hover/press feedback. Off applies to switcher navigation only: Settings and the explicit Close control remain clickable; ordinary text editing within an already-open search field remains native. Do not turn target controls into disabled accessibility elements just because physical mouse navigation is off.

Help text:

> Open with your shortcut, then click a target. Wheel selection moves the highlight without switching windows. Mouse control only applies inside Tabnax.

When Off:

> Choose targets with the keyboard. Close and accessibility actions remain available.

Mode-specific footer examples:

- Shore/Canopy/search: “Wheel: choose a highlight · Click or Enter: select”.
- Lattice/Fold branch stage: “Wheel: choose a branch · Click or Enter: open”.
- Relay window view: “Wheel: choose a highlight · Click: select · Enter: previous window”.
- Relay search: ordinary result selection, with Enter selecting the highlighted result.

Persist proposed `interaction.mouseControl = "off" | "click" | "clickAndWheel"`. Native preference storage must use an equivalent validated enum. Missing or unknown values resolve to `click`; do not infer a new default from the last input device. The schema remains a proposal until updated by task 1.1. Preference changes persist independently of label drafts, never reset addresses, and apply at the next opening. Changing it while a switcher is open cancels that session before publication. Browser Undo/Restore defaults include this preference; native recovery must at least allow selecting Click to select again without an address reset.

## Interaction contract

### Session, press and focus ownership

- Input is accepted only for an active switcher session and a surface belonging to that session. Opening captures the preference, mode, scope, address generation and navigation order.
- Opening beneath a stationary pointer creates no synthetic hover, branch choice or selection. Pointer hover is decorative; wheel, keyboard navigation and explicit clicks express intent.
- A primary press records the logical target/branch, session generation and action kind. Selection happens on release over the same action, after checking that its identity is still eligible. Dragging away cancels the press; no drag action is introduced.
- A click on a row icon, title or key badge means the same complete target. Do not make small glyphs the only hit area. Tooltips and accessibility labels expose the full title and complete address.
- Duplicate delivery through a button, local monitor and event tap must produce one action. A double-click has no special Tabnax command; the first completed action closes the session and later callbacks cannot select again.
- Cancellation or target closure during a press invalidates the action immediately. The matching release must not activate a newly exposed underlying control. Phase 0 must verify AppKit tracking and, if needed, narrowly scoped mouse-pair ownership before this behavior is released. Do not leave a hidden panel consuming unrelated future mouse events.
- A completed target action goes through `SelectionState` → `InputRouter` → `FocusCoordinator`. No renderer calls AX focus independently. Stale session/identity, revoked capability or a failed focus request produces no guessed sibling selection.
- Existing observed-focus history remains authoritative. Hover, wheel, branches, settings edits and failed requests never create a Relay history entry.

### Boundaries and cancellation

“Inside Tabnax” means the actual bank/panel or Beacons plaque rectangles for the current session, not their combined bounding box and not every Tabnax settings/menu window. Transparent space between plaques belongs to the underlying app. Use event coordinates captured at dispatch, not a later `NSEvent.mouseLocation` read.

In both enabled choices, primary click on panel background is a no-op. Secondary/middle/extra buttons inside the overlay have no switching command. They are not forwarded through the overlay to a covered application. Off similarly consumes physical clicks delivered to its target surfaces without selecting. Close remains an explicit exception.

A click outside the switcher cancels it, invalidates pending Tabnax focus work and continues normally to its actual destination. Never replay a click synthetically. Merely moving outside does not cancel. Outside scrolling remains ordinary application input and does not navigate Tabnax. The initial release does not capture wheel events globally, so it must not claim reliable detection/cancellation of every scroll in another application. Focus supersession continues to use the existing verified key/click/activation paths.

Escape, shortcut toggle, lock/sleep, permission loss, tap loss, session replacement and display disconnection cancel pointer navigation and discard gesture state. Preference Undo does not resurrect a pointer press or a previous session.

### Keyboard, search and hold interaction

- Complete typed addresses retain immediate final-key selection. A valid partial address restricts wheel candidates to that branch; scrolling does not erase or expand it. Typing resumes against that prefix, independently of the hovered item.
- A pointer-entered branch uses the same logical prefix command as a typed branch. Backspace removes one prefix character; the explicit breadcrumb follows its documented parent action. No timing requirement is added between stages.
- `/` opens global search and clears branch context. Wheel selection over the results changes the highlighted result without editing text. IME composition, selection and scrolling inside the text field remain AppKit/browser text behavior. Query changes reset result navigation by identity; no stale result may be committed.
- Relay Enter remains the previous-window command throughout its direct Windows view, including after wheel movement or arrow navigation. Do not make Enter silently change meaning because the last input was a mouse. In search and non-window scopes it follows ordinary selection.
- Native arrow/Tab navigation should consume the same visible actionable-item projection as wheel navigation. Existing keyboard wrapping may remain; wheel navigation clamps. Lattice branch Enter must open the highlighted branch instead of selecting a descendant that is not the highlighted cell. Document and test this specific navigation correction. Letter-address behavior is unchanged.
- **Latched shortcut, initial native delivery:** release the shortcut and click/scroll normally. Residual activation modifiers must not prevent target selection or enter a context-menu path. Modified input outside Tabnax retains its ordinary meaning.
- **Hold to show, future native engine:** no automatic conversion to latch on mouse movement. Clicking commits only if the held session is still valid on release. Releasing the activation key/modifier before mouse-up cancels; the pending press cannot commit later. Wheel/hover alone never commits on release. Releasing after a completed selection cannot repeat or undo it. Missed key-up, device loss and both-side modifiers require native tests. The browser Shift surrogate can exercise this rule now, but is not evidence that native hold is implemented.

### Wheel behavior and normalization

Click to select delegates scrolling to the normal scroll view. In Click + wheel selection, intercept wheel events only over the current switcher’s navigation content; Settings controls, editable text and scrollbar dragging keep their normal behavior. One event either navigates or scrolls content, never both. Prevent DOM scroll chaining into the settings page when a simulated navigation region owns the gesture, including at a boundary.

Build a small testable normalizer. Its input carries device precision, delta units, direction, phase, momentum phase, region and session generation. Its output is a bounded step command, not a focus intent.

- Detented/non-precise input starts with one directional navigation step per delivered nonzero vertical event; validate coalesced-device behavior in Phase 0 before promising a physical-notch mapping.
- Precise trackpad/Magic Mouse input accumulates logical distance. Start with a **40-point threshold** as a calibration candidate, not a shipped constant; reset the remainder on direction reversal or session/region change and bound each update to at most five items. Test and record the selected threshold; expose no sensitivity slider initially.
- Respect the system’s configured scroll direction once. Do not apply a second inversion simply because `isDirectionInvertedFromDevice` is set. Verify direction using recorded device sequences and both system settings.
- Ignore momentum for selection navigation. Do not allow a previously started gesture to navigate a freshly opened panel. A fresh phase-bearing gesture must begin in the current session/region; phase-less wheels need the explicit non-precise path. Reset on phase cancellation/end and on keyboard, branch or scope transitions.
- Horizontal-only input never selects another mode, scope or group. Lock a mixed gesture to its predominant axis. Navigation gestures are vertical; Shift-modified horizontal scrolling remains content behavior where supported and must not also advance selection.
- Clamp at the first/last enabled item; no wrap to the opposite end. Empty sets do nothing. Disabled/closed/held cells remain visible but are skipped as actionable candidates. An otherwise eligible target with exhausted short-label capacity stays reachable through search and enabled pointer selection; lack of an address is not lack of target availability. Stop automatic reveal when the action is no longer valid.
- Keep the highlighted logical identity stable while its row is scrolled into view. Scrolling content under a stationary pointer must not change that highlight. Scrollbar dragging changes viewport only.

Apple documents distinct active and momentum scroll phases, including different event destinations during momentum. These facts motivate explicit gesture/session guards; the threshold and clamping choices above are Tabnax design decisions. [Apple: Handling Trackpad Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html).

## Required behavior in every mode

| Mode | Primary click | Wheel-selection order and region | Commit / recovery / special case |
| --- | --- | --- | --- |
| **Shore** | Select the clicked complete target | Stable list order inside the list; prefix/search restricts candidates | Enter selects highlighted target; boundaries clamp; reveal hidden rows without relabeling |
| **Beacons** | Plaque selects its window; bank row selects that exact off-screen target | Bank wheel navigates the bank only. Wheel on an isolated plaque does not traverse distant plaques; that target is directly clickable. Global search supplies a unified scrollable view | Plaques and bank share session ownership. Moving between displays/plaques does not activate an app. Actual geometry freeze and hit testing must prevent a plaque moving under a press |
| **Canopy** | Select a child directly; app/browser headings have no extra activation action | Group order, then stable child order; in native columns traverse down a group before the next group, independent of column reflow | Enter selects target. No wheel-generated app stage. Native grouping and browser-window grouping use the same rule |
| **Lattice** | Target cell selects; branch cell opens; held/empty cell does nothing | Visible actionable cells in alphabet order; branch cells are items, not flattened hidden descendants. Inside a branch use its next grid | Enter on highlighted branch opens it. Backspace/breadcrumb returns. A label never moves to another identity because a cell is skipped |
| **Fold** | App button opens that family; child selects; singleton still requires child stage | At root, app families. In a child sheet, its children. A gesture over the spine navigates families without opening them; over the sheet navigates that sheet. Lock one region per gesture | Click/Enter on highlighted app opens it; child click/Enter selects. Switching family clears old child highlight; no automatic family opening from wheel alone. Full app+child labels remain visible |
| **Relay** | Click current/previous/other target, or the explicit Return control | Current, previous, then remaining live targets, de-duplicated. Return button is not a duplicate wheel stop | Enter in direct Windows view always returns; click chooses the highlighted/different target explicitly. A missing/filtered previous window disables return. Navigation never updates history |

Shared search is a flat result projection in every mode. Browser tabs in Shore/Beacons/Fold/Relay use the declared two-letter list; Canopy uses browser-window groups; Lattice uses branch/leaf grids. Filtering to Arc, Zen or any supported combination keeps tab identities and labels unchanged. Browser workspace/profile context remains part of the accessible target name when supplied by its adapter.

Native Running apps keeps the existing explicit scope and its documented list/grid presentations. Fold app-family selection in Windows scope must not be confused with activating a running app in Apps scope. Native tabs remain a future adapter integration; these mouse settings must be reusable when that scope is added, without changing the existing numeric commands silently.

## Architecture and concurrency boundaries

Use a pure actionable projection shared by keyboard navigation, wheel navigation and visual highlighting:

```text
NavigationItem = target(TargetID) | branch(prefix, familyID?)
NavigationRegion = list | bank | grid | appSpine | childSheet | searchResults
NavigationFocus = item identity + region + source(keyboard | wheel)
PointerPress = sessionID + addressGeneration + action identity + button
WheelGesture = sessionID + region + axis + remainder + phase state
InteractionPreferences = mouseControl
```

Names are proposed. Keep hover identity separate from navigation focus, active native window and Relay history. A row index is a projection result, never the authority used to commit. Revalidate generation, scope, branch membership and availability before accepting an action. Metadata-only updates can refresh a label’s text; new targets wait for a fresh navigation snapshot, and confirmed closure disables/removes that identity without transferring its press or highlight. If a pressed target disappears, cancel that press; navigation may then choose the next surviving item only after another explicit navigation action.

The main actor owns AppKit surfaces, text editing, hit regions and visual state. The input lane owns semantic selection and accepted actions. Send immutable session-stamped commands through the existing bridge; drop commands from stale presentations. Never query AX, wait for main-thread layout, enumerate all windows, or perform focus verification in a wheel callback. Presentation may coalesce redraws, while bounded navigation commands preserve intended movement and final-key selection stays independent of drawing.

Use AppKit responder/scroll-view handling first. If a local event monitor is needed, scope it to registered switcher windows and remove it when the session ends. A global `NSEvent` monitor cannot suppress events, so it cannot implement exclusive wheel navigation over other apps; that enhancement needs its own feasibility decision. [Apple: Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html).

Verify the first click on the nonactivating bank and each plaque. Evaluate `acceptsFirstMouse(for:)` in the actual control hierarchy where necessary, rather than assuming the panel style guarantees first-click delivery. [Apple: acceptsFirstMouse(for:)](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse(for:)).

Do not disable `TargetRow` or `ActionButton` globally for mouse Off: they must retain keyboard and accessibility activation. Separate physical pointer-origin checks from semantic `accessibilityPerformPress`/keyboard actions. Restrict any event suppression to the registered surface and, if required by the Phase 0 probe, the exact owned mouse pair. Retain independent cancellation of obsolete focus requests on ordinary external user input.

## Phased tasks

File names marked **new** are proposed files. All paths below are relative to the workspace root. Adding native source/test files must also update `macos/Tabnax.xcodeproj/project.pbxproj` where the existing project requires explicit membership.

### Phase 0: prerequisites

| Task | Status | Size | Dependencies | Affected files / areas | Description and acceptance |
| --- | --- | --- | --- | --- | --- |
| 0.1 Audit existing behavior | [x] | S | None | Native input/presenter/core/settings; study input/modes; this plan | Record current click, scroll, latch, scope and Relay contracts; identify native/study differences and Apple event constraints. **Accepted:** findings and source links above; no new behavior claimed |
| 0.2 Probe native event delivery | [ ] | M | 0.1 | `macos/TabnaxTests/NativeContractTests.swift`; `macos/TabnaxUITests/TabnaxUITests.swift`; `macos/verification/mouse-routing.md` **new** | Probe first click, press-release tracking through cancellation, residual shortcut modifiers, exact outside hit testing, negative-origin displays and wheel phases on real devices. **Accepted:** documented event traces and a bounded ownership design; blocked sequences identified before production routing edits |

### Phase 1: core preferences and state

| Task | Status | Size | Dependencies | Affected files / areas | Description and acceptance |
| --- | --- | --- | --- | --- | --- |
| 1.1 Add preference contract and recovery | [ ] | S | 0.1 | `macos/Tabnax/Support.swift`; `settings-exploration/model.js`, `settings.schema.json`, `CONFIGURATION.md` | Add validated enum/default/migration; keep runtime pointer state out of persistence. **Accepted:** missing/unknown values use click; all choices round-trip; changing preference never touches allocators; study Undo/defaults restore it |
| 1.2 Add actionable navigation model | [ ] | M | 0.1 | `macos/Packages/TabnaxCore/Sources/TabnaxCore/Selection.swift`; `PointerNavigation.swift` **new**; matching `Tests/TabnaxCoreTests/PointerNavigationTests.swift` **new** | Model target/branch items, regions, identity focus, clamped wheel movement and correct branch activation. **Accepted:** six-mode order, empty/unavailable/held entries, prefix restrictions, Relay Enter, Fold singleton, stale-generation rejection and identity retention pass pure tests |
| 1.3 Add session-stamped input handoff | [ ] | L | 0.2, 1.1, 1.2 | `macos/Tabnax/InputRouter.swift`, `AppDelegate.swift`, `FocusCoordinator.swift` as required; `NativeContractTests.swift` | Replace broad outside-window classification; route pointer intents through existing selection/focus pipeline; implement narrowly necessary press ownership. **Accepted:** one intent per action; no stale callbacks, swallowed outside clicks, synthetic event replay, stuck ownership or AX work in callbacks; keyboard fast path and focus supersession regressions pass |

### Phase 2: controls, wheel input and six modes

| Task | Status | Size | Dependencies | Affected files / areas | Description and acceptance |
| --- | --- | --- | --- | --- | --- |
| 2.1 Add native settings and click policy | [ ] | M | 1.1, 1.3 | `macos/Tabnax/SettingsController.swift`, `ModePresenter.swift`, `AppDelegate.swift`; `TabnaxUITests.swift` | Add compact three-choice control, accurate help, first-click selection and physical-origin gating. **Accepted:** default preserves current behavior; Off blocks physical target/branch/scope selection while Close, keyboard, search editing and accessibility remain usable; preferences save independently of label-reset action |
| 2.2 Normalize wheel navigation | [ ] | M | 0.2, 1.2, 1.3 | `macos/Tabnax/PointerEventAdapter.swift` **new**; `ModePresenter.swift`; core `Sources/TabnaxCore/WheelNormalizer.swift` and `Tests/TabnaxCoreTests/WheelNormalizerTests.swift` **new** | Separate native content scrolling from wheel selection; normalize precision, phases, direction and bounded steps. **Accepted:** no momentum carryover, no global wheel capture, no duplicate scroll/navigation, clamped boundaries, horizontal-input isolation and recorded-device cases pass |
| 2.3 Bind all native mode regions | [ ] | L | 2.1, 2.2 | `macos/Tabnax/ModePresenter.swift`; `macos/Packages/TabnaxCore/Sources/TabnaxCore/ModeLayout.swift` only if region/order data is needed; `ModeTests.swift`, `TabnaxUITests.swift` | Bind hover/focus/press styling, breadcrumbs, viewport reveal and six rows of the behavior matrix. Preserve geometry during pointer interaction and prevent remounts from losing an owned press. **Accepted:** every existing native scope works in every mode; Beacons bank/plaque separation, Canopy order, Lattice branches, Fold regions and Relay return remain correct |
| 2.4 Extend settings study | [ ] | M | 1.1, 1.2 and settled 2.2 semantics | `settings-exploration/index.html`, `app.js`, `modes.js`, `styles.css`; `pointer.js` **new** if useful; `package-standalone.py`, `tabnax-settings.html`; `tests/mouse-control-checks.js` **new** | Add same settings/copy and simulated session navigation, using DOM wheel units and scoped non-passive handling where needed. Preserve normal page/settings scrolling. **Accepted:** clicks select only during active preview; all six modes and all seven sample browsers; Off/default/wheel modes, search, branch recovery, Shift-hold cancellation, persistence and responsive layout work. Rebuild standalone from source |

### Phase 3: verification and delivery

| Task | Status | Size | Dependencies | Affected files / areas | Description and acceptance |
| --- | --- | --- | --- | --- | --- |
| 3.1 Run automated regression matrix | [ ] | M | 2.3, 2.4 | Core tests, `NativeContractTests.swift`, `TabnaxUITests.swift`; study tests; verification reports | Execute the acceptance cases below plus existing relevant suites. **Accepted:** native and study results separately recorded; no counting simulated gestures as native hardware evidence; all failures resolved or feature explicitly withheld |
| 3.2 Verify hardware and accessibility | [ ] | M | 3.1 | `macos/verification/mouse-routing.md`; `macos/verification/mouse-control-results.md` **new** | Test detented mouse, Magic Mouse and trackpad; both scroll directions; VoiceOver, Full Keyboard Access, enlarged text, contrast and multiple displays. **Accepted:** one-click operation without unintended activation, visible navigation, no input loss, no live focus changes from scrolling, and usable physical-Off accessibility path |
| 3.3 Update contracts and review artifacts | [ ] | S | 3.1, 3.2 | `macos/MODE-COVERAGE.md`; study `SPECIFICATION.md`, `INVENTORY.md`, `SIX-MODE-COVERAGE.md`, `EVALUATION.md`, `VERIFICATION.md`, `README.md`; this tracker | Replace planned labels only for completed behavior; add six-mode examples/screenshots and limitations; record chosen normalizer constants and recovery results. **Accepted:** docs match shipped-in-workspace capabilities, no native tab/hold claims beyond evidence; no commit or production deployment without a separate request |

### Phase 4: optional enhancements, outside initial acceptance

| Task | Status | Size | Dependencies | Affected files / areas | Description and acceptance |
| --- | --- | --- | --- | --- | --- |
| 4.1 Integrate a native held shortcut | [ ] | L | 3.3 plus a separately verified hold activation engine | `InputRouter.swift`, core ownership/session state, native settings/tests | Apply the hold contract above. **Accepted:** modifier/main-key release, release during press, missed key-up and device loss cancel without selecting; release after commit does not repeat. Do not expose unsupported native activation choices |
| 4.2 Evaluate wheel outside the panel | [ ] | L | 3.3 plus a concrete need and separate capability review | Input transport, event ownership, settings and native verification | Consider a separate explicit option only if panel-local selection proves insufficient. **Accepted before adoption:** original app cannot scroll simultaneously, lifecycle cleanup is reliable, permission/transport needs are established, and event consumption is disclosed. A global observer alone is insufficient; defer if these requirements cannot be met |

## Acceptance matrix

Run base functional cases for **six modes × three mouse choices × every scope actually supported by that implementation**. Add hierarchy/search cases where they apply; avoid padding test counts with equivalent assertions.

| Area | Required cases / expected result |
| --- | --- |
| Opening | Shortcut opens under stationary pointer with zero selection; first click works on bank and plaque; mouse alone cannot open/activate the idle preview |
| Click intent | Icon/title/badge all select the same exact target; press-drag-out cancels; closure/revision/permission loss between down/up prevents selection; duplicate callback cannot focus twice |
| Off | Physical target, branch, scope and wheel navigation blocked; no click-through beneath surfaces; settings/Close work; keyboard and accessibility activation still work |
| Scrolling | Default scrolls content without moving navigation focus; opt-in wheel moves focus and reveals content without double-scrolling; first/last clamps; empty and disabled-only regions are inert |
| Device streams | Positive/negative coarse deltas, coalesced events, tiny precise deltas, reversal, large deltas, phase-less events, momentum, gesture starting before opening, mixed axes and residual shortcut modifiers |
| Modes | Each behavior-matrix row; branch Enter/Backspace, singleton Fold, return-target absence and a Relay wheel highlight different from the previous window |
| Hybrid input | Type prefix → wheel → complete label; wheel → search → Enter; pointer branch → type child; Escape at each stage; pointer leaves region mid-gesture; stationary pointer while content scrolls |
| Identity / focus | Two same-title siblings; hidden/minimized/unavailable target; catalogue update during press; delayed focus completion followed by external click; navigation never writes history |
| Scopes / browsers | Preserve native Windows/Apps commands; preserve study Windows/Tabs commands; Arc/Zen filters and remaining sample browsers; same-title tabs in different windows; exact tab/window focus is a native-adapter gate |
| Displays | Negative-origin external screen, scaled display, panel on another monitor, Beacons gaps, display removal and changing visible frame during a press; no pointer-driven repositioning |
| Accessibility | Full action names, logical focus order, visible hover versus navigation versus current-window states, keyboard-only completion, native accessibility press with physical mouse Off, enlarged labels without clipping |
| Lifecycle | Preference change, mode/scope change, session replacement, lock/sleep/tap loss, repeated opening, cancel during a press and device disconnect; no leftover capture, stale gesture or stuck panel |

Use deterministic replay for state/normalization tests, browser events for study behavior, and controlled native fixtures for exact focus. Browser `wheel` events do not expose AppKit momentum phases, so native replay/hardware verification is mandatory. Native integration testing should not install new permissions or change consent as a side effect; record missing capabilities as a test boundary.

## Key decisions and alternatives

| Decision | Why chosen | Alternative rejected/deferred |
| --- | --- | --- |
| Click to select is the default | Both existing implementations already support target clicks and content scrolling | Silently disable existing clicking, or make wheel navigation the default |
| One shared three-choice setting | Clear states and easy recovery across six modes | Per-mode checkboxes or a separate setting for every mouse button |
| Wheel navigates, explicit action commits | Avoid involuntary focus changes and preserve Relay history | Switch on each tick, dwell, or commit on wheel/shortcut release |
| Panel-local wheel input | Matches normal event ownership and can coexist with other apps’ scrolling | Global wheel interception in initial delivery |
| Hover is decorative | Prevent a stationary pointer from overriding keyboard/wheel intent after layout/scroll | Focus follows hover or app opens on hover |
| Preserve Relay Enter | Keeps the mode’s defining command predictable | Enter changes meaning based on last input device |
| Navigate visible branches | Wheel highlight and Enter correspond to what is shown | Flatten hidden Lattice descendants or skip Fold singleton stage |
| Separate pointer/AX origins | Off is a physical input preference, not an accessibility lockout | Disabling every target button and losing VoiceOver activation |
| Keep native/study scope differences explicit | Prevent command conflicts and false browser-support claims | Treat native Apps as if it already meant browser Tabs |

## Rollback and release boundaries

Event ownership and asynchronous focus are the high-risk portions. Keep a last known-good native build and record the affected-file diff before changing routing. Introduce mouse navigation behind the preference and an internal rollout guard until native acceptance is complete. Never reset learned addresses as part of recovery.

If wheel behavior fails, select **Click to select**, cancel the current session, detach navigation interception and restore ordinary scroll-view behavior. If a routing regression affects clicks or keyboard use, disabling the new mode is insufficient: revert the new routing/ownership changes to the baseline, clear owned gestures and run cancellation/key-pair/focus regressions. Preserve compatible preferences and ignore unknown enum values safely; remove only session-owned monitors/capture, never revoke system consent.

There is no production deployment in this request. Completion means a tested workspace change and reviewable prototype/native evidence. Packaging, signing, distribution, browser installation and committing require their own requested work. This plan itself changes documentation only.
