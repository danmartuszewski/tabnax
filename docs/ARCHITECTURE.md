# Architecture

Tabnax is a menu-bar application built with AppKit for switcher panels and SwiftUI for settings. `TabnaxCore` supplies testable models shared by native UI and controlled fixtures. There is no web view dependency in the native app.

| Component | Responsibility |
| --- | --- |
| `AppDelegate`, `ApplicationShortcuts` | Startup, menu bar, login registration, app integration. |
| `InputRouter`, `ShortcutExceptionRouter` | Activation chord, foreground exceptions, event ownership, Carbon registration lifetime, direct addresses, navigation and search. |
| `WindowCatalogue` | Public AX window discovery and process/window lifetime identity. |
| `BrowserCatalogue`, `BrowserBridge`, `BrowserTransport` | Browser adapters, connection status, bounded local protocol. |
| `FocusCoordinator` | Exact window/tab selection with follow-up identity confirmation. |
| `ModePresenter` | Six native layout renderers, retained views, preview rendering. |
| `SettingsController`, `SettingsDesign` | Seven settings panes, drafts, scoped resets, native preview. |
| `TabnaxCore` | Settings, address books, navigation, app assignments, themes, layouts, browser protocol. |

## Selection flow

1. Native catalogues discover apps, exact AX windows, and approved browser tab metadata.
2. Core models allocate stable addresses before visibility filters. Flat and app-grouped layouts have separate allocation books.
3. Opening the switcher freezes address meanings, traversal ranks, group/overflow positions and return history for that session. Metadata can update; new meanings wait for a fresh session.
4. Input chooses a target through a direct address, navigation, search, or optional mouse action.
5. The focus coordinator acts on the exact identity and confirms focus. Stale targets and competing input cancel pending follow-up work.

Discovery and observer work are bounded and happen away from the keypress path. The current implementation avoids periodic desktop polling, private WindowServer APIs, and window image capture. Search remains available for targets beyond address capacity.

## Browser adapters

Arc/Chrome/Edge/Brave use Apple Events with browser-specific consent. Firefox/Zen use a companion and native messaging host. Safari has an embedded web extension and native handler. The local bridge uses length-prefixed JSON and per-user Unix sockets, with size, sequence, connection, and target lifetime checks. The [security policy](../SECURITY.md) describes the trust boundary.

## Website and prototypes

`website/` is a standalone HTML/CSS/JavaScript presentation with synthetic demo state. It cannot inspect or focus real windows. Its PNG gallery contains native own-view exports. Historical studies preserve earlier behavior contracts; they are not linked into the native product.

See the [feature inventory](PRODUCT.md) for current capabilities and the [native app guide](../macos/README.md) for implementation and browser setup details.

## Window actions

`SelectionState.actionMenuItems` resolves the highlighted row or Fold app branch into immutable action/target pairs. Window operations require a catalogue window ID; app/tab rows never fall back to a window. `FocusCoordinator.inspectActions` checks the captured process lifetime and exact AX handle on the reserved worker lane, and `WindowActionAccess` checks enabled controls or writable minimized state. Execution repeats live checks. Normal close presses `kAXCloseButtonAttribute`; zoom and fullscreen press their distinct public AX controls. No global shortcuts, force termination or private window IDs are involved.

`InputRouter` synchronously gates menu input before main-thread presentation, disarms hold/latch release selection, consumes pending keys until AppKit is ready, then hands tracking to NSMenu. The presenter freezes command IDs, suppresses hover/spotlight during tracking and lets AppKit retain the search field editor. Closing a window dismisses the switcher before sending the normal close request. Other actions suspend focus preview until explicit navigation. Menu outcomes are scoped to their originating session/target. The `windowActionsEnabled` setting defaults to true when decoding older documents and preserves all prior settings.

## Search ranking and consent

`SearchField` caches normalized characters and word/camel-case boundaries independently for app, title and context. All terms must match, and an ordered-subsequence scorer retains meaningful symbols and gives whole-field, prefix and contiguous matches precedence over initials and looser matches. `SelectionState` rebuilds ranked matches when the query, searchable metadata or choice memory changes; repeated navigation reuses that ranking. Stable ties use the session’s chosen traversal order. `displayMatches` is the shared search presentation/navigation source; closed-app launch targets are excluded there and selection rechecks eligibility. Grouped layouts order groups by their strongest result; Canopy columns and Fold's spine follow that same order. Relay's search grid does not reorder results by focus history. Empty-query layouts and direct addresses retain their established behavior.

`rememberSearchChoices` defaults to false when absent or malformed in schema-v1 documents. `Preferences` loads/writes the separate `searchChoices.v1` state only with explicit consent. `SearchMemory` holds at most 128 recent digest pairs, rejects malformed entries, uses length-framed fields and a random per-store salt, and never serializes raw queries or target metadata. It can influence ranking after a restart but cannot resolve an identity or bypass availability checks. Unrecognized/oversized state is discarded without invalidating settings. Clear/off/reset removes persisted choices; the salt also serves as a generation guard against delayed input callbacks repopulating cleared memory. Monotonic revisions prevent older callbacks or settings snapshots from overwriting newer choices. Undo can restore the preference but not deleted choices. The native input thread retains a value snapshot, with persistence on the main thread; native field-editor/IME ownership is unchanged.


## Exclusion and activation routing

`ExclusionPreferences` in TabnaxCore filters the owner-resolved, labelled snapshot. App rules compare durable bundle IDs, including closed launch targets; title rules inspect only windows and tabs. Filtering never reallocates labels or changes target identity. `suppressedIDs` distinguishes explicitly excluded live targets from ordinary disappearing windows so `reconcilingLive` removes them instead of retaining disabled rows. The same model feeds settings previews and every presentation/search/navigation/spotlight mode. The native focus registry and launch registry reject excluded targets as well.

`ShortcutExceptionRouter` is a reusable, shortcut-independent foreground policy. Its main-actor KVO and workspace observers resample the actual frontmost app, ignore our own PID and spotlight preview activations, publish a lock-protected `ShortcutExceptionGate` to the input thread, and configure fallback registration. Startup configures policy before registering. Deactivation temporarily releases registration until the foreground identity changes; delayed notification payloads cannot overwrite a newer foreground identity. Registration and Carbon dispatch recheck foreground identity. Carbon APIs stay on the main actor because the public SDK marks them non-thread-safe.

`HotKeyFallback` actually unregisters when suspended, rejects callbacks from older registration generations, and delays registration until the trigger key is released. `InputRouter` separately tracks keys that began passing through an exception, preserving repeats and key-up even if rules or foreground change mid-sequence. Existing switcher-owned key sequences remain owned. The explicit settings recorder keeps precedence, and manually opening a switcher allows normal navigation. The main and opt-in search shortcuts share this policy/gate, including recorder suspension and foreground resampling on deferred retry. Each fallback instance owns a distinct Carbon signature plus its own registration generation. Its installed handler returns `eventNotHandledErr` for other signatures so sibling callbacks continue through the application dispatcher. Tests send real Carbon events through that dispatcher and verify both OS reservations release in an exception.

## Traversal ordering and observed focus

`TraversalOrder` is a schema-v1 additive preference, defaulting to `stable` on missing/unknown/malformed values. `SelectionState.open()` sorts already-labelled leaves by the chosen policy, then captures target, owner and address-branch ranks separately from `TargetID` and address books. `update()` keeps those ranks while reconciling metadata/availability; group ranks survive removal of their original first child. New identities are held out by the existing `reconcilingLive` boundary. Search reranks by score with the frozen sequence as its tie-breaker. Grouped layouts use the first ordered child for group rank, while childless app rows retain their own sorted position. Lattice’s shared branches remain after app-owned cells, and unaddressed targets remain after the grid.

Presentation and keyboard navigation share ordered target sequences. Relay retains its default current/previous pair and Enter behavior, using opening history even when catalogue history changes. With an optional order its pair contains the first two ordered targets. Beacons' optional-order/search bank preserves the flat traversal subsequence across target kinds; plaques remain spatial. Closed app launchers stay addressable but have no invisible traversal stop. Native field-editor, accessibility press and exact focus identity paths are unchanged.

`FocusHistory` remains runtime-only. `FocusCoordinator.observationToken` is nil during focus/preview work and otherwise identifies the current generation. Catalogue discovery captures the token before AX reads and requires the same non-nil value on completion. Thus a preview read cannot become real recency just because cancellation completed before its callback. Cancelled previews keep their activation provenance (including while an actions menu is open) until a verified selection or a different external activation replaces them; failed selection does not clear it. Verified final focus outcomes still call `recordObservedFocus`; preview completion and selection/navigation intent do not. Escape restores the opening history’s current window, independent of later catalogue history.

## Search activation

`searchActivation` is a schema-v1 additive preference with an explicit disabled default and independently recorded chord/side. Validation compares key, modifiers and side overlap with the main activation. New Shift-only printable chords are rejected; decoding legacy main chords repairs only the unsafe chord so unrelated settings do not become read-only.

Both the tap callback and Carbon dispatch enter `InputRouter.activateSearch`. Opening clears hold/cycle/release state, bypasses quiet return, and publishes search in the first visible frame. Already-open invocations retain the session and frozen ordering; repeated search preserves query/highlight and marked text. The presenter focuses its existing native editor without selecting all. A session-scoped handoff queues early CG key-down events until the presentation callback has focused the field, then gives the original events to the native field editor. The tap owns their repeats/key-up consistently; after handoff, normal AppKit text/IME processing resumes. Native replay tests cover the early text/Enter path, and isolated UI tests exercise the actual callback and Carbon dispatcher through local app events without global capture or real target actions.

## Simultaneous display presentation

`SettingsDocument.allDisplays` defaults to false, including absent/malformed saved values. The existing shared display preference selects the initial input owner when enabled. `SwitcherPresenter` freezes the display inventory for the opening and gives each non-recursive `SwitcherSurfacePresenter` the same published `SelectionState`, settings and callbacks. Renderers own geometry and reusable views; only `InputRouter` changes selection or executes an action. Each panel uses its own AppKit visible frame, including negative origins and mixed backing scales. Embedded and exported previews stay single.

Only one renderer owns the native search editor. Pointer/key-window changes transfer that ownership before input dispatch. The old editor finishes marked text, then its committed string and selection move to the destination before it accepts another keystroke. The coordinator retains the latest pending native query until the asynchronous router acknowledges its edit revision (including repeated or truncated text); older publications cannot overwrite immediate typing after a handoff. It does not duplicate input contexts or IME composition. Menu tracking is exclusive across the cohort, disarms modifier-release selection, and suspends hover/spotlight everywhere. All bank/plaque frames are published together to the event router.

Beacons repeats the full bank while the primary renderer alone plans spatial plaques against every bank footprint. Separate plaque rows avoid reparenting bank content. Only the primary renderer owns desktop spotlight surfaces. Dismissal closes all panels, plaques and spotlight surfaces and cancels menu tracking; display changes and wake also cancel the router and focus preview before a fresh opening. Native window renders and accessibility attachments use fictional targets, avoiding unrelated desktop captures.
