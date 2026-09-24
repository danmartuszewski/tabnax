# Native display-mode coverage

Design references (some predate the shared target view): [settings specification](../settings-exploration/SPECIFICATION.md), [six-mode settings coverage](../settings-exploration/SIX-MODE-COVERAGE.md), and the [current application architecture](../docs/ARCHITECTURE.md). Select a mode in Settings → Position or Appearance. Mode changes preserve the shared label session.

## Shared behavior

| Requirement | Implementation and evidence |
| --- | --- |
| Immediate final-key selection | Pure `SelectionState` plus dedicated `InputRouter`; native replay resolves full sequences without waiting for drawing |
| Windows, browser tabs and apps | One shared target view. Flat modes include running app rows; Fold/Canopy group windows and tabs by owning app. Closed assigned apps are launchable in every mode. App activation does not promise a particular window |
| Explicit global search | `/` or an independent opt-in search shortcut; search invocation always latches, repeats preserve query/selection, and modifier release never commits. Native AppKit field editor, all-term app/title/context fuzzy matching and ranking, ordinary text/IME input; search never treats letters as direct commands |
| Stable filtered identities | `LabelSession` allocates before eligibility filters, retains held addresses and rejects conflicting pins; active snapshots freeze label meanings |
| Assignment edits and recovery | 6–26 letters, four hand presets, custom order, scoped restore, stable/initials/pair policy, pins, reset, Apply/Discard and Undo |
| Keyboard and pointer | Native buttons, first-click handling, captured press identity, session checks; mouse Off preserves assistive actions; wheel changes highlight only |
| Minimized windows | Option restores an exact minimized window and never minimizes a visible window. App rows and Fold families choose a minimized child by observed recency, then catalogue order. A monochrome minus badge appears on window icons in all six modes, flat app entries and Fold families; state updates remove it after restoration. Compact tiles retain the marker when a long address hides the icon. Search, tooltips and accessibility labels retain the state |
| Placement | Shared display choice, opt-in simultaneous copies, per-mode nine anchors and inset; frozen on opening, each panel clamped to its own usable bounds |
| Appearance | Graphite/Tabnax/Sage/Iris/Frosted Glass/macOS Glass, System/Light/Dark, per-tone customization, resets, contrast-derived text, label scaling and stronger outlines |
| Missing or exhausted targets | Unavailable targets cannot select; short-label exhaustion retains search/click/navigation access; exact closures retire identities |
| Cancel and hierarchy | Escape backs out of search/prefix then closes; Backspace removes a letter. Hold is owned by the modifiers, not the trigger key: releasing them commits the previous window or a highlight reached through keyboard cycling; typing and quitting disarm release selection; Option restores a minimized window and preserves selection on modifier release. Unknown keys are swallowed rather than closing the switcher or leaking to the app underneath; function keys pass through |
| Recency and cycling | `FocusHistory` is a bounded most-recently-used stack. A session opens with the highlight on the most recent available window other than the current one, using the chosen frozen traversal order; a quick hold-tap therefore returns to the previous window. Stable ordering remains the default. Re-pressing the trigger while the modifiers stay down advances the highlight; in latch mode a fresh chord press toggles closed. Left/Right move between Canopy columns, enter/leave a Fold family, and step linearly elsewhere; Shore ignores them |
| Windows on other Spaces | A known window that macOS stops listing but whose handle still answers stays selectable and is labelled "Elsewhere" (other Space or full screen). A timed-out app keeps its last known windows instead of losing them. Windows on a Space never visited since launch are reachable only through their app row |
| Capture recovery | A disabled event tap is re-armed in place; only three losses within ten seconds stop capture and raise the health message. A public Carbon hot key mirrors eligible chords (either-side modifiers, not ⌘Tab) so the switcher still opens under Secure Input or a lost tap |

## Mode-specific behavior

| Mode | Windows | Tabs and mouse behavior |
| --- | --- | --- |
| **Shore** | Narrow index; aligned direct codes | Shared flat addresses. Wheel follows list order without wrapping |
| **Beacons** | Public AX bounds with conservative visibility correlation; collision-safe plaques; ambiguous, covered, minimized and off-display targets stay in the bank | Tabs and launch targets use the bank. Wheel navigation is bank-only; hovering never changes a plaque target |
| **Canopy** | Visual app columns; complete app-prefix/child addresses | Tabs join their owning app columns; navigation follows the displayed group order |
| **Lattice** | App-grouped tiles, trailing held slots, visible branches and full-address inventories | Shared-address cells; closed assigned apps retain direct launch letters without invisible traversal stops; single-app branches stay with their app, shared branches follow app groups. Enter/click opens a branch, then selects a leaf. Wheel traverses actionable visible cells, not hidden descendants |
| **Fold** | Stable app spine → stable child labels; typing an app's head letter selects directly when it owns exactly one window, otherwise both stages are still required; search remains global | Tabs join their owning app’s family; closed assigned apps remain launchable. Window wheel gestures stay in the app or child region where they began |
| **Relay** | Current and previous distinct observed windows plus direct shelf; Enter returns only to an available previous window | Tabs share the shelf; search uses normal Enter selection. Wheel only highlights; direct Windows Enter retains its Return meaning, while click selects the chosen target |

Keyboard, click and wheel use the same semantic target/branch actions. All six Windows/Tabs previews are exercised through native UI tests, including Lattice branches and Fold’s family stage. Physical mouse-off/accessibility behavior is also checked at the native control layer. Current theme renders are in verification/settings/ (`verification/settings/`; local artifact, not published); exact test results and gates are in [VERIFICATION.md](VERIFICATION.md).

### Filtering within each layout

Opening `/` search or the opt-in search shortcut keeps the selected mode and its panel width. Typing filters app names, titles and context without changing any target's address. Clearing the query restores the full layout; Escape leaves search. Arrow Up/Down and Tab walk the filtered results, and Enter selects the highlight in every mode.

| Mode | Filtered presentation |
| --- | --- |
| Shore | Results stay in the narrow index. |
| Beacons | Matching windows retain plaques where possible; remaining results use the grouped bank. |
| Canopy | Matching windows and tabs stay in app columns, ranking groups by their strongest match and preserving column width. |
| Lattice | Results use app-grouped address tiles in the grid, including matches inside overflow branches. |
| Fold | The app spine narrows to matching apps; the child pane follows the highlighted result. App buttons and wheel navigation stay within search. Apps with no available matching result are disabled. |
| Relay | A ranked result grid replaces the direct current/previous view. Enter selects the highlighted result; focus history cannot reorder search navigation. |

`FilteringLayoutTests` checks the native renderer through empty search, a query, no results, clearing and Escape in all six modes. Core tests cover ranked Canopy ordering (including browser-owned tabs), Fold navigation, normalized abbreviations/subsequences, symbol and field boundaries, churn, opt-in memory and empty-result selection. Native tests compare rendered order, pointer presses and Enter against navigation in all six modes. UI automation enters a query and presses Return in every mode, including a fixture with an invisible closed app. Closed apps cannot be selected by search; their direct addresses still launch them. General → Search exposes the default-off memory setting and Clear control; persistence tests cover migration, bounded digests, clear/off/reset and delayed callbacks.

## Boundaries

Beacons uses conservative public metadata correlation, not complete occlusion or an all-Spaces guarantee. AX handles remain the focus identity; geometric matches never choose a window. Browser tabs have no reliable desktop-window geometry, so they use each mode’s defined list/grid fallback. Arc/Zen workspaces or split views are not inferred from titles or URLs.

Browser code and companion protocol tests do not establish live browser approvals, third-party focus behavior or signed extension distribution. Likewise, fixtures do not establish hardware trackpad behavior, mixed-display arrangements, IME/VoiceOver/Mouseless coexistence or measured latency/resource targets. These remain explicitly separated in the verification record.

## Highlighted target actions

All six modes expose the same native actions menu through the footer ellipsis and Command–Period, including explicit search. Close, minimize, zoom and fullscreen only use exact catalogue windows. App rows and Fold family branches offer app actions; browser tabs offer app actions only when their real owner is resolved. Neither kind redirects window actions to an arbitrary child. Restore retains its existing minimized-child rule.

Menu tracking freezes the action IDs and disarms the opening modifier release. Native menu keys never become direct addresses or search edits. The switcher stays latched after the menu closes, and search retains its text selection. Window close dismisses the switcher to expose normal document confirmation. Other actions suspend desktop-window preview until the user navigates again. Both the pointer and keyboard paths share these rules; Mouse Off still permits the footer controls and assistive access.

## Optional traversal ordering

General → Windows offers Stable, Most recently used, Alphabetical and Window state. The setting survives relaunch and Undo; absent, unknown or malformed values decode as Stable. Address allocation precedes ordering. Runtime recency is bounded to the current window plus 32 previous windows and is not persisted.

| Layout | Ordering contract |
| --- | --- |
| Shore / Canopy | App groups follow the first ordered child; children follow the selected order. Canopy lateral navigation uses the same visible column sizes. |
| Fold | App spine follows the first ordered child; Stable keeps its original app spine. Children follow the selected order. Hold-release on a family still chooses its most recent available child. |
| Lattice | App-owned address cells follow group/child order. Shared overflow and held/empty cells follow in alphabet order; unaddressed rows follow the grid. Branch positions are captured even if a child is later excluded. |
| Beacons | Spatial plaques keep their geometry. With optional ordering, the bank is the traversal sequence with plaque targets omitted, mixing windows/tabs/apps as needed. Strong-match search uses the same ordered bank. |
| Relay | Stable preserves current/previous cards. Optional ordering fills the pair and remaining grid in chosen order. Enter still returns to the opening session's previous window; pointer, direct letters and hold-release choose their exact target. |

Search keeps stronger-match ranking, using frozen order for equal scores and strongest children for group ranking. Metadata may change search membership/strength but never its ordering tie-breaker. Closing a target disables its row; exclusions remove it; neither reorders survivors. Invisible closed app launchers remain direct-address-only.

`OrderingTests`, native renderer/Command–Tab tests and isolated settings/search UI tests cover all four choices and six layouts, unknown history, closed/hidden/minimized/elsewhere targets, owned tabs, overflow, migration/persistence, preview updates and live reconciliation. Focus discovery captures a generation token and checks it again on completion, rejecting reads crossing a preview or selection transition.

## Simultaneous displays

One `SwitcherPresenter` coordinates non-recursive `SwitcherSurfacePresenter` renderers. The default still opens one panel. All six layouts can show one panel per connected display with one selection/search session, a single native editor owner and shared menu tracking. Search activation, fuzzy ranking, exclusions, traversal ordering, exact actions and direct addresses use the same upstream model for every copy. Beacons has identical complete banks plus unique spatial plaques; one spotlight controller dims the desktop. Every bank and plaque is included in pointer regions. Display changes and wake dismiss the session, including menus and editors. Synthetic display arrangements and actual connected-display/UI evidence are recorded in `verification/competitive-gaps-2026-09-22/simultaneous-displays.md`; physical Spaces transitions and live IME candidate/VoiceOver integration remain separate checks.
