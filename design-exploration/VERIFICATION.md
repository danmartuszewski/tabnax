# Browser verification

Verified on 17 September 2026 with Chromium through the Playwright CLI. These are interaction and layout checks, not a native performance benchmark or a user usability study.

**187 browser assertions passed** across the three suites below. The original suite was also rerun after integration. No JavaScript page errors occurred in either full interaction suite.

| Suite | Passed | Coverage |
| --- | ---: | --- |
| [Original regressions](./tests/verify.js) | 92 | Shore, Beacons, Canopy; direct selection; same-app windows; search/selection separation; cancellation; hold behavior; apps scope; minimized windows; immediate selection; 6/8/10 windows; retired addresses; overflow sequences; 28 tabs; hand presets; custom alphabets; reduced motion; layout bounds. |
| [Additional directions](./tests/verify-additions.js) | 73 | Lattice fixed cells and progressive tabs; Fold's two-stage addresses and singleton behavior; Relay history and Enter semantics; shifted command keys while held; native button activation; repeated window stacking; all six concepts retained. |
| [Final checks](./tests/verify-final.js) | 22 | Search cursor and input focus under target churn in all six modes; direct local-file loading of the standalone gallery; no external scripts/styles; standalone window and progressive tab selection. |

Surface bounds and document overflow were checked at viewport widths **1440, 1024, 768, 390, and 320 pixels**. All six modes were visually inspected through screenshots, including compact fallbacks. Scrollable tab inventories and compact grids are intentional; desktop-size use is the appropriate comparison for this macOS interaction.

## Visual evidence

- Final six-concept gallery (`./verification/screenshots/gallery-six-final.png`; local artifact, not published)
- Shore (`./verification/screenshots/shore.png`; local artifact, not published), Beacons (`./verification/screenshots/beacons.png`; local artifact, not published), Canopy (`./verification/screenshots/canopy.png`; local artifact, not published)
- Lattice (`./verification/screenshots/lattice-final.png`; local artifact, not published), tab overview (`./verification/screenshots/lattice-tabs.png`; local artifact, not published), narrowed tab grid (`./verification/screenshots/lattice-narrowed.png`; local artifact, not published)
- Fold app choices (`./verification/screenshots/fold.png`; local artifact, not published), unfolded Safari windows (`./verification/screenshots/fold-branch.png`; local artifact, not published)
- Relay (`./verification/screenshots/relay.png`; local artifact, not published), Relay with ten windows (`./verification/screenshots/relay-ten.png`; local artifact, not published)
- Compact Lattice (`./verification/screenshots/lattice-compact.png`; local artifact, not published), compact Fold (`./verification/screenshots/fold-compact.png`; local artifact, not published), compact Relay (`./verification/screenshots/relay-compact.png`; local artifact, not published)

## Corrections made during review

- Reserved address branches prevent target letters becoming ambiguous prefixes under growth.
- Shifted slash and scope digits work while the browser's held-Shift activation is active.
- Search selections clamp after target churn, and search retains keyboard focus after lab mutations.
- Simulated window z-indices cannot escape the desktop's stacking context and cover the switcher.
- Enter and Space on a browser-focused target button preserve ordinary button activation.
- Relay reserves a bounded pair area above its shelf, including when ten windows are open.
- Product surfaces were made opaque where background text reduced legibility.

## Running the artifact

Open [tabnax-gallery.html](./tabnax-gallery.html) directly in a desktop browser. All styles, icons, data, and interaction code are embedded. The companion rationale documents are linked files in this folder. No server or installation is needed for the demo itself.

The editable source is [index.html](./index.html) with its adjacent CSS and JavaScript. Regenerate the standalone artifact with `python3 design-exploration/package-standalone.py` after edits.

These checks establish simulated behavior only. Native latency, memory, energy, window enumeration, title extraction, permissions, Spaces, multi-monitor placement, and real tab support remain untested and outside this design phase.

## Workspace organization

On 17 September 2026, browser verification callbacks were moved into `tests/`, screenshots into `verification/screenshots/`, and the original browser session logs into `verification/session-logs/`. Screenshot output paths and links were updated. This relocation did not change the gallery interaction code or rerun the original browser assertions.
