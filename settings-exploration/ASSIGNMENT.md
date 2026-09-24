# Letter assignment: learnable first, clever second

## Recommendation

Recommend **stable automatic assignment using an ergonomic ordered alphabet**. Allocate once when a confirmed identity enters an address session. Never rearrange labels on activation, focus frequency, title change, temporary invisibility, or a new sibling window. Use one reserved overflow key from the beginning so growth cannot turn an already-selectable letter into a prefix. Show a clear prefix indicator and accept the entire sequence without waiting for rendering.

Right-hand default: `J K L U I O N M H P`. The final `P` is a branch, never a window. This is a comfort-order hypothesis for the user's QWERTY-like reach, not a claim of universal ergonomic optimality. Changing hand is an explicit draft operation; other layouts require a captured key map.

## Concrete default examples

| Target, in deterministic first-observed order | 6 windows | 8 windows | 10 windows |
| --- | --- | --- | --- |
| VS Code · Tabnax | J | J | J |
| Safari · Tabnax Keyboard guide | K | K | K |
| Safari · Tabnax Layout preview | L | L | L |
| Finder · Assets | U | U | U |
| Figma · Interaction studies | I | I | I |
| Terminal · zsh | O | O | O |
| Notes · Interview notes | — | N | N |
| Safari · Personal routes | — | M | M |
| VS Code · Review diff | — | — | H |
| Finder · Exports | — | — | PJ |

At ten, type `P J` to select Exports immediately. `P` alone selects nothing and has no timeout. The eleventh identity gets `PK`. The nineteenth gets `PPJ`; the earlier labels do not change. An alphabet with `b` keys gives `b−1` direct leaves at each reserved-prefix depth.

Native initial ordering must be deterministic within a snapshot: recommended app display name (localized stable comparison), then process generation, then confirmed window discovery ordinal; persist the observation ordinal for the live identity. Avoid deriving address order from changing title strings or MRU focus. The fixture table uses curated discovery order solely to keep the examples easy to compare. Prototype array order is not a verified native discovery order.

## Algorithm comparison

| Policy | Example and benefit | Tradeoff | Recommendation |
| --- | --- | --- | --- |
| Stable ergonomic | New targets consume `J,K,L,…,H,PJ,…`; existing assignments remain | Some letters do not suggest the app name; branch adds a key after nine | Default |
| Name initials first, frozen at allocation | With right alphabet, VS Code falls back to J; Safari’s “Keyboard guide” gets K; its sibling can use L from “Layout”; Notes gets N | Initials outside alphabet cannot help; same-app collisions; results depend on discovery order and title at allocation | Explicit advanced experiment; no rescoring after rename |
| All fixed pairs | `JJ,JK,JL,JU,…,JP,KJ,KK…` | Every selection takes two keys even for six windows | Useful for larger collections; not default for 6–10 |
| Session pin | Pin Code to free H; J becomes held; K/L and other labels stay | Cannot steal K; not reliable across native window recreation/restart | Optional advanced action, no smart title matching |
| Stable app prefix | Fold Safari = K; child Keyboard guide = J, Layout preview = K; complete `KJ`, `KK` | App then window always costs two stages; singleton must also have a child code | Required in Fold; independent from the other modes’ direct window map |
| Frequency-weighted / MRU / Huffman reallocation | Frequent window receives shorter or easier key | Learned labels change as behavior or population changes; probabilities are invisible | Reject dynamic assignment |
| Frozen “learned” weighting | Score at setup, then freeze | Adds training/history, privacy and explanation costs for a tiny set | Defer; direct pin is clearer if ever needed |
| Sequential labels rebuilt every invocation | Minimizes current lengths | Closing first window changes every later target | Reject |

Do not market all methods as equivalent. Ship stable alone initially if the alternatives add more decisions than value. The prototype exposes all three policies to make the comparison concrete; the optional-pins label deliberately marks the larger scope.

## Precise stable allocator

Given ordered alphabet `A = [a0…a(b−1)]`, let `r = a(b−1)` and `L = A` without `r`. The leaf vocabulary is `r^d + l`, for depth `d ∈ {0,1,2,3}` and each `l ∈ L`, traversed depth first by increasing depth, then alphabet order. Equivalently: all one-key leaves, then branch + all leaves, then branch-branch + all leaves, and so on. **Maximum leaf length is four** in the proposal and executable model. Fold concatenates app and child leaves, so its complete address can reach eight characters. No complete address is a prefix of another: every label ends in a nonbranch letter.

State per namespace: ordered identity list, live identity→label map, retired-label set, optional pins, monotonic visual slot ordinal and a generation. Allocate the first unoccupied, unretired leaf. In mnemonic mode, first try initial letters from app display-name words, then window-title words, in that order, if they are available one-key leaves; otherwise use the same pool. Pin reservations seed the pool before a deliberate full reassignment. For fixed pairs, enumerate `A × A`; every complete address has exactly two keys. A complete pair such as `JP` is allowed because all labels have equal length; the last letter is not a dedicated overflow branch in this policy.

Four-key capacity with a ten-letter alphabet is 36 consumed addresses, including retired addresses. With six letters it is 20. Pair capacity is `b²`, including retired pairs. No silent extension beyond the advertised bound. On exhaustion, preserve every current address and expose new targets as unaddressed (`—`) with a click/arrow/search fallback and the message “All short labels are in use. Reset labels to reuse closed-window labels.” Reset remains explicit. The prototype allows up to 40 targets to exercise this; a dash still permits pointer/native Tab activation and explicit search. The fallback cannot become an excuse to silently reassign learned labels.

A larger future hierarchy may reserve multiple branches to keep many windows within two keys, but it spends scarce one-key letters and changes the learned vocabulary. This is unnecessary for the initial 6–10-window case. Browser tabs use a separate pair namespace and do not consume the window allocator’s overflow budget.

## Lifetime, identity and collisions

| Event | Required result |
| --- | --- |
| Select, cancel, change theme, reopen overlay | Labels and slots unchanged |
| Rename title or app display name | Identity and label unchanged; no mnemonic regeneration |
| Open another window | New label and slot; current session snapshot admits it only next opening |
| Confirmed close | Disable target immediately; retire label and hold Lattice slot; clear a pending stale sequence; no reassignment of survivors |
| Temporary enumeration failure / hung app | Preserve identity as unavailable; do not treat as confirmed close |
| Hide/minimize, or eligibility checkbox off | Keep label reserved for that live identity; re-inclusion restores it |
| Native app restart / uncertain identity recreation | Old window labels retire; new process/window generations receive fresh labels |
| Tabnax restart | Preferences survive; window address session restarts. Do not infer identity by equal titles |
| Session reset | Clear retired set and window pins, rebuild live labels and slots; disclose before Apply; Undo possible while snapshot valid |
| Alphabet reorder / change | Compute draft map against same identities; count changed labels; blocked until valid; atomically apply new generation |
| Incompatible existing pin | Block apply with the conflicting pin named; resolve/clear it explicitly, never silently drop it |
| Duplicate manual mapping | Reject, name the occupied label/target; no automatic swap or stealing |
| Prefix reservation | Stable/mnemonic: P, PP etc. are branches; PJ/J etc. are leaves. Reject pinned P, JP (outside grammar), or any code containing a command key |
| Reclaiming a retired code | Only explicit reset/new address session, never a timer or “when the list gets long” |
| Undo after catalogue churn in native app | Restore config, reconcile still-live identity generations; never resurrect a closed window or allow a recycled native ID to inherit an old target |

The simulation's Undo can restore synthetic windows because they are fixtures; a native Undo must not reopen real windows. A native reassignment Undo can restore labels only for still-matching live identities; show the number that could not be restored, retain fresh labels for the others, and keep the result prefix-free. This is a limit of the browser simulation, not a cross-app undo promise.

**First collision example:** after eight windows, pin Code to K → blocked (Keyboard guide owns K). Pin Code to P → blocked (prefix). Pin Code to H → preview changes only Code; J is held; pinning another window to H → blocked. Adding a target consumes PJ if all other one-key labels are occupied or held. Changing to a left-hand alphabet that lacks H → blocked while the H pin remains; reset pins first, then preview the new alphabet.

**Churn example:** close Keyboard guide K after the default eight; open a new Safari window → H. Layout preview stays L. Open one more → PJ. A compact list removes K's row but the label never transfers. A fixed-cell grid keeps K's empty position. Reset deliberately allows compact allocation again.

## Namespaces and spatial placement

Shore, Beacons, Canopy, Lattice and Relay share the flat window-address namespace. Shore row compaction, Beacons geometry and Canopy grouping do not promise stable positions; label identity does. Lattice adds an address-cell contract: fixed alphabet-ordered cells with held places; reflow due to viewport changes may move cells and must never relabel them. Alphabet order is comfort order, not a claim that the displayed grid is a literal keyboard.

Fold has an app trie and separate child-window tries. Full address is `appCode + childCode`; each stage is prefix-free, so concatenation can be parsed unambiguously even when app codes have variable lengths. Always require the child stage, even for an app with one window. Example app J = Code and K = Safari; Code's one child J gives JJ; Safari's Keyboard guide J and Layout preview K give KJ and KK. Adding a second Code window K gives JK without turning J from an instant switch into a prefix. An empty app family keeps its prefix while the app generation is live. Native confirmed process termination retires that generation and its child namespace; the synthetic study has no process lifecycle feed. Persistent app reservations can later survive restart using verified bundle identity; window mappings cannot inherit that persistence automatically.

Browser tabs are requested scope, with their own adapter-lifetime identities and labels, never borrowed window addresses. The prototype has 48 sample tabs across seven browsers with repeated titles and Work/Personal context. It does not implement a native adapter. The native action must select the exact tab and focus its parent window, then verify success.

The preview’s **Windows / Browser tabs** controls and `1` / `2` commands switch namespaces without reallocating labels, pins or retired addresses. Clear pending input when changing views. Filters preserve reservations for excluded live tabs. The shared alphabet changes the flat-window, tab and Fold namespaces in one Apply/Undo transaction, and the change count includes every affected map. Changing only the window policy preserves the entire tab session. Pending label drafts block view changes until Apply or Discard. Tab labels are always pairs. Connection identity, restart and privacy contracts are in [the update](./POSITION-TABS-THEMES.md#browser-tabs).

## Editor and selection rules

The UI allows direct text editing, preset selection, and selected-letter arrows; keyboard users need no drag operation. Normalize whitespace and letter case, then validate length, supported tokens and uniqueness. Never silently delete duplicates. I/O exclusion is a visible edit action whose reassignment cost is previewed. Reserve slash, Escape, Backspace, Enter, Tab, arrows and scope commands before accepting an alphabet. Native non-Latin support needs key-token validation, not a larger regex.

Label errors stay adjacent to the alphabet with an alert role. Invalid drafts keep the last valid preview and disable Apply. Preview heading explicitly says “Last valid labels.” Input in the alphabet field never selects a sample window. Apply reports the number of changed assignments across flat-window, tab and Fold maps; hidden live reservations may also change and native disclosure should include them if not visible. No recurring confirmation for a color choice. Reset gets a small explanation because it discards learned mappings.

Partial input highlights a valid branch. Invalid letters do not restart a sequence implicitly or select a “closest” match. Backspace corrects it; Escape returns outward. Literal `/` search is explicitly separate. A final leaf selects on the same keydown even if the branch view has not painted. Accessible button names include app, full title and address; labels remain readable at larger sizes and without color perception.
