# Scoped restore controls — UX review and implementation

Update: 17 September 2026. Implemented in the settings study after the request for a default-order action beside “Letters, in comfort order.” This is a heuristic review of the existing controls plus interaction/layout verification, not a claim of a separate human usability study. Native app code is unchanged.

## Review decisions

| Setting | Recovery need | Decision |
| --- | --- | --- |
| Ordered letters | Reordering, text editing and removing I/O can lose the recognizable preset. Choosing Custom also hides which hand the order came from | **Add Restore default order beside the field.** Retain the originating Right/Left/Both preset and name it in the help text |
| Recorded shortcut | The suggested chord is not an option in the recorder after replacement; whole-app reset would undo unrelated work | **Add Use suggested shortcut.** Restore only the chord; keep activation behavior and modifier-side choice |
| Individual theme colors | Reset this theme clears both colors in both appearances, which is too broad when only one experiment went wrong | **Add Reset beside each color.** Restore only that token in the current preset and Light/Dark appearance |
| Position | The existing Use default position already restores one mode’s display, anchor and inset | Keep existing scoped reset |
| Whole preset | Reset this theme intentionally clears both appearances of one preset, with Undo | Keep alongside the smaller color resets |
| Assignment session / pins | Reclaiming held addresses and clearing pins is a distinct operation from restoring the alphabet | Keep Reset label assignments in Advanced, with its existing confirmation and Apply step |
| Appearance source, theme choice, label size, assignment policy | System, the presets, Standard and Stable are already visible choices | Do not add duplicate reset buttons |
| Inclusion toggles and browser filters | Each value is directly reversible; automatically enabling browsers or changing scope during a broad reset could surprise | Keep explicit controls and Undo; no additional bulk browser reset |
| All preferences | Broad recovery remains useful when deliberately requested | Keep Restore defaults with its existing scope explanation and confirmation |

Controls remain visible but disabled when the corresponding value is already default. They use named buttons, not unlabeled icons. Field-level color resets expose their color and appearance in the accessible name. Reset actions do not create a confirmation dialog when preview/discard or immediate Undo already provides recovery.

## Letter-order behavior

- A named hand preset becomes the reference preset. Custom typing, reordering and Remove I/O retain that reference, including after Apply and reload.
- Restore default order reinstates the complete reference alphabet, including removed I/O. It does not force a left-handed user back to Right hand.
- The action previews through the existing label transaction. Saved preferences and addresses remain intact until Apply labels. Discard keeps the saved custom order; Undo after Apply restores the preceding preference/address snapshots.
- The assignment policy, theme, all mode positions, browser choices, activation and key interpretation remain unchanged. Flat windows, tabs and Fold use the shared alphabet transaction across affected maps.
- Compatible session pins survive. Incompatible pins block Apply with an explanation; restoration never silently deletes them. Explicit Reset label assignments remains the way to clear pins.
- Applying an order change starts a new address generation, as any alphabet change does. Retired addresses can become available in that new generation; it is not a promise to preserve tombstones through deliberate reassignment.
- Invalid custom text can be recovered with the same button. A conflict caused by a different setting, such as an incompatible pinned assignment, still requires resolution.
- The button is disabled when the displayed normalized letters already equal the reference order. This avoids a redundant transaction even if the selector still says Custom order.

The browser stores `selection.baseHand` as `right`, `left` or `both`. This is recovery metadata; it never controls an allocator’s grammar or the activation modifier. Old preferences migrate from a named hand, then an exact alphabet/preset match; a custom alphabet with no recoverable origin falls back to Right hand, named visibly beside the control. Migration adds metadata without changing the saved alphabet. The proposed native equivalent is `selection.baseHandPreset`; it remains a schema/design contract until implemented natively.

## Shortcut and color behavior

Use suggested shortcut restores the study’s Control-Option-Space suggestion. It ends an active recorder and clears its validation message. It preserves the chosen latch/hold behavior, modifier side, alphabet and all target addresses. A changed chord creates an Undo checkpoint. Native implementation must validate/register a suggested chord before replacing a working shortcut; this study records no global shortcut.

A color Reset removes only the current preset/current appearance override for key background or selection accent. Rendering falls back to the curated token and recalculates readable text/contrast. The other color, other appearance, other presets, label size and display mode remain unchanged. Empty override objects are pruned. Reset this theme remains available when another appearance still contains customization. Both token-level and whole-preset resets retain Undo and persistence.

## Verification

[Reset interaction checks](./tests/reset-checks.js) cover all three reference presets, invalid text, removed I/O, Apply/Discard/Undo, reload and older preferences, compatible/incompatible pins, all six modes, shortcut recovery, independent color restoration and narrow layouts. The relevant existing selection, theme and mode suites are also rerun. Results are recorded in [Verification](./VERIFICATION.md).

- Default-order action beside its field (`./output/playwright/resets-selection.png`; local artifact, not published)
- Individual color resets at compact width (`./output/playwright/resets-colors-compact.png`; local artifact, not published)
