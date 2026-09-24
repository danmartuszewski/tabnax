# Tabnax: three additional directions

The original **Shore**, **Beacons**, and **Canopy** remain available and keep their visual models. The expanded [gallery](./index.html) adds **Lattice**, **Fold**, and **Relay** as separate alternatives. There is no combined “everything” mode and no native feature commitment.

Three independent agents contributed: one explored the Mouseless-inspired grid, one developed semantic hierarchy and return-history models, and one challenged their switching costs and audited the shared interaction. Their proposals are linked below. The final implementation and browser checks are integrated by the lead agent.

## Lattice: addresses become places

**Try:** select Lattice, then `L` for Learner preview. Open the lab and close a window: its cell stays empty. Use ten windows and type `P J`. Press `3` for 28 tabs, then `J` to narrow and `K` to select.

Lattice places every window on one readable plane, including occluded and minimized windows. The default alphabet occupies a fixed five-by-two field. This is an address grid in comfort order, **not a literal map of physical keyboard rows**. Existing windows require one letter; the reserved `P` cell leads to overflow without changing other labels.

Closed identities leave held cells. That gives Lattice a stronger spatial-memory promise than the original index layouts: both the address and its place remain available to learn. The grid reorganizes only for a deliberate alphabet change, reset, or viewport reflow.

The optional tab experiment exposes the full two-letter labels and title inventories under their first-letter regions. The first key narrows into a leaf grid; the second selects immediately. A remembered sequence works without waiting for the new grid to be seen. No window thumbnails or desktop geometry are involved.

**Where it may help:** someone already comfortable with Mouseless-style spatial addressing; repeated selections; reaching covered windows without a separate hidden bank.

**Cost:** a wide scan can be slower than Shore's narrow list. Empty cells consume room. Tab groups follow stable allocation rather than topic or browser window, so a first-time search may be easier in Canopy or with `/`.

This borrows the visible-region and hierarchical-key relationship described in [Mouseless's customization documentation](https://mouseless.click/docs/customizing_mouseless.html). It adapts that relationship to window identities instead of pointer coordinates.

## Fold: app first, window second

**Try:** select Fold. Press `K` for Safari, then `K` for Learner preview. `K J` selects Lesson editor. `J J` selects the Code window. Type both keys consecutively to test the transition-independent path.

Fold begins with a small app spine. Choosing a family opens its adjacent window sheet, giving similar titles more space and reducing the number visible at once. Unlike Canopy, it does not present every family's windows simultaneously.

Fold intentionally has a **different address vocabulary**. A complete window address combines the stable app address with a stable local window address. It always requires both stages, including singleton apps. Opening a second window must never change a one-key action into a prefix. Closing or adding a sibling window preserves the other full addresses.

`Backspace` removes the pending prefix, and `Escape` returns through the shared back/cancel behavior. `/` searches all windows globally, from either stage. Enter in search selects its highlighted result. The initial proposal considered branch-local search; the integrated prototype uses the shared global behavior to keep the mode boundary explicit. Apps scope still provides ordinary direct app selection.

**Where it may help:** several similarly titled windows concentrated in a few apps; a user who thinks of an application before its document title.

**Cost:** normally two selection keys instead of one. It should lose to direct addressing for many singleton apps unless reduced visual competition demonstrably helps. Overflow can add more letters. No tabs are added to Fold: a third hierarchy level is not justified merely because the interface could contain one.

## Relay: a clear way back

**Try:** select Relay. Its initial simulated history is Code after Lesson editor. Press `O` to select Terminal, reopen with Space, and press `Enter` to return to Code. Repeat Space, Enter to alternate. Then use `L` to deliberately break the pair.

Relay makes one action prominent: return to the previous distinct live window. A small current-window marker connects to a larger return card near the current work. All other windows remain visible in a direct-address shelf. The current window's letter is visible in its marker; the return target keeps its normal letter too.

The gallery starts with a synthetic previous-window fixture so this behavior can be inspected immediately. After that, history follows actual selections in the simulation. Selecting the current window does not change history. Opening, cancelling, searching without selection, or changing the visual concept does not change it either.

`Enter` is explicitly a changing **command**, not an immutable address. The `J K L…` window labels remain exactly the same as in Shore, Beacons, Canopy, and Lattice. Enter applies only in Relay's direct window mode; in search it selects the highlighted result. If the previous target is no longer available, the return card shows an empty state and Enter cannot select a closed window. This prototype keeps only the prior distinct target, rather than inventing a longer fallback history.

**Where it may help:** repeated editor/preview, terminal/editor, or writing/reference alternation.

**Cost:** it spends attention on a predicted destination that may not be wanted. A three-window loop is less predictable. Enter does not save a key compared with a learned direct letter; its possible advantage is avoiding recall and search. No tab history is mixed into this window-level experiment.

## Compare by scenario, not novelty

| Scenario | Strong candidates | What must improve |
| --- | --- | --- |
| Random jumps among 6–10 windows | Shore, Lattice | Fast recognition and learning without extra input stages. |
| A known visible window | Beacons, Lattice | Spatial memory must reduce searching, not send the eye to a stale location. |
| Similar windows of one app | Canopy, Fold | Fewer wrong-window choices and less title scanning. Fold must repay its extra key. |
| Repeated two-window work | Relay, direct letters in any flat mode | Less mental effort without confusing the next destination. |
| Covered or minimized windows | Shore, Canopy, Lattice, Fold | Equal visibility and reliable selection; no native support is implied by the simulation. |
| Larger tab collections | Canopy, Lattice, explicit search | A manageable scan that beats guessing arbitrary first-letter groups. |

The shared benchmark is already activation plus one selection key for the ordinary flat window set. New models cannot beat that by adding visual ambition. They need to improve recognition, error recovery, comfort, or a particular work pattern.

Multiple modes could eventually be useful. Keep them only if different scenarios show repeatable value; do not make the user operate all six to accomplish a normal switch. A visually appealing model that adds hesitation should stay a design study.

## Keyboard contracts preserved

- Space latches the demo open; held left Shift peeks for right-hand selection. The left-hand preset uses right Shift. These remain browser surrogates, not proposed system-wide captures of ordinary typing.
- Letters commit synchronously on the final keydown. No animation or prefix timeout gates input.
- `/` explicitly starts text search. `Escape` returns to addresses. `1`/`2` switch windows/apps; `3` is supported by Canopy and Lattice only.
- Held-Shift command keys use physical command positions for slash and scope digits, so shifted glyphs do not break these shortcuts. Search text itself retains ordinary typing behavior.
- Browser Tab navigation and Enter/Space activation of focused buttons remain available.
- Right-hand, left-hand, and custom ordered alphabets remain in the prototype lab, outside product UI.
- Reduced motion comes from either the operating system preference or the demo toggle.
- Both target churn and search-result changes clamp selection state. Simulated windows live in a separate stacking context, so repeated focus changes cannot rise above the switcher.

## Limits and next decision

All windows, titles, app icons, minimization, focus history, and tabs are synthetic. This can test visual recognition and interaction coherence. It cannot establish native input latency, memory footprint, energy use, actual window enumeration, title extraction, stable native identity, multi-display behavior, Spaces, permissions, or browser tab support. Short labels are curated, not evidence of an automatic native title algorithm.

No installation, OS permission changes, launcher, workspace manager, native app, deployment, or commit is included. The decision now is which interactions warrant real user comparison. Product scope follows that decision.

## Team contributions and verification

- [Lattice proposal](./proposals/mouseless.md)
- [Fold and Relay proposal](./proposals/new-models.md)
- [Independent critique and user test matrix](./proposals/critique.md)
- [Original three-concept rationale](./DESIGN-NOTES.md)
- [Browser verification record](./VERIFICATION.md)

The proposal documents preserve independent reasoning, including options that were not integrated. The behavior described in this document is the final gallery contract.
