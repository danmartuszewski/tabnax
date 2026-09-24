# Settings review — 20 September 2026

Three agents reviewed and improved General/Browser tabs, Letters/Apps, and Position/Appearance. The primary agent integrated the shared layout, reviewed all six tabs, and verified behavior against the current native renderer. Work from the separate UI-cleanup task was preserved. No commits were made.

## Changes by tab

| Tab | Improvements |
| --- | --- |
| General | Readable shortcut keycap and recording state; accurate press/hold, quiet return, Relay Enter, and modifier-side guidance; actionable Accessibility state; observed login status. |
| Letters | Clearer preset picker and ordering controls; useful alphabet-validation messages; prevention of removing too many letters; explanations for physical keys, assignment policies, and reserved app letters. |
| Apps | Picker errors no longer block valid letter drafts; unavailable key choices explain their conflicts; exhausted two-letter alphabets give a recovery path; clearer enabled/disabled/launching states; cached app availability refreshes. |
| Position | Clear distinction between the active layout, shared display choice, and each layout’s position; more legible anchor selection; illustrative display roles; position reset preserves legacy display choices. |
| Appearance | Consistent three-column theme cards with readable names; visible glass compatibility information; explicit preview/edit color tone; clear scope for resetting light and dark colors; improved contrast and accessibility labels. |
| Browser tabs | Inclusion is distinguished from connection permission; active-browser range and empty selections are explained; each connection identifies Automation or Extension; setup requirements are visible; connection setup remains available independently of tab inclusion. |

Shared improvements include section cards, pane descriptions, explicit save semantics, a read-only banner, a narrower preview column in compact windows, and clearer Apply/Discard/Undo/reset behavior.

## Behavior corrected

- Staged letters now follow windows opening and closing while the draft stays unapplied.
- Clean drafts follow selection changes received from outside the settings editor.
- The changed-letter count uses the active layout’s namespace and counts each target once.
- Invalid edits preserve the last valid preview configuration and show a useful A–Z/length/duplicate error.
- Application-selection failures are separate from letter-validation failures.
- Resetting a legacy position preserves the display choice stored with that position.

## Verification

Verification uses a separate build identity, `pl.tabnax.Tabnax.SettingsReview`, and isolated preference domains. User preferences, login registration, and permission grants are not changed by these checks.

- Core suite: 78 tests passed.
- Native settings suite: 21 tests passed, including five new regressions for the draft and preview corrections above.
- Settings UI suite: all 11 flows passed across the initial full run and corrected rerun. The final rerun passed all five affected flows plus all 21 native settings tests. Results are recorded in `final-tests.log`; the initial complete run is retained in `initial-ui-tests.log`.
- Debug build and strict deep code-signature verification passed on macOS 26.6.2.
- All six tabs were visually reviewed at the default size in light appearance and at compact size in dark appearance.
- Individual browser selection and dark appearance were also verified directly through the native accessibility interface.

The initial UI run exposed assertions that still used the old restore-button title, expected closed launch targets to be drawn, and treated the native appearance radio buttons as a segmented-control element. These were updated to match the actual controls and the concurrent renderer cleanup. Browser selection verification now waits for the updated enabled state and targets the visible menu item.

Final result bundle: `macos/build/SettingsReviewDerivedData/Logs/Test/Test-Tabnax-2026.09.20_06-39-31-+0200.xcresult`.

## Screenshots

| Tab | Light | Compact dark |
| --- | --- | --- |
| General | Light (`renders/general-light.png`; local artifact, not published) | Dark (`renders/general-dark.png`; local artifact, not published) |
| Letters | Light (`renders/letters-light.png`; local artifact, not published) | Dark (`renders/letters-dark.png`; local artifact, not published) |
| Apps | Light (`renders/apps-light.png`; local artifact, not published) | Dark (`renders/apps-dark.png`; local artifact, not published) |
| Position | Light (`renders/position-light.png`; local artifact, not published) | Dark (`renders/position-dark.png`; local artifact, not published) |
| Appearance | Light (`renders/appearance-light.png`; local artifact, not published) | Dark (`renders/appearance-dark.png`; local artifact, not published) |
| Browser tabs | Light (`renders/browsers-light.png`; local artifact, not published) | Dark (`renders/browsers-dark.png`; local artifact, not published) |

These are app-owned view renders using sample data. Scrollable content below the viewport is exercised by UI tests rather than being compressed into the screenshots.

## Scope and remaining limits

The review covers the six shipping native settings tabs and their shared preview/draft behavior. Historical HTML design prototypes were not changed. Live browser consent flows, signed extension distribution, physical modifier-side behavior on different keyboards, and execution on macOS 15 require their respective external environments. Position diagrams remain illustrative; they are not captures of the user’s displays. Existing unrelated compiler warnings are unchanged.
