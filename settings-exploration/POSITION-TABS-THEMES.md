# Position, browser tabs and customizable themes

Update: 17 September 2026. The user likes the settings window and its room for future areas, and requested placement controls, browser tabs, predefined themes and customization. These are now included in the [interactive prototype](./tabnax-settings.html). The six original gallery concepts remain unchanged; the settings preview now implements all six. See [required mode functions](./SIX-MODE-COVERAGE.md). Arc and Zen are required browser targets; native connections remain unverified. See [browser support](./BROWSER-SUPPORT.md).

The toolbar is **General / Selection / Position / Appearance / Browser Tabs**. Keep one clear purpose per pane. The implementation interprets “position” as the switcher’s screen placement. The settings window itself remains an ordinary movable macOS window in the native proposal.

## Themes

| Preset | Treatment | Purpose |
| --- | --- | --- |
| macOS | Neutral light/dark surfaces, restrained gray keys and familiar blue selection | Preserve the native feel of the settings preview; default |
| Tabnax | Original green `#d9f68c`; green-tinted light surface and `#202720` dark surface | Retain the character of the initial design concepts |
| Sage | Softer green keys and neutral surface | Quieter green alternative |
| Iris | Violet keys and neutral surface | Additional predefined choice |

The macOS preset keeps the internal identifier `graphite` for compatibility with existing browser preferences. Settings chrome remains restrained across presets; themed surfaces and accents appear in the switcher preview. System / Light / Dark is independent of preset selection.

**Customize this theme…** exposes key background and selection color. Each preset stores its own light and dark overrides. Under System appearance, the disclosure names the currently edited appearance. Changing a preset or appearance restores its corresponding saved colors. Changes preview and persist immediately without reallocating window or tab labels.

Key letters automatically use whichever of black or white has stronger contrast. Selection colors must reach 3:1 against the opaque preview surface; a color below that threshold is shifted toward a readable shade, with a visible explanation. The requested color remains in the picker, while the preview shows the adjusted result. Colors never encode target identity on their own. Native compositing, focus states and accessibility still require platform validation.

**Reset this theme** clears both light and dark overrides for the selected preset, keeps other presets intact and offers Undo. **Restore defaults** clears every override along with the other Tabnax preferences. No color edit needs a confirmation dialog. Continuous changes in one color control share one undo checkpoint.

Included: four presets, two editable colors, independent appearances, automatic legibility, persistence and recovery. Deferred: surface/font/opacity editors, blur/animation controls, theme naming/duplication, importing/exporting profiles. Curated surfaces retain a coherent native appearance while covering the requested customization.

## Position

Placement is saved separately per display mode. Defaults: **active-window display / 24 pt edge spacing**, with Shore/Relay middle right, Beacons bottom center, Canopy top center and Lattice/Fold center. Users can choose active-window, pointer or main display; any of nine anchors; and 12–64 pt edge spacing in 4 pt steps. Centered axes ignore edge spacing and stay centered. A dedicated desktop diagram makes the intended result visible, including sample main/external displays. The prototype’s active window is on External; pointer is on Main.

Native placement contract:

1. Resolve the selected display when opening: active-window screen, pointer screen or main screen. If the requested display cannot be resolved, use the main display, then the first available usable display. Do not persist an obsolete display identifier as a forced destination.
2. Calculate within the display’s usable frame, excluding menu bar and Dock reservations. Apply the chosen inset at edge-aligned axes; center other axes. Clamp the result within usable bounds. If content is larger than the available area, constrain the panel and scroll its contents.
3. Freeze that frame during a switching session. Pointer motion, changing selection or new windows must not move the switcher beneath input. A disconnected display triggers safe re-clamping; keep the address map unchanged.
4. Within each mode, use the same panel position for windows and tabs. Beacons remains a special visual mode: labels follow their actual windows; these controls govern its shared control/out-of-sight panel, not every plaque.
5. Save placement immediately for the next native session. Provide **Use default position** and Undo. A reset changes only the current mode’s placement. Other modes retain their choices.

The web diagram illustrates anchors and display rules. It does not move a native overlay, discover actual monitors or verify coordinate transforms, Dock autohide, display scaling, Spaces, Stage Manager or full screen. Those belong in the native validation matrix. No arbitrary per-window offsets or manual pixel coordinate editor are added.

## Browser tabs

Tabs are requested product scope. **Arc and Zen are required targets.** Safari, Chrome, Firefox, Edge and Brave complete the proposed initial list. All seven are sample connections in the prototype. [Browser coverage and minimal setup](./BROWSER-SUPPORT.md) records the preferred adapters and evidence. Each browser row explicitly says “sample tabs only.” The prototype cannot enumerate real tabs, install an extension or request OS permissions.

Preferences: include tabs; automatically include available browsers or choose individual browsers; show all included browsers / active browser / active browser window; and open to Windows or Browser tabs. Windows remains the proposed initial view. Turning tabs off returns to Windows; Undo restores the prior tab view and preferences. When no matching browser/window is available in native operation, show an explanatory empty state; do not silently reinterpret the filter.

Use separate window and tab views so a larger tab collection does not crowd the normal 6–10 windows. Buttons and the reserved `1` / `2` commands switch scopes during direct input. Switching clears the partial sequence and preserves each namespace’s live labels, pins, retired labels and visual slots. Digits typed in search remain search text. The shared alphabet is applied to flat-window, tab and Fold maps transactionally; tabs always use two-letter labels. A window-only policy change leaves the tab map untouched. Apply or Discard a pending label draft before switching views.

Each row identifies title, browser and browser-window context. The sample contains 48 tabs across seven browsers and Work/Personal windows. Native labels follow an adapter-provided identity, not URL/title matching. Navigation, rename, reordering and moving a surviving tab preserve its label when identity continuity is confirmed. Confirmed closure retires the label. Reconnect/restart creates a new adapter generation; recycled IDs cannot inherit a previous target’s label. Select the exact tab and focus its containing window; verify completion or report failure without falling back to an arbitrary sibling.

Private tabs are excluded. Keep only the live metadata needed for switching; do not store browsing history, page contents or search queries. Preferences contain no tab titles, URLs or IDs. Native availability must distinguish disconnected, access needed, denied, revoked, connected and temporarily unavailable. Revocation stops enumeration and clears affected live metadata; window switching and settings remain usable.

For a possible Chromium extension adapter, Chrome’s official Tabs API documents access requirements for sensitive tab metadata. Temporary `activeTab` access does not supply a durable catalogue of every tab. Activating a tab also does not necessarily focus its window, so focus is a separate step. This supports a narrow metadata-and-focus adapter, subject to implementation verification; it does not establish Safari or other Chromium-browser compatibility. [Chrome Tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs).

Choose the actual browser adapters only after verifying exact-tab focus, profile/window identity, private-mode exclusion, consent and revocation behavior. The current design does not assume a blanket Accessibility grant provides browser tabs. It adds no page-content reading, tab-history synchronization or browser-management features.

## Decisions and acceptance

| Decision | Reason | Alternative deferred |
| --- | --- | --- |
| Extend the accepted toolbar to five panes | Position and browser connections have distinct, requested responsibilities | Replacing it with a large sidebar |
| Keep macOS and original-green presets | Cover both visual directions explicitly requested | Replacing the native palette with green everywhere |
| Two editable colors with automatic contrast | Immediate customization with predictable readability | Full theme designer |
| Nine anchors and a display rule | Predictable placement without fragile coordinates | Free dragging with saved absolute coordinates |
| Separate tab namespace | Preserve learned window labels as tab counts grow | One mixed list with shared label capacity |

Acceptance: select each preset in light/dark; customize, reload, reset and undo; check all anchors within the diagram; filter and switch scopes without label changes; change the shared alphabet and undo all affected maps; check disabling tabs and old-preference migration. Layout must remain readable with expanded customization, small viewports and enlarged zoom. Results are recorded in [Verification](./VERIFICATION.md). Native browser support and actual display/window focus remain outside the prototype’s evidence.
