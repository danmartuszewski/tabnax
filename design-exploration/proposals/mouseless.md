# Lattice — addresses become places

## Recommendation

Add a screen-wide, progressively narrowed address grid. This is the clearest additional Mouseless-inspired proposition because it borrows the relationship between a visible region and a key, while adapting it to a finite set of windows. It does not trace the windows' physical geometry. Every window gets an equal, non-overlapping place in the overlay, including covered and minimized windows.

This is worth prototyping alongside the original concepts. It is not evidence of faster switching. A wide grid can demand more eye movement than Shore, especially before addresses are learned.

## Proposed interaction

- **Normal 6–10-window case:** the desktop is covered by a light, screen-wide mesh of cells. A cell contains one large app icon, a complete distinguishing title, muted context, and a large address. Single-letter windows select immediately. Do not introduce a mandatory two-key hierarchy for an eight-window set.
- **Stable places:** derive the cell from the stable address, never MRU, app sorting, screen position, or filtered rank. Closed targets leave a quiet empty place until Reset. A new window uses its newly allocated address. This is a useful contrast with the original concepts, whose addresses stay stable but whose visual positions can move.
- **Overflow:** the allocator's reserved final letter is a visible continuation cell. The normal windows retain their addresses. Pressing `P` reveals `PJ`, `PK`, and subsequent targets; the prefix stays visible in a breadcrumb. Keyboard input is immediately active in the revealed grid. If the user already knows `PJ`, pressing the keys quickly must work without waiting for an animation.
- **Optional tabs:** use the existing two-letter tab addresses. Initial cells correspond to occupied prefixes (`J`, `K`, `L` for the default 28 tabs). They expose small inventories of titles, with complete two-letter labels. The first letter expands one prefix into the same address grid; the second letter focuses its tab and its parent window. A known two-letter address bypasses the visual selection step.
- **Explicit search:** `/` enters the existing text field. Search results become a readable result list within the Lattice surface; retained direct labels are informational. Letters type text, arrows choose, Enter selects. Escape returns to the grid. Searching must not squeeze or renumber address cells.
- **Back:** Backspace removes a prefix. Escape/Space follow the shared return/cancel behavior. Clicking a prefix tile is the pointer equivalent of typing its key; clicking a target selects it.
- **Scopes:** keep `1` windows, `2` apps, `3` tabs. Window, app, and tab namespaces stay separate. The surface explicitly names its scope.

## Visual specification

The surface occupies the whole simulated desktop below the menu bar, inset enough to retain a hint of wallpaper at its edges. Use a translucent charcoal scrim, faint continuous grid lines, and restrained green key marks. Cells are drawn as areas in one field rather than independent rounded cards. The field should feel like a spatial keyboard laid over the desktop, not Mission Control thumbnails.

For the default alphabet, a practical first prototype is a fixed 5-column × 2-row grid of ten address positions. The order follows the configurable alphabet (`J K L U I / O N M H P`). This is a symbolic address grid; do not falsely imply the rectangle is a literal physical keyboard map. A 3-column layout on narrower screens is only an inspection fallback. The window branch cell occupies the final slot from the start, even before overflow exists. Unused slots are visibly empty, not collapsed. On a drilled-in window level, the same grid repeats, with the final slot again reserved for deeper overflow. For tabs, every suffix is a leaf, so the final slot may contain a target.

Root tab groups need their constituent titles exposed. Three identical Safari icons with counts alone would force a blind first key. Render each occupied root prefix as a generous column in the same field with a small title inventory: the additional reading surface is intentional, and must be judged against Canopy's browser-window grouping. The leaf grid removes unrelated titles after the prefix is typed.

The large key sits in one repeated corner. App icon and title sit together. Keep the full title available via tooltip and accessible name, but give the distinguishing title enough room to avoid truncating “lesson editor” versus “learner preview.” Show `Minimized` or `Covered` only when it materially explains why the window was not visible before activation. These statuses must not alter a cell's position.

Do not animate tiles flying from real window positions. That would imply geometry is the organizing principle and delay legibility. A short opacity transition is sufficient; reduced motion removes it. Events select synchronously regardless of visual state.

## Where it helps

- A user already comfortable with Mouseless-style visible regions and successive key narrowing.
- Covered windows that would be awkward to label in Beacons: all targets occupy the same readable plane.
- Repeated switching after positions and labels become familiar; both spatial and key memory can develop.
- A large collection whose user can remember a two-key address. Prefix drill-in gives the user a manageable next choice without relabeling the collection.
- Longer titles that need more horizontal room than Canopy's app columns.

## Costs and grounds for rejection

- A full-screen scan can be slower than Shore's short vertical list. A larger surface is not automatically easier to read.
- The grid order is arbitrary, and the initial row/column location is an extra fact to learn. The keyboard label remains the meaningful address.
- The `P` overflow case adds a visual decision for a new target. It is justified only by preserving the other nine addresses.
- Retired-address holes preserve memory but waste space. The lab should make this visible rather than hiding it. Native retention policy remains undecided.
- Prefix groups are based on allocation, not semantic tab topics. This preserves addresses but makes a first-time tab search less intuitive. `/` may win decisively for the 28-tab case.
- The overlay deliberately covers more of the desktop than Shore or Beacons. It suits an explicit switching moment rather than an unobtrusive peek.

## Comparison and acceptance checks

Keep alphabet and targets fixed. Compare selecting Learner preview, Terminal, and the minimized personal window across Lattice and Shore. Observe whether the extra surface causes hesitation before assuming the spatial model helps.

Verify: existing windows select in one key; opening/closing never moves another target's cell; a `PJ` selection works with consecutive keydowns; 28-tab `JJ` and `L…` paths work; Backspace and Escape restore the parent; search letters cannot select; a left-hand/custom alphabet changes both labels and deterministic cells; the held trigger can be released without committing; reduced motion does not change input behavior. Do not infer native latency or tab API support from these checks.

## Integration

Add `lattice` to the concept registry and gallery navigation; retain Shore, Beacons, and Canopy without modifying their visual models. The shared stable allocator, target data, direct-key handler, search logic, and focus operation can stay intact. Lattice needs only its own layout renderer, styling, and a branch-tile click action that feeds a prefix through the shared direct-key path. Add `lattice` to the optional-tabs capability check. No new product configuration controls are needed.
