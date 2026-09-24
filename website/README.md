# Tabnax homepage

The current product homepage lives at `website/index.html`. Open this directory's `index.html` directly in a browser or serve only the website directory from the repository root:

```sh
make website
```

Then open [localhost:4173](http://127.0.0.1:4173/). No install, package manager, framework, build step, external font, CDN, analytics, or runtime network service is required.

## Editing

| File | Purpose |
| --- | --- |
| `index.html` | Homepage sections, copy, semantic structure, dialogs and metadata. |
| `guide.html` | Public-facing local build, first-run, browser connection and customization guide. |
| `guide.css` | Build-guide typography and responsive layout. |
| `styles.css` | Design tokens, desktop artwork, shared switcher styling, six layouts and responsive rules. |
| `app.js` | Sample destinations, demo input and selection, themes, native gallery and dialogs. |
| `assets/tabnax-icon.png` | Copy of the native app icon. |
| `assets/native/` | Curated copies of the latest native view exports. |

`MODE_INFO`, `TARGETS`, `APPS` and `PANE_INFO` at the top of `app.js` hold the editable demo content. Addresses are explicit and deterministic; filtering never reallocates them. Flat and grouped layouts use separate addresses, as in the native app. Keep labels prefix-free within each layout.

The layout controls and demo state are deliberately independent of the historical design and settings explorations. All state is in memory; reloading restores the sample workspace. Keyboard commands are handled only while focus is inside the demo. Tab remains normal browser focus navigation.

## What the playground demonstrates

- Shore's compact list, Beacons' visible-window plaques and fallback bank, Canopy's app columns, Lattice's address grid, Fold's app/child selection, and Relay's observed sample window pair.
- Click or letter selection, grouped multi-letter addresses, arrow-key highlighting, Enter, slash search, Escape and Backspace.
- Search by app, title and browser context, including empty results and ordinary Enter selection in Relay search.
- Stable sample addresses when browser tabs or app targets are hidden and restored.
- Fixed app letters, simulated Figma launching, and minimized-window restoration through Option/Alt or an accessible button.
- Six themes and light/dark appearances; native images for all six layouts; all six settings panes in light and dark.

This is a bounded browser simulation, not the native renderer. It does not discover or focus real windows, launch applications, quit applications, request permissions, reproduce global modifier capture, allocate new targets/overflow, or persist native settings. On phones Beacons plaques stack. Glass is a CSS approximation. These boundaries are explained in the page's FAQ.

## Native image provenance

App-owned views refreshed September 20, 2026 with Tabnax-only sample titles (Keyboard guide and Layout preview). Render staging is under ignored `output/brand-refresh/native/`:

- `assets/native/{pane}-{light,dark}.png` is regenerated from the app’s `--render-settings` command, covering General, Letters, Apps, Position, Appearance and Browser tabs. Dark captures use `--compact`; Apps uses `--preview-launcher`.
- `assets/native/mode-{mode}.png` is regenerated with `--render-preview --mode {mode} --theme graphite --appearance light`, including minimized-window indicators.
- The app icon comes from `macos/Tabnax/Assets.xcassets/AppIcon.appiconset/icon_128x128.png`.

When refreshing captures, copy reviewed app-owned renders into these filenames, update the capture date/copy in `index.html` and `app.js`, and check both light and dark views. Keep the distinction between the actual native captures and the interactive browser simulation.

## Local distribution

Keep the `website` directory together: HTML, CSS, JavaScript and `assets` use relative paths. The build dialog describes the current local development workflow; do not substitute a download CTA until a signed public release exists. Repository organization and its public build guide are maintained alongside the homepage.

No hosting service or production deployment is configured by this change.

## Browser checks

The callback in `tests/browser-checks.js` runs with an existing Playwright CLI installation, without adding a test dependency. Start the server above, open the homepage in a named CLI session, then run:

```sh
playwright-cli --session tabnax-home open http://127.0.0.1:4173/
playwright-cli --session tabnax-home run-code --filename website/tests/browser-checks.js
```

Run from the repository root so generated screenshots go to the ignored `output/playwright/` directory. The file is a CLI callback expression; keep its final closing brace free of a trailing semicolon. See [verification](VERIFICATION.md) for results and scope.
