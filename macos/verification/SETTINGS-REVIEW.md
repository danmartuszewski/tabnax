# Native settings review

Implementation review, 17 September 2026. This records native evidence separately from the earlier browser study. The browser study remains the visual/behavior reference; its synthetic tabs are not live-browser verification.

## Implemented behavior

- Five native settings panes: General, Selection, Position, Appearance and Browser tabs. The interactive preview embeds the actual AppKit switcher renderer and never focuses another app.
- Versioned validated settings, deterministic migration of the former mode/alphabet/shortcut keys, bounded Undo, future/corrupt-data preservation, and scoped recovery. Existing legacy left-hand order is preserved with Left as its restore reference.
- Selection drafts, presets and custom 6–20-key order, reordering, Remove I/O, Restore default order, stable/initials/pair policies, physical/character interpretation, runtime window/tab/Fold pins, namespace-scoped reset and Apply/Discard. Atomic shared label-session values cover flat windows, tab pairs, app prefixes and Fold children.
- Theme presets macOS, Tabnax green, Sage and Iris; System/Light/Dark; separate per-tone overrides and color/preset resets; automatic readable key text and selection contrast; larger labels and essential row text; stronger outlines.
- Each of six modes remembers display choice, nine-position anchor and inset. Placement is frozen on opening and clamped to the usable screen. Beacons retains independent window plaques.
- Recorded shortcut, suggested-chord recovery, latch/hold, explicit modifier sides, and suspension of the global activation route while recording. Hold release cancels; it never selects.
- Minimized/hidden eligibility preserves reservations. Login-item registration uses SMAppService and displays actual observed status. Failed registration keeps working settings.
- Mouse Off / Click / Click + wheel. Local surface gating, first-click controls, captured press callbacks, session stamps, bounded precise-wheel accumulation, momentum exclusion, identity highlight, bank-only Beacons navigation and separate Fold regions. Accessibility actions remain available with physical mouse control off.
- Windows / Browser tabs / Running apps are visible on keys 1 / 2 / 3. Tabs have an independent pair namespace in every mode. Active-session identity sets are frozen; closures update availability and metadata without admitting a new meaning for a typed label.

## Browser implementation and limits

Arc, Chrome, Edge and Brave have built-in Apple-event adapters. Discovery checks installation/running/approval without requesting consent; explicit setup requests Automation approval. Reads exclude incognito windows before collecting tab titles. Selection finds the exact browser tab ID, prefers its observed parent window, activates that window and verifies the active tab. Browser workers are bounded and scripts have a timeout.

Zen and Firefox share a WebExtensions companion and a native messaging host. The host derives the browser from its parent application; the native app validates same-user peers and expected executable paths. Safari has an embedded Safari web-extension target and request/reply adapter. All use a local Unix socket, framed bounded JSON, independent connection UUIDs, exact tab/window activation and private-tab rejection. Disabled connections pause metadata updates; an explicit acknowledgement, not a settings checkbox, establishes connection health. No page-content permissions, content scripts, profile-database reads or remote debugging are used.

**Distribution gates:** the Firefox/Zen companion is source-only until a signed add-on is produced. The app installs the native-host manifest through Set up, but browser-owned add-on installation/approval remains necessary. Safari’s local development extension requires Safari approval for unsigned development builds; production signing and its scoped local-IPC entitlement need release validation. No store extension or signed installer was published.

**Live verification gates:** Accessibility and per-browser Automation/add-on approval must be provided through macOS/browser UI. Tests that lack these permissions are recorded as skipped, never passed. Cross-browser workspace/split-view behavior and physical Magic Mouse/trackpad hardware are not established by synthetic or XCTest events.

## Issues found and corrected during implementation

- A transparent settings content background rendered black in view captures; added an explicit native window background.
- The accessory app lacked standard Edit responder commands; alphabet-field Select All now works.
- Unselected toolbar labels had gaps in their hit area; the full toolbar tile is now clickable.
- Fold’s app actions were exposed as checkboxes; changed them to action buttons.
- Lattice navigation previously counted hidden descendants rather than visible branches; it now traverses actionable cells.
- Mouse-off originally risked disabling assistive actions; physical event gating keeps semantic accessibility activation intact.
- Broad outside-click classification used all app windows and a later pointer location; it now uses the event’s location and only published switcher surfaces.
- Tab pins and assignment reset scope were missing in the first native pass; window, tab and Fold pins/resets now preserve unrelated namespaces, and a staged pin survives a compatible later draft edit.
- Browser filters now affect the native preview, and login registration runs only through a validated settings commit.
- Native scroller gutters clipped the trailing badges; row sizing reserves the gutter, and compact layouts use the actual clamped frame size.
- Browser IPC writes now use a bounded background queue and disconnect stalled peers; companion acknowledgements also require the correct connection and foreground browser.
- XCTest sent Escape to a borderless app-level target without window bounds; the test now targets the visible control. The presenter routes direct keys before native panel cancellation.
- System appearance/Increase Contrast changes refresh an open switcher without changing its labels.
- Enlarged Beacons plaques and Fold/Relay section spacing now grow with their labels; narrow Fold previews use tiles to preserve complete codes. Fold family selection now has an explicit theme-colored highlight and an accessible Selected value.
- Reopening/activating the settings window raises it; the final reopen/persistence flow passed.
- Safari’s generated extension Info.plist initially omitted its version; explicit build-version settings now match the parent app, and Release validation confirms them.
- Short-label exhaustion previously omitted targets; unaddressed targets remain available through search/click/navigation.

## Primary implementation references

- [Mozilla native messaging and manifest locations](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_manifests)
- [Zen extension support](https://docs.zen-browser.app/user-manual/extensions)
- [Apple Safari native messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)
- Installed Arc/Chromium scripting dictionaries and SDK IOLLEvent modifier-side masks were inspected locally. Declared dictionaries are not proof of successful live focus.

Final build/test counts, renders and remaining live gates are recorded in the implementation tracker and verification results after the final checks.
