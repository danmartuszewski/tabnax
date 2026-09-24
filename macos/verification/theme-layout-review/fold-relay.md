# Fold and Relay visual and interaction review

Reviewed 19 September 2026 against the current native renderer and selection model. The screenshots in `macos/build/filtering-verification/` were inspected alongside the older settings/native captures. Older captures and `MODE-COVERAGE.md` still describe separate target scopes; the current source combines windows, browser tabs and eligible apps, and is the behavior used for this review.

## Fold

1. **High priority: preserve Fold's implied-family keyboard contract and explain it. Implemented.** The right pane previews a highlighted app before its prefix is entered. `SelectionState` deliberately tries that app's child suffix first, so the suffixes are correct both at the root and after explicit entry. The pane now calls these next letters. Search displays complete stable addresses as identities while ordinary letters enter search text. The stable full identity also remains in accessibility text. An initial review hypothesis that root suffixes were incorrect was rejected after checking the complete key handler; no selection semantics were changed.
2. **Medium priority: distinguish the containing app from keyboard focus. Implemented.** The app spine keeps a soft selection tint when a child owns focus, while the actively navigated app retains the stronger accent ring. This makes the relationship visible without two equally strong focus indicators.
3. **Medium priority: make the two panes understandable before selection. Implemented.** The spine asks the user to choose an app; empty-pane copy includes windows and tabs; the divider is present in empty and populated states. Search includes a result count. App accessibility labels include the number of items instead of promising that every action opens windows.
4. **Follow-up: improve dense family navigation. Deferred.** Independent pane scrolling could help an app with many windows while keeping the app spine in place. It requires input and scroll-region work, so it should not be bundled into surface/theme styling. Existing family-versus-child wheel gesture ownership must remain intact.
5. **Compact enlarged-label repair: implemented after visual QA.** At a 306-point preview width with extra-large labels, the fixed 36% app spine could not fit the enlarged icon, name and key horizontally. Narrow family rows now use an icon/key line above an app-name line, fitting long keys and hiding the decorative icon only when needed. Compact headings use a shorter label and a bounded font/height. The spine boundary used for wheel navigation remains unchanged. A native geometry regression checks one- and four-letter family keys for containment and absence of overlaps.

## Relay

1. **High priority: make the return pair readable in narrow settings previews. Implemented.** Two half-width tiles hide much of the title in compact previews and at large label sizes. The pair now stacks as full-width rows when the available width is less than 520 times the label scale. Current, previous and shelf retain their original navigation order.
2. **Medium priority: make missing return history an explicit state. Implemented.** Missing current/previous cards now retain a framed surface. A missing previous destination has a `Return unavailable` heading and explains that another window must be visited. Search placeholders explicitly say that the card is not in the results. No synthetic history is introduced.
3. **Medium priority: reduce empty shelf chrome and clarify density. Implemented.** The shelf heading includes its item count and disappears when there are no remaining targets. Direct Enter still returns to the observed previous window; search Enter still chooses the highlighted match.
4. **Follow-up: simplify shared shortcut help. Deferred to shared presenter work.** Relay's direct Enter action can differ from the highlighted shelf card. Its existing return caption and accent must survive theme changes; if the previous window is unavailable, shared footer help should avoid suggesting that Enter has a usable destination.

## Glass-theme constraints

- Keep text and key-cap readability deterministic over varying desktop colors. Strong outlines and Increase Contrast must remain effective.
- Use the material for the outer surface and quiet card fills. The selected row and Enter destination need distinguishable accent treatment.
- Preserve the Fold spine boundary and Relay current/previous structure when material translucency increases.
- Theme changes must not change label allocation, target order, selection routing, hover arbitration, mouse-off behavior, or accessible activation.

## Verification

- `swiftc -frontend -parse macos/Tabnax/ModePresenter.swift` passed after the method changes.
- Added native regression coverage in `FilteringLayoutTests` for implied Fold suffix selection before family entry, suffixes after explicit entry, full keys during search, stable accessible identity, narrow Relay containment, and unchanged Enter destinations.
- Updated the existing Fold search-layout caption expectation.
- Integrated build, native test execution and new glass renders are owned by the main task; this review does not claim those results.
