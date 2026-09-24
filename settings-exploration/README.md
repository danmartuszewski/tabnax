# Historical settings exploration

This is a historical, simulated design study. For the current six-pane settings implementation and browser adapters, use the [native guide](../macos/README.md). The current product presentation lives in [website/](../website/README.md). Statements below about deferred native work describe the original study.

A focused macOS settings proposal with five panes, six working display modes, a live assignment sandbox and theme preview. All behavior is simulated. No native app, OS settings, permissions, gallery files or research files were changed; no tools were installed and no commits were made.

**Start:** [self-contained interactive prototype](./tabnax-settings.html). It embeds its styles, scripts, icons and synthetic data, with no external requests. Double-click to open in a desktop browser. Local file storage behavior depends on the browser. If a browser tool blocks `file:` URLs, serve this repository locally:

```sh
python3 -m http.server 4174 --bind 127.0.0.1 --directory .
```

Then open [the local prototype](http://127.0.0.1:4174/settings-exploration/tabnax-settings.html). No package install or build step is needed to use it.

## Planned additions

- [Optional mouse control: detailed implementation plan](./plans/MOUSE-CONTROL-PLAN.md) — Off, Click to select, or Click + wheel selection across all six modes. Includes native/study differences, event ownership, accessibility, phased tasks and acceptance gates. Planned only; this option is not yet in the prototype.

## Design package

- [Scoped restore controls and UX review](./RESET-RECOVERY.md)

- [Required functions across all six display modes](./SIX-MODE-COVERAGE.md)
- [Browser coverage and minimal setup](./BROWSER-SUPPORT.md)
- [Position, browser tabs and customizable themes](./POSITION-TABS-THEMES.md)
- [Settings specification and primary-source research](./SPECIFICATION.md)
- [Prioritized functionality/defaults matrix](./INVENTORY.md)
- [Assignment recommendation, examples and edge cases](./ASSIGNMENT.md)
- [Configuration/runtime model and native contracts](./CONFIGURATION.md)
- [User evaluation guide](./EVALUATION.md)
- [Validation results and screenshots](./VERIFICATION.md)

The toolbar now contains **General, Selection, Position, Appearance and Browser Tabs**. Appearance offers **macOS, Tabnax (original green), Sage and Iris**, with separate light/dark custom key and selection colors, automatic readable text, preset reset and Undo. Appearance also selects Shore, Beacons, Canopy, Lattice, Fold or Relay. Position remembers nine-point placement, display selection and edge spacing separately for each mode. Browser tabs have a separate, stable pair-label namespace, range selection and a default opening view. Arc and Zen are required targets, with Safari, Chrome, Firefox, Edge and Brave also in the prototype. Automatic inclusion and individual choices are available; native adapters remain to be implemented. See [browser coverage and minimal setup](./BROWSER-SUPPORT.md).

Stable ergonomic window letters and the reserved overflow prefix remain the baseline. Letter order can restore its originating hand preset, the shortcut can return to its suggestion, and each custom color can reset independently. Harmless changes persist immediately; alphabet/policy/pin changes are previewed, explicitly applied and undoable. All six visual modes now have functional previews and a shared settings contract. Fold has separate app/child addresses; Relay has a runtime return pair. Browser tabs are available in every mode. This update implements the requested design changes in the prototype; native integration remains separate.

## Source and verification

Editable source: `index.html`, `styles.css`, `model.js`, `modes.js`, `app.js`. Rebuild the standalone file after editing:

```sh
python3 settings-exploration/package-standalone.py
node settings-exploration/tests/model-checks.js
```

The browser checks are callbacks for an already-installed Playwright CLI, not `@playwright/test` specs. Serve the repository at the URL above and run `playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/browser-checks.js`. The tool must already have a browser session open. See the verification record for the actual installed command used and additional edge checks. No new testing dependency was installed.

Test-only scenarios sit below the simulated settings window. Session fixtures, permission scenarios and accessibility simulation switches do not persist. The functional preferences and last pane use only `tabnax.settings-study.v1` in this browser's localStorage. The study writes no native preferences and contacts no service.
