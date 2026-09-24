# Independent interaction critique

The relevant comparison is a remembered window address, not native Cmd-Tab cycling. At eight windows, the existing prototype already needs one activation plus one selection letter. A new concept earns its place by improving recognition, error recovery, or comfort; novelty alone cannot improve that key count.

## Scenarios and costs

| Direction | Best case | Cost and reject condition |
| --- | --- | --- |
| Shore | Unfamiliar or mixed windows; reading similar titles in one predictable column. | Eye travel to an edge. Reject if the compact typography makes the identifying word harder to find than the alternatives. |
| Beacons | A known, visible window whose location the user remembers. | A hidden window causes a second search; focus changes move targets between the desktop and hidden bank. Reject if the user looks at the old location after a focus change. |
| Canopy | Several windows from one app, where the app icon immediately narrows the scan. | Wide scan followed by vertical reading. Reject if grouping adds a decision without reducing title comparisons. |
| Address grid | Repeated use where both a letter and a fixed cell become learned. Covered and minimized windows are equally reachable. | More area and a two-dimensional scan. Keep direct selection for the normal set; mandatory region-then-target selection wastes a key here. A grid in alphabet preference order must not claim to mirror the physical keyboard. |
| App → window drill-in | A large same-app collection or browser tabs, especially when the user knows the app but not the title. | An extra selection key and an intermediate visual state. Single-window auto-commit makes the same app key change meaning when a second window opens. Either use consistent depth or expose that distinction unmistakably. Do not call this the fastest model for eight mixed windows. |
| Relay | Repeated editor–preview, terminal–editor, or reference–writing alternation. | It gives one predicted target disproportionate space; random access can become slower. “Previous” is an explicit changing command. It must never borrow a letter described elsewhere as an immutable target address. Keep every cold window visible and directly addressable. |

## Shared behavior that matters

- Keep addresses independent of display positions, selection recency, query ranking, title changes, and active concepts. If a new hierarchy requires a different namespace, expose and explain it; do not silently reuse global labels with new meanings.
- A spatial grid has a stronger promise than a list: preserve its empty cells when windows close if the concept claims spatial memory. Compaction with stable letters preserves verbal memory only.
- A fixed overflow branch is a reasonable cost of stability, but retirement forever cannot be the final native policy. The demo reaches a creation limit based on all assigned identities rather than currently live windows. Present this as a bounded experiment.
- Similar-title recognition currently benefits from curated short titles. Comparing layouts using those strings is fair, but it does not establish that useful native titles can be derived automatically. Include identification using the distinguishing suffix, not merely the app icon.
- Search is explicit and defensible: slash changes letters from addresses to text, Escape returns to addresses. Search-mode key badges should appear secondary to the selected search result because their normal direct action is suspended.
- Enter in Relay must select the highlighted result during search and return to the previous window only in direct window mode. An Enter action must always be visible before it can change focus.
- A grid prefix must accept the next key immediately, including during any visual narrowing transition. Reduced motion should remove movement without changing selection semantics.

## Concrete original-prototype issues found in source

1. Held Shift changes slash and scope digits into `?`, `!`, `@`, and `#` on a US keyboard. The original handler checks their unshifted `event.key` values, so these commands do not work while peeking. Root notified to normalize those commands during the held surrogate.
2. Changing the scenario count during search can leave the result cursor past the end of the filtered list. Root notified to clamp the cursor after target churn.
3. Simulated window z-indices grow on every focus, while the `.windows` parent originally has no stacking context. Eventually child windows can pass the dimmer and switcher layers. Root notified to isolate that layer and test repeated switching.

## Short user comparison

Keep alphabet and window identities unchanged and rotate concept order. Treat wrong targets, recovery steps, visual searching after repetition, and hand tension as observations. Do not invent speed scores from browser event timestamps.

| Trial | Task | Observe |
| --- | --- | --- |
| Cold recognition | Select Tabnax Layout preview from eight windows without search. | Does the user inspect all targets, a family, or one known place? Which word resolves the duplicate Safari icons? |
| Learned selection | Repeat Terminal → Finder → Layout preview. | Does visual scanning disappear once letters are learned? A new model should not force it back. |
| Alternation | Alternate guide editor ↔ layout preview, then deliberately choose Notes. | Does Relay help the pair without making the unexpected third target hard to find? |
| Occlusion | Select minimized Personal, then return to an obscured work window. | Does each concept keep the hidden target equally legible and accessible? |
| Churn | Learn an address, add a window, close another, return to the learned one. | Are both the letter and any promised spatial location retained? |
| Overflow | Use ten windows; select the reserved-branch target and cancel halfway through. | Are the extra key, pending prefix, and recovery obvious? |
| Tabs | Find window-shortcuts layout preview among 28 tabs; repeat with slash search. | Does progressive narrowing reduce title comparisons enough to justify another state? |
| Ergonomics | Try held and latched activation with the preferred hand preset. | Are a prefix, search, and scope change comfortable without releasing the trigger accidentally? |

Keep multiple modes only if distinct scenarios show repeatable value. A mode that is attractive only on first exposure should remain a design study.
