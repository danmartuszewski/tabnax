# Tabnax: three ways back to work

This records the original three-study exploration. All three remain in the expanded gallery. See [Additional directions](./ADDITIONAL-DIRECTIONS.md) for Lattice, Fold, Relay, the expanded tab experiment, and the current comparison contract.

This is a design decision package: three interactive alternatives, one shared input model, and a simulated desktop. It contains no native implementation and commits to no final feature set.

Open [the gallery](./index.html) in a desktop browser. It needs no build, packages, external assets, network connection, or permissions. `index.html`, `styles.css`, and `app.js` must stay together. For a local preview, run `python3 -m http.server 4173 --bind 127.0.0.1 --directory .` and open `http://127.0.0.1:4173/design-exploration/index.html`.

## The decision to make

**Shore is the strongest starting hypothesis.** A narrow, predictable scan joins an app icon, a distinguishing window title, and a letter. With eight windows, every target has one direct selection key. There is no app selection step before choosing a same-app window.

This is an interaction argument, not a measured speed advantage. Browser verification establishes that the controls work; it cannot establish that Shore beats the user's practiced rcmd workflow. Beacons is visually more unusual. Canopy may make duplicate app windows easier to separate. Keep either only if that advantage survives repeated switching.

The useful novelty here is the relationship between location, recognition, and stable direct addresses. Letter selection, app grouping, edge lists, and spatial labels all have precedents. This exploration does not claim to have invented those ingredients.

## Three distinct models

| Concept | Proposed surface and scan | Selection model | Ergonomics | Failure to watch for |
| --- | --- | --- | --- | --- |
| **Shore** | A tall, narrow surface at the right edge. Scan down icons and titles; keys form a separate aligned column. The current desktop remains visible. | One letter per window in the normal set. Apps are an optional alternate scope. | Left thumb activates, right hand selects. After learning a letter, the visual scan is optional. No pointer travel is required. | The edge is far from the current gaze on a large display. Icons repeat, long titles wrap, and larger sets become a list. |
| **Beacons** | Floating address plaques near visible window title bars. Occluded and minimized windows appear in one bottom strip. No scaled window previews. | The same direct window addresses as Shore. Focus changes real simulated stacking, so the next overlay reflects the changed geography. | Uses the user's spatial memory of the current desktop. Selection does not depend on pointing at a label. | The eye searches multiple locations. Hidden windows require a second scan. Overlapping or tightly packed windows can produce plaque collisions; the prototype demonstrates the intended behavior, not a complete placement solver. |
| **Canopy** | A surface descending from the top edge. Large app icons establish columns; windows sit beneath their parent app. | Each window has a complete direct address. Reading an app column is not a mandatory keyboard prefix. Apps can also be selected as a scope. | The app icon is a strong recognition anchor; repeated windows share one large icon. | The scan crosses the screen before moving down. A two-dimensional reading path may be slower than Shore's list. Many app families or tabs require more room. |

Beacons is deliberately the spatial outlier. It should be rejected if window geography adds hesitation. Canopy is deliberately the grouped outlier. It should be rejected if identifying the app first adds a mental step without helping disambiguation.

## Keyboard behavior

Click **Try it** or the desktop to direct keyboard input to the simulation. The initial desktop is already active.

| Key | Action |
| --- | --- |
| `Space` | Open the switcher. While open, return/back or dismiss. This is a browser-friendly activation surrogate. |
| Left `Shift`, held | Peek while held. Type an address to commit immediately; release without selecting to cancel. The left-hand selection preset uses right Shift instead. |
| Displayed letter(s) | Focus the exact target immediately on the final keydown. No Enter, timeout, release, or animation completion is needed. |
| `1` / `2` | Windows / apps. The scope is visibly named. The address namespaces are independent. |
| `3` in Canopy | Optional Safari tab experiment. |
| `/` | Enter explicit text search. It is never part of the address alphabet. |
| Letters in search | Type a query; they do not select an address. Search matches all space-separated terms in titles, context, and app names. It is simple substring matching, not fuzzy ranking. |
| `↑` / `↓`, then `Enter` in search | Choose and focus a result. Stable letters remain visible but are not active in text mode. |
| `Escape` | Exit search, clear a partial address, or cancel. Cancellation never changes window focus. |
| `Backspace` in direct mode | Undo the current prefix. |
| `Tab` | Normal browser focus navigation. It is not captured as a scope shortcut. |

Input is scoped to the desktop, so controls and text fields elsewhere in the gallery keep normal browser behavior. Losing browser focus dismisses the overlay. Modifier combinations, composition input, and key repeat cannot accidentally trigger a direct selection.

The final native activation key is **undecided**. Space and Shift in this demo are not a proposal to globally capture ordinary typing. A native candidate must be chosen around the user's Mouseless trigger, keyboard layout, shortcuts, and comfort. A tap-to-latch trigger avoids a sustained chord; a held trigger supports a quick peek. Both are represented without changing OS mappings.

## Stable address policy

- Default right-hand order: `J K L U I O N M H P`. Nine letters are available as direct addresses; `P` is reserved as an overflow branch from the beginning.
- The first eight windows use `J K L U I O N M`. The ninth gets `H`; the tenth gets `PJ`. Subsequent windows get `PK`, `PL`, and so on. The reserved branch can deepen after exhaustion without converting an existing target into a prefix.
- Addresses attach to simulated identities, not list positions, titles, recency, or the number of open windows. Changing concepts, selecting targets, and searching never reassign them.
- Closing a target retires its address for this page session. Opening a new target allocates a new address. An incomplete sequence clears on target churn to avoid a stale partial selection.
- Changing between the 6/8/10-window scenarios restores the same simulated identities; those targets keep their original addresses. This differs deliberately from the lab's **Open a window**, which creates a new identity.
- **Reset** or applying a new alphabet starts a fresh address session. The prototype does not persist identities across a page reload or simulate a native restart.
- The lab provides a left-hand preset and custom ordered alphabets of 6–12 unique ASCII letters. Six is the minimum for representing all 28 experimental tabs with two keys. Physical keyboard layout mapping and non-Latin alphabets remain a native design question.

This policy trades the absolute shortest label for predictable labels under churn. At ten windows, one extra key is better than changing a familiar address when the new window opens. Whether that tradeoff feels right needs user testing.

Visual positions are not promised stable: Shore compacts gaps, Beacons follows desktop stacking and occlusion, and Canopy groups by app. Addresses stay fixed. There is intentionally no MRU reordering of the window index.

## Optional tabs, kept separate

Canopy contains 28 simulated tabs across three Safari windows: Work / Keyboard guide, Work / Layout preview, and Personal / Saved routes. Similar lesson titles, long reference titles, repeated domains, and different window contexts make naive title search less conclusive.

Every tab starts with a two-letter address. Typing the first letter dims other prefixes without relabeling anything; the second selects immediately. `/ pronouns` narrows the collection while preserving addresses. Enter focuses the tab's simulated parent window and updates its title.

This asks whether a grouped top surface can make a larger collection manageable. It does not imply that Tabnax should ship tabs, support all browsers, or acquire browser permissions. Tabs are inaccessible from the other two concepts to keep their core window comparison focused.

## Desktop and visual choices

- Eight initial windows across six apps, including three Safari windows, two nearly identical Tabnax work titles, and one minimized personal window. Six and ten-window presets stress the same structures.
- Icons are locally drawn approximations for recognition; no external image or font assets are required. All desktop content is synthetic.
- The wallpaper and overlapping, readable app interiors make the desktop context visible. They are not candidate thumbnails in the switcher.
- The switcher uses opaque dark surfaces, quiet metadata, and high-contrast pale green key badges. The color marks what to press rather than coloring every window differently.
- Short window titles are curated for this experiment. Full long titles are available through each target's accessible name and pointer tooltip. Automatically deriving useful title distinctions is unproven.
- Selection handlers execute synchronously. Only small surface movements use CSS transitions; input is enabled before they finish. The system reduced-motion preference and lab toggle remove those transitions.
- The gallery's concept navigation, scenario controls, alphabet controls, and explanatory copy sit outside the proposed product surface. None is a proposed Tabnax settings screen.
- On compact screens, Shore fills most of the desktop region, Canopy reflows, and Beacons stacks labels. This is an inspection fallback; judge desktop spatial ergonomics at desktop width.

## What to test with the user

Keep the alphabet and window set constant while comparing concepts. Rotate concept order to reduce the learning advantage of whichever comes last.

1. **First recognition:** locate and select the Tabnax Layout preview window without search. Observe eye wandering and title ambiguity.
2. **Repeat use:** switch to Terminal, Finder, and the same Safari window several times. Observe whether addresses start replacing visual scanning.
3. **Same-app distinction:** alternate between the guide editor and layout preview. Watch wrong-window selections and time spent parsing shared words.
4. **Churn:** learn one address, open another window, close the focused window, then return to the learned target. Watch confidence, not just correctness.
5. **Hold versus latch:** try both activation behaviors. Watch hand tension, accidental cancellation, and conflicts with existing muscle memory.
6. **Optional tabs:** find the layout preview for object pronouns among 28 tabs. Compare reading grouped columns with `/ pronouns`. Decide whether the extra scope helps enough to justify itself.
7. **Return to rcmd:** repeat the same real switching sequence in the user's practiced setup. If none of these concepts reduces hesitation or increases precision, stop; visual novelty alone is insufficient reason to build another utility.

Useful observations are wrong-target count, recovery steps, number of visual searches after learning, preference under fatigue, and ease of distinguishing same-app windows. A browser demo can collect human observations about these, but this package does not invent a benchmark score or claim measured speed superiority.

## Boundaries of the evidence

The prototype can establish whether these layouts are readable and whether their simulated state transitions are coherent. It cannot establish native activation-to-focus latency, memory use, energy use, or app size. It cannot validate real window enumeration, title availability, stable native identities, focus permissions, Spaces, full-screen windows, multiple monitors, or browser tab access. It does not call any native API or request any OS permission.

In Beacons, occlusion is approximated from a point near the leading edge of each simulated title bar. Native geometry, display boundaries, collision avoidance, and more complicated occlusion need separate work only if the concept wins. The test desktop should not be mistaken for proof that all native windows can be labeled this neatly.

## Focused primary-source inspiration

Sources inspected on 17 September 2026. These informed the boundaries; the prototypes are original compositions.

- [rcmd's product page](https://lowtechguys.com/rcmd/) describes right-Command letter switching, dynamic assignment, search, and broader app/workspace actions. The relevant inspiration is direct addressing. This exploration keeps the user's focus on open windows and avoids a launcher or workspace manager.
- [Mouseless customization documentation](https://mouseless.click/docs/customizing_mouseless.html) describes configurable selection keys and hierarchical grids. That supports exploring ordered alphabets and short sequences without assuming a fixed handedness or mnemonic app name.
- [AltTab's primary repository releases](https://github.com/lwouis/alt-tab-macos/releases) provide a useful reminder that real focus behavior and window lifecycle handling are a separate engineering problem from a polished visual switcher. No AltTab implementation is copied here.

## Decision gate

Choose a visual interaction, or reject all three. Only then decide the minimum native scope: likely windows first, with apps, tabs, and search evaluated individually. No launcher, workspace manager, general command system, large preference tree, native implementation, deployment, or commit is included in this exploration.
