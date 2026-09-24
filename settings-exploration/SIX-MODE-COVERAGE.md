# Required function coverage across six display modes

Audit and implementation update: 17 September 2026. The user requested settings coverage for all six modes. **Appearance → Show windows as** now selects Shore, Beacons, Canopy, Lattice, Fold or Relay. Each has a working settings preview. The original gallery remains unchanged as the historical comparison artifact.

This matrix distinguishes required behavior from optional preferences. Covered means implemented in the browser simulation and represented in the native contract, not verified native macOS operation.

## Coverage matrix

| Mode | Required window behavior | Selection and recovery | Position | Browser tabs | Coverage |
| --- | --- | --- | --- | --- | --- |
| **Shore** | Compact icon/title/key index; all eligible windows reachable | Direct stable labels; reserved overflow prefix; search, pins, reset and Undo | Defaults middle right; configurable panel anchor, display and inset | Compact two-letter list | Covered in settings preview |
| **Beacons** | Plaques for exposed windows; out-of-sight bank for covered, minimized and hidden windows | Same flat labels as Shore; bank targets remain directly selectable; filtering retains reservations | Plaques follow window geometry. Position settings govern the bank and tab list; default bottom center | Compact list because individual tabs have no desktop rectangle | Covered with explicitly synthetic geometry; native collision/visibility handling remains a gate |
| **Canopy** | Group windows by app while showing complete direct labels | Group headings add no keyboard stage; search crosses groups | Defaults top center; grouped panel remains within usable screen | Group by browser and browser window, retaining available workspace context and existing pair labels | Covered in settings preview |
| **Lattice** | Stable address cells with held places; visible overflow branch | A prefix opens its next grid; final key selects immediately. Backspace/breadcrumb returns; search and pointer fallback handle exhausted labels | Defaults center; automatic responsive grid in alphabet order; resize may reflow cells without changing labels | First-letter regions expose full two-letter addresses, then narrow into a leaf grid | Covered in settings preview |
| **Fold** | Stable app spine followed by a child-window sheet; own address vocabulary | Always app + child, even for singleton apps. Both stages can overflow. Global search, full-label pins, reset, Undo and stable sibling churn | Defaults center; spine and sheet placed together | Existing two-letter tab list, with no third hierarchy level | Covered in settings preview and pure allocator checks |
| **Relay** | Current window, previous distinct live window, remaining-window index | Enter returns at the root; direct letters remain stable. Search Enter selects a result. Cancellation, failure, current-window reselection and tab selection leave the return pair unchanged | Defaults middle right; pair and index move together on the chosen display | Existing two-letter tab list; no mixed window/tab return history | Covered in settings preview, including failed-selection simulation |

## Shared functions and where they live

| Function | Settings location / behavior | Applies to |
| --- | --- | --- |
| Display mode | Appearance; saves immediately, cancels pending input, preserves each address vocabulary; blocked during a label draft | All six |
| Activation and input interpretation | General and Advanced selection; same recorder, latch/hold contract, side preference and physical/character interpretation | All six |
| Ordered alphabet and handedness | Selection; one Apply transaction previews every affected map | All six; Fold reuses the alphabet for each stage |
| Stable/mnemonic/pair policy | Selection; affects the shared flat window map | Shore, Beacons, Canopy, Lattice, Relay. Fold uses stable stages and keeps the flat policy for later. Tabs always use pairs |
| Pins and assignment reset | Selection; scoped to the active address set, collision checked, previewed and undoable | Flat windows, Fold composite labels or tabs |
| Minimized/hidden inclusion | General; filters eligibility without freeing addresses | All six; Beacons puts included off-screen targets in its bank |
| Search, cancellation, focus loss and overflow | Shared input router; `/` enters global text search, Escape/Backspace recover, Tab leaves capture | All six |
| Position | Position pane names the current mode; each mode saves a separate display/anchor/inset | All six; Beacons plaque exception is explained inline |
| Theme presets and customization | Appearance; same native/original-green/Sage/Iris choices and per-appearance custom colors | All six, including tab fallbacks |
| Label size and contrast | Appearance; enlargement, strong outlines and OS accessibility accommodations | All six |
| Browser inclusion and setup | Browser Tabs; automatic or selected browsers, range and opening view; Arc and Zen included | All six; no mode owns a separate browser connection |
| Restore defaults and Undo | Shared footer; restore mode, all positions, themes and address sessions; never revoke system permissions | All six |
| Login and access status | General; one app-wide setting and actual native capability state | All six |

No checkbox is added for an invariant such as “keep labels stable,” “show hidden bank,” “require Fold child,” or “only update Relay history on success.” Those behaviors define the modes and remain mandatory.

## Address and state boundaries

The five flat modes share one window map. Changing between them changes presentation only. Fold owns an app map and one child map per app; a full window label concatenates the two prefix-free stages. The UI explains the vocabulary change before selection. Switching away and back preserves both vocabularies. Titles, visibility, themes, mode changes and ordinary window churn never reassign surviving targets.

Fold pins specify the full label while retaining that app’s prefix. Duplicate, invalid, occupied or retired child labels are rejected. A shared alphabet change reassigns app prefixes and child labels transactionally; compatible child reservations survive, incompatible reservations block Apply. Each stage is bounded to four characters, so a complete Fold address can contain up to eight. Address exhaustion uses explicit search/pointer fallback, not a silent grammar extension.

An empty Fold app family keeps its prefix for that running app session. Native confirmed process termination must retire its generation; reopening a process cannot silently inherit its prior children. The browser simulation has synthetic app IDs and no process lifecycle feed. This is a native identity gate, not evidence of persistent app reservations.

A shared alphabet change counts changes across the flat-window, tab and Fold maps. Apply publishes the affected snapshots together; Undo restores them together. Changing only a flat policy leaves Fold and tabs unchanged. A pin/reset affects its own address set. Pending label changes block mode and scope switching until Apply or Discard. Mode switching and scope changes clear partial input. Scope changes during a held preview preserve release-to-cancel behavior.

Relay history is a runtime pair, not a saved preference or score. It follows successful, distinct window selections in any window presentation, allowing Relay to be opened after work in another mode. Closing a referenced target clears that reference. Filtering a previous target makes return unavailable without guessing another destination. Re-inclusion can restore eligibility if the identity remains live. Switching modes, changing settings, selecting a tab, or a simulated failed focus request does not add a history entry. Reload starts without a previous target. Native history must follow confirmed real focus events, including switching outside Tabnax.

## Placement and accessibility

Defaults are Shore/Relay middle right, Beacons bottom center, Canopy top center, Lattice/Fold center; all use active-window display and 24 pt inset. The current mode’s reset leaves the other modes’ placement intact. The preview names the mode being edited. Existing saved placement becomes Shore’s placement when older prototype preferences are loaded.

Native panels must clamp within the usable display frame, freeze their geometry for the active input session, adapt to enlarged text and retain reachable controls. Beacons additionally requires verified window rectangles, collision avoidance, occlusion classification and multi-display behavior; the small settings preview uses three synthetic exposed windows and banks the rest. It is not a placement solver. Native Relay positioning may refine the pair’s proximity to current work, while honoring the explicit saved display/anchor choice.

All renderers consume the same theme tokens and target markup. Labels retain characters and borders independent of color. Full titles remain in accessible names/tooltips even where text truncates. The settings preview uses a small two-column Lattice representation and scrolling at larger collections; final native cell geometry needs desktop-scale evaluation. System accessibility requirements still take priority.

## Scope decisions

- Browser tabs now work in every mode’s settings preview. This intentionally extends the older gallery, which exposed tabs only in Canopy/Lattice. Beacons, Fold and Relay use a declared flat-tab fallback; there is no fictional tab geometry or extra hierarchy.
- The current product scope is open windows plus browser tabs. The gallery’s optional running-app scope remains deferred across all modes. It is not needed for any mode’s window interaction: Fold app branches always lead to windows. If standalone app switching is adopted, it needs its own shared namespace and explicit command in all six modes; the current `1` Windows / `2` Tabs mapping must be migrated visibly. No launcher is implied.
- No native APIs, permission changes, browser installations, commits or gallery rewrites are part of this update. Native focus, browser adapters, process/window identity, full-screen/Spaces and assistive-technology validation remain required before shipping.

## Planned mouse-control option

[The detailed mouse-control plan](./plans/MOUSE-CONTROL-PLAN.md) specifies optional click and wheel navigation for every mode, including branch behavior, Relay’s Enter command, pointer/keyboard interaction and native acceptance. It adds no implemented behavior to this coverage report. The plan also records the current native Windows/Apps versus study Windows/Tabs scope difference.

## Review evidence

[Display-mode interaction checks](./tests/display-modes-checks.js) cover all six modes with direct selection, global search, Arc/Zen pair selection, held scope changes, mode-specific behavior, persistence and placement. [Pure Fold checks](./tests/mode-model-checks.js) cover uniqueness, prefix freedom, singleton/overflow paths, retirement, pin validation and non-mutating drafts. Existing settings/browser/theme regressions remain applicable. Counts and screenshots are recorded in [Verification](./VERIFICATION.md).
