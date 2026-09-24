# Option restores minimized windows

Option now restores the highlighted minimized window. It never minimizes a visible window. App entries and Fold families resolve one exact minimized child by observed recency, then stable catalogue order. Browser tabs, unavailable targets, closed apps and ambiguous overflow groups do not dispatch restore actions. The worker rechecks the window's live AX minimized state, so repeated requests cannot toggle it back.

With Command–Tab, pressing Option restores the window and releasing Command selects that exact window. Further navigation or typing clears the pending restore selection. Press-to-open sessions also support a fresh Option press after the opening modifiers are released. Option remains available to native text input during search. Normal address/click/Enter selection still restores minimized windows.

A small monochrome minus badge sits on the lower-right corner of minimized window icons. App entries and Fold's collapsed groups carry it when they contain an available minimized window. The badge uses theme surface/text colours, has a stronger outline with the accessibility setting, and leaves the full icon recognizable. VoiceOver and tooltips describe the state. The same row component covers Shore, Beacons' fallback bank, Canopy children, Lattice tiles, Fold children and Relay cards/shelf, including search and Settings previews. State updates remove badges without replacing rows or addresses.

## Verification

- 78 core tests passed. Coverage includes restore target resolution in every mode, visible-window no-ops, app recency, unavailable children, browser-tab exclusion, ambiguous groups and live state reconciliation.
- 79 native tests passed, none skipped. Input replay verifies both Option keys, repeated modifier events, opening shortcut suppression, native search handoff, exact Fold child selection on Command release, and navigation after restore.
- The controlled duplicate-title fixture confirmed exact-window focus, restoration of two independently minimized windows, harmless repeated restoration and normal quit cancellation. Live state was deliberately newer than the cached window records.
- Renderer checks cover all six modes, normal/compact presentation, standard/extra-large labels, light/dark palettes, stronger outlines, search, tooltips, accessibility state and badge removal after restoration. They assert that badges stay inside their controls without overlapping text.
- Fourteen own-view PNG exports were visually reviewed; the final Fold exports were regenerated after correcting the badge position for its flipped AppKit coordinates. These exports use isolated preferences, and glass exports use the renderer's opaque fallback.

Native result: `../../build/OptionRestoreDerivedData/Logs/Test/Test-Tabnax-2026.09.20_06-26-43-+0200.xcresult`. Logs: `../../build/option-restore-tests.log` (core pass; its later shared-directory build was locked), `../../build/option-restore-native-tests.log` (complete native pass), and `../../build/option-restore-fixture-build.log`.

An embedded scrolling test was corrected to account for Settings reparenting its preview out of the unused switcher panel. Concurrent interface-cleanup changes, including the scroll viewport assertion, were preserved. Physical delivery through the live global event tap was not exercised in this task. No permissions, production installation or commits were changed.

## Reviewed layouts

| Layout | Full view | Minimized window |
| --- | --- | --- |
| Shore | Full (`shore-full.png`; local artifact, not published) | Minimized (`shore-minimized.png`; local artifact, not published) |
| Beacons | Full (`beacons-full.png`; local artifact, not published) | Minimized bank entry (`beacons-minimized.png`; local artifact, not published) |
| Canopy | Full (`canopy-full.png`; local artifact, not published) | Minimized child (`canopy-minimized.png`; local artifact, not published) |
| Lattice | Full (`lattice-full.png`; local artifact, not published) | Minimized tile (`lattice-minimized.png`; local artifact, not published) |
| Fold | Full (`fold-full.png`; local artifact, not published) | Minimized group and child (`fold-minimized.png`; local artifact, not published) |
| Relay | Full (`relay-full.png`; local artifact, not published) | Minimized card (`relay-minimized.png`; local artifact, not published) |

Additional compact/extra-large checks: Lattice (`lattice-compact-large.png`; local artifact, not published), Fold (`fold-compact-large.png`; local artifact, not published).
