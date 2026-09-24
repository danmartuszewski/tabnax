# Desktop spotlight verification

Verified on 2026-09-21 with Xcode 27, using isolated test preferences.

## Behavior

Appearance contains an enabled-by-default desktop spotlight and a 0–100% dimming slider in 5% increments, initially 35%. Zero retains the outline. Disabling preserves opacity. A fictional desktop example uses the same overlay drawing as the real switcher.

The real spotlight follows a highlighted catalogue window after verified raise/activation and visible geometry. Nonactivating, mouse-transparent panels cover each display below the switcher and Beacons plaques. Selection, cancellation, disabling, and unavailable targets remove the overlay. Settings previews and demo fixtures never raise windows or create desktop overlays; no screen capture is used.

## Completed checks

- Core suite: 86 passed, including older-settings migration, persistence, and opacity validation.
- Final native suite: 99 passed, one existing Accessibility-dependent focus fixture skipped. Spotlight coverage includes all layouts, panel reuse and cleanup, negative/vertical display coordinates, display removal, unavailable targets, preview isolation, opacity pixels, preserved sample-window content, settings persistence, and Undo.
- Own-view Appearance export inspected at `macos/build/desktop-spotlight/settings.png`. The selected example window stays readable while its surroundings dim.
- Live isolated Settings UI checked through macOS accessibility actions: toggle on/off, disabled-slider state, increment/decrement through 0%, 35%, 40%, and 100%, and Saved status.

## Verification limits

An exploratory XCUITest using mouse clicks and dragging did not change either standard control in this session; a coordinate drag through computer use was also inconclusive. Accessibility actions did change the controls immediately. The exploratory mouse test was not retained as automated coverage; native regression tests and the live accessibility checks above are retained evidence. Physical mouse interaction remains a manual check.

Multiple-display geometry is covered with fixture frames and live metadata; physical multi-monitor, native full-screen Spaces, and Stage Manager combinations were not exhaustively exercised. App families and browser-tab entries have no unique desktop window to preview. Minimized, hidden, and off-Space windows retain the usual final-selection behavior. A failed preview remains selectable without showing a misleading desktop outline.

## Primary-display visibility fix

The reported failure was reproduced from live window metadata on three connected displays. Notification Center supplied a display-sized layer-21 window with alpha 1 above all primary-display app windows. The old visibility check treated its entire rectangle as an obstruction, leaving only two secondary-display windows eligible. Selecting a rejected primary-display window dismissed every spotlight panel.

The visibility check now excludes Notification Center's non-normal windows only when their bounds match a connected display. Process identity comes from its bundle identifier; display bounds are converted from AppKit to Quartz points. Smaller notification windows, normal windows, other apps' floating windows, and unverified owners or bounds retain the existing obstruction check.

- Live AX bounds evaluated against the same window-server snapshot: eligible windows increased from two to five, restoring three primary-display windows and preserving both secondary-display windows.
- Native suite: 103 executed, 102 passed, one existing Accessibility-dependent fixture skipped. Added regression cases cover the desktop container on each display, preserved real obstructions, and selection moving from either secondary display back to the primary without dismissing any spotlight panel.
- Test log: `/private/tmp/tabnax-primary-display-tests.log`. Live checks read window geometry without focusing, moving, or capturing other windows. Manual keyboard/visual confirmation after restart remains separate from this metadata check.

## Bring highlighted windows forward

Highlight changes now submit a preview through the reserved focus lane. The exact AX window is raised and its app activated, with the existing bounded focus verification and repair. Preview activation keeps the switcher open, suppresses recent-window history updates, and refreshes occlusion before drawing the spotlight. Final selection supersedes pending previews; Escape restores the original history window. Search input is returned to the switcher after preview activation. The Desktop spotlight toggle controls both bringing windows forward and dimming.

An initial raise-only approach returned AX success but left a controlled fixture window behind another process's window. The verified activation path passed the same window-server stacking check. The retained fixture also checks that previewing does not call switcher dismissal or committed-selection callbacks.

- Native suite: 107 executed, 106 passed, one existing Accessibility-dependent fixture skipped. New checks cover covered-window eligibility, excluded targets, input-lane preview ordering, Enter/Escape/disabled behavior, original-window restoration requests, cancellation, final-selection precedence, and redraw when preview readiness changes.
- Direct fixture under existing Accessibility access: the overlap check passed, including proof that neither dismissal nor committed-selection callbacks fired. One complete run passed all 21 checks; a later repeat passed the new overlap check but had intermittent failures in the existing hidden-app restoration report and Relay history check. Only controlled test windows were changed.
- Logs and fixture report: `/private/tmp/tabnax-window-raise-tests.log`, `/private/tmp/tabnax-window-raise-fixture.json`.


## Smooth window transitions

Added an enabled-by-default dim-and-reveal transition, a Slow–Fast speed control, and a Try animation button in Appearance. The default duration is 0.2 seconds, bounded to 0.08–0.5 seconds. Older settings gain these defaults while retaining their existing dimming preference. Animation off or macOS Reduce Motion produces an immediate reveal.

The desktop remains dimmed during preview activation and geometry verification; it no longer flashes back to full brightness between windows. After verification, Core Animation fades the selected window's dimming veil and outline. These are GPU layer animations without timers or delayed focus actions. Selection changes and dismissal remove existing animations immediately. Application windows retain their positions; the animation affects the desktop overlay, not switcher item opacity. At zero dimming opacity, only the outline fades.

Validation: core and native test suites passed (108 native tests executed, one existing Accessibility-dependent test skipped). Added checks cover migration, persistence, validation, Reduce Motion, retained dimming while awaiting verification, rapid retargeting, cancellation, and animation-off behavior. The Appearance export at `macos/build/spotlight-animation/settings.png` was visually inspected; controls and the example render correctly. Test log: `/private/tmp/tabnax-animation-tests.log`.


## Switcher-only focus and updated defaults

New settings default to 75% selected-window dimming, animation enabled, and the user's saved duration of 0.13655945920658685 seconds. Existing saved values remain unchanged. The Focus picker offers Selected window and Switcher only. Switcher only has an independent 75% default opacity and uniformly dims all displays without a window cutout. Input routing suppresses preview raises/activation in this mode; normal final selection remains active. App, group, browser-tab, and empty-highlight navigation do not require window geometry for dimming. Disabling the feature or closing the switcher removes all panels.

Validation: 88 core tests passed; 110 native tests executed with no failures and one existing Accessibility-dependent test skipped. New coverage verifies migration/preservation, independent opacity persistence/validation, uniform pixel alpha across displays without a window target, dismissal, no preview callbacks during browsing, and successful final selection. The dark settings export at `macos/build/switcher-only/settings.png` was visually inspected using an isolated preferences domain, removed afterward. Test log: `/private/tmp/tabnax-switcher-only-tests.log`.
