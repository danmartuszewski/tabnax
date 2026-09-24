# Canopy and Lattice review

Reviewed native `ModePresenter.swift`, the mode and search contracts in `MODE-COVERAGE.md`, and app-owned Canopy/Lattice renders in `verification/icon-alignment/` and `verification/modes/`. Older renders establish visual issues but are not evidence of the new implementation.

## Canopy

| Priority | Finding | Bounded response | Status |
| --- | --- | --- | --- |
| P1 | Browser tabs with similar titles cannot be distinguished by window/workspace context when the subtitle only repeats the browser name. `Target.group` already stores available context. | Use the existing group context in shared row subtitles and accessibility names, without regrouping or changing addresses. | Sent to the shared-renderer owner. |
| P2 | App headings and the first child row have nearly identical visual weight; long columns are hard to scan on a translucent surface. | Add a quiet target count aligned at the right of each app heading and a thin rule beneath the heading. | Implemented in `canopy`. |
| P3 | Repeating the same app icon and name in every child row consumes title space. | Evaluate a Canopy-only compact child style after the existing icon alignment contract can be compared with fresh renders. | Deferred; not needed for this theme pass. |

The implementation retains the full target set when typing an address, dimming unmatched groups in place. Search still uses matching rows in original app order and retains the unfiltered column width. Counts describe displayed children. Headers add no focusable controls or extra keyboard stage.

Acceptance: inspect one-column compact, multi-column desktop, enlarged-label, and search renders. Count labels and app names must remain distinct; full addresses, arrow navigation, mouse hover/click, wheel navigation, and assistive target actions must retain their existing meaning.

## Lattice

| Priority | Finding | Bounded response | Status |
| --- | --- | --- | --- |
| P1 | Branch height assumes one line per title even though branch detail wraps; long titles and enlarged labels can clip the complete address inventory. | Measure the displayed detail using its actual font and constrained width, then give the row enough height. | Implemented in `branchTileHeight` and `lattice`. |
| P2 | A branch resembles a target tile although opening it has a different result. | Begin branch detail with “Open group”, retain the complete inventory, and provide Return/Backspace accessibility help. | Implemented in `lattice`. |
| P2 | An opaque grid of cards can hide most of a glass panel's material and make it feel disconnected from macOS. | Keep neutral tile fills translucent under glass themes and preserve a clear selected outline and keycaps. | Sent to the shared surface owner. |
| P3 | Held slots need to remain visibly different from groups without relying only on color. | Retain the explicit “Held slot” and “Unassigned” text and disabled interaction state. | Existing behavior preserved. |

The implementation retains alphabet order, held cells, branch addresses, leaf addresses, navigation actions, and whole-cell target hit areas. Search still lays out leaf results and does not become a list. Branch detail measurement is independent of highlight, so moving the selection does not change tile height.

Acceptance: inspect overflow branches with long titles at compact width and enlarged scale, plus search and held slots. Every descendant address must be visible. Return/click must open a branch; wheel must highlight actionable visible cells; disabled held cells must not select. Check opaque/reduced-transparency fallback alongside glass.

## Verification

`xcrun swiftc -frontend -parse macos/Tabnax/ModePresenter.swift` passed after the mode changes. Integrated compilation and fresh render results belong to the main theme work; this document does not claim they have passed.
