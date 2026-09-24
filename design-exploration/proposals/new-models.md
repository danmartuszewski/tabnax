# Two additional interaction models

Independent design proposal. These models supplement Shore, Beacons, and Canopy. They do not establish native scope or measured performance.

## Fold: choose a family, then its exact window

**Question:** Can reducing the number of titles visible at once repay one extra selection key?

### Visual composition

A compact vertical application spine sits left of the desktop center. It contains six large app icons, app names, counts, and stable first-letter badges. There are no window titles at the first level. Selecting an app keeps the spine in place and unfolds a wide sheet to its right containing only that app's windows. The selected app row remains lit; the other rows become quiet. A tiny breadcrumb shows `Safari K / choose window`.

This is not a side-by-side display of every app family. It exposes one family at a time, so each window title can have considerably more horizontal room than in Canopy. Use a visually solid sheet, subtle dividing lines, and restrained rounded corners. Avoid a fanned stack of overlapping cards: that would recreate the occlusion problem.

### Input model

- Opening the switcher shows application choices. `K` opens Safari's sheet; `K J` selects its first window, `K K` its second, and `K L` its third.
- Every window uses an app key plus a local window key, including apps with one window. Never auto-select a singleton: when a second window opens, that would silently turn a previously complete key into an incomplete prefix.
- Both keydowns may arrive immediately. Updating the branch is synchronous. Expansion animation is decorative and never blocks the second key.
- `Backspace` or `Escape` clears the app prefix; another `Escape` dismisses. `Space` follows the established back/cancel behavior.
- `1` selects windows, `2` apps. Apps scope intentionally uses one app key to focus that app's most recent window. Scope is named prominently.
- `/` enters explicit text mode. At the root it searches all windows; inside a family it searches only that family, with the family stated in the field label. Search result labels remain stable but are inactive while typing. Escape restores the exact branch.
- Optional tabs should be deferred in this concept's first prototype. App→window→tab adds a third decision and is not justified merely because a tree exists.

### Address policy

Keep app allocations stable within this concept, including gaps left by closed app families. Each family owns a separate stable window allocator. A new Safari window receives the next unused local key without changing existing Safari keys or any other app's keys. Closed addresses retire for the session. App keys must use the same reserved-overflow rule as other namespaces.

These are intentionally a separate address vocabulary from Shore's flat window keys. Reusing the same window labels while adding a prefix would make the labels look universal when they are not. State the difference in the gallery and test one concept in a block rather than rapidly switching concepts while memorizing labels.

### Scan, ergonomics, and edge cases

The initial scan asks only “which application?” The second asks “which window?” That matches people who recall an app before they recall a document title. Icons help the first task, while longer titles and context help the second. A right-hand alphabet keeps both strokes on the selection hand; selecting a singleton often repeats the easiest home-row key.

Occluded and minimized windows appear normally in their app's sheet, with a quiet status annotation. The model depends on window identity, not on current desktop position or visibility. Similar titles should front-load the differing part (`Lesson editor` / `Learner preview`) without inventing automatic title intelligence.

At 6–10 windows, Fold has an unavoidable one-key cost over flat direct addressing. Its strongest scenario is many windows concentrated in a few applications. Its weakness is many singleton apps. Users may also forget the first prefix during an interruption; the breadcrumb and highlighted family must make recovery explicit.

### Specific acceptance observations

- Typing `K K` quickly must select the second Safari window without waiting for the sheet to finish opening.
- Opening another Safari window must preserve both existing full addresses.
- Switching from a hidden Safari preview to a visible Safari editor should require exactly two letters after activation in both directions.
- Search inside Safari must never select a non-Safari result silently.
- Compare same-app error rates with Canopy, and compare total hesitation with Shore. Retain Fold only if reduced visual competition matters more than its extra key.

## Relay: make the previous window an explicit handoff

**Question:** Can a dedicated return action reduce repeated scan effort during a two-window loop?

### Visual composition

Use a low horizontal surface above the dock. Its left section is a single confident handoff: a large icon, the previous window's distinguishing title, context, and an `Enter` badge under the phrase `Return to`. Its right section is a compact two-column index of all windows with their unchanged direct addresses. The current target has a quiet marker and is never mistaken for the previous target.

The contrast between one prominent expected destination and a subdued stable index is the concept. Do not put five recent cards beside it; that becomes an MRU thumbnail switcher. No thumbnails, task groups, saved pairs, or inferred workspaces are needed.

The primary card may contain a simple connecting line from the current app's small icon to the previous app's larger icon. Treat the line as an explanation of the handoff, not as decoration that must animate before input. This composition occupies the lower desktop rather than relocating Shore to the center.

### Input model

- `Enter` selects the previous distinct live window. Opening and cancelling the overlay never changes the previous target.
- All existing direct letters continue to select their window instantly. There is no second key just to reach the full index.
- Selecting another window updates history only after the selection commits. A→B→Enter→Enter alternates B→A→B.
- Selecting the already focused window is a no-op for history. It must not destroy the previous destination.
- If the previous window closes, the primary card falls back to the most recently focused surviving distinct window. If none exists, show a neutral `Choose a window` state and make Enter a no-op.
- Keep `1` windows and `2` apps only if Enter's meaning remains explicitly window-based. Simpler for the prototype: enable the handoff only in windows scope; app scope uses the ordinary direct index.
- `/` enters explicit search. In search, Enter chooses the highlighted search result; it does not execute the handoff. The prominent card should disappear or become inert while searching.
- Optional tabs are a poor default here. Decide whether “previous” means a window or a tab before offering a tab version; do not mix their histories.

### Address policy

Use exactly the original flat window addresses. Recency changes the single handoff card, never the index order or a direct label. The handoff action is a verb (`Return`), not a permanently assigned destination. That distinction permits a useful dynamic destination without undermining learned direct keys.

### Scan, ergonomics, and edge cases

For an editor/preview or editor/terminal loop, no index scan is necessary once the previous window is understood. Enter is farther from the home row than J/K but is comfortable for a right-hand selection after left-hand activation. A future native trigger could provide a dedicated previous-window action, but the prototype should not invent a new global shortcut to make the evidence look better.

Hidden or minimized previous windows still appear in the handoff card and restore on commit, just like any direct selection. Three-window loops are less favorable: the primary card changes each time, and the user may anticipate the wrong destination. The entire index must remain visually secondary but legible enough to correct that expectation.

At 6–10 windows, Relay targets a repeated workflow rather than universal random access. Beyond that set, it still helps the two-window loop, but its fallback index scales no better than a list. It is not a substitute for Fold or a large-collection grid.

### Specific acceptance observations

- Initial state clearly indicates whether a previous target exists; do not seed fictional focus history just to make the card attractive.
- Select Terminal, return to Code, return to Terminal, then jump to Safari. The next handoff must be Terminal, not the first app in the index.
- Cancel and reopen without changing the handoff.
- Close the prior target and verify that Enter cannot address a dead window.
- Enter during `/` search must select the result, never the return card.
- Compare repeated pairs against direct learned letters. Relay earns its place only if the predictable return action saves mental effort; it does not necessarily save a keystroke.

## Novelty filter

Both are deliberate deviations from the flat one-letter model and need a narrow reason to exist. Fold adds a key to reduce title competition. Relay uses one dynamic action to make repetitive work easier. Neither is automatically faster than Shore.

I would prototype both only because they test different questions from the existing three and the Mouseless grid: semantic hierarchy and focus history. Do not add a radial ring merely to reach a concept count: arbitrary angles add eye travel without reducing keystrokes. Do not add a chronological carousel: stepping through history would recreate the cycling complaint.

If only one of these deserves the next prototype slot, choose **Fold** for a substantial new interaction model and keep **Relay** as the useful counterexample: a small return affordance may help more than a visually ambitious replacement.
