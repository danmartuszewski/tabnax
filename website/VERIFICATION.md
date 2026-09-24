# Homepage verification — September 20, 2026

The final homepage was tested from `/website/` after the repository organization moved it out of the workspace root. A subsequent sample-content refresh updated the native preview fixtures and regenerated all 18 native screenshots with Tabnax titles. No OS preferences were changed.

## Results

- **215 browser assertions passed**, with **zero JavaScript errors**, using the installed Playwright CLI and Chromium.
- All six layouts passed direct keyboard selection, search, empty search, Enter, Escape, simulated app launch and Option/Alt restoration checks.
- Fold app-prefix and child selection, mouse branching, and Backspace passed. Relay returned between the actual sample window pair, while Enter in search selected the result.
- Hiding and restoring tabs/app targets preserved existing addresses. Unknown letters kept the switcher open and displayed useful feedback.
- All six themes worked in both tones. All six native settings panes loaded their light and dark screenshots. Dialog opening, Escape dismissal and focus restoration passed.
- Viewports of **320, 390, 768, 1024 and 1440 CSS pixels** kept all six layouts inside the demo, with no horizontal page or panel overflow.
- Additional checks passed for direct `file:` operation, loading native screenshot assets, normal Tab/Enter navigation, and keyboard commands remaining scoped to the demo. Reduced-motion styling was exercised.
- JavaScript syntax checking and initial local asset/anchor checks passed.
- Sample content uses Tabnax titles and the reserved `tabnax.example` domain. Source scanning found no previous sample brand in publishable text; local OCR found no previous sample brand in the 55 publishable PNGs across the repository. The homepage versions refreshed demo assets to avoid stale browser copies.

## Visual review and corrections

Reviewed the entire desktop page, all six desktop layouts, and compact layouts. Fixed decorative artwork overflowing at tablet width, darkened the glass surface for readable labels, improved editorial text contrast, and attached Beacons plaques only to the two represented sample windows. Other destinations use its bank.

Generated screenshots live in the ignored repository `output/playwright/` directory. `tests/browser-checks.js` is a reusable browser callback; it reloads the already-open homepage so it does not depend on a particular hosting root.

## Scope

These checks cover the browser homepage and its bounded simulations. Native permission flows, real window focus, global hotkeys, native rendering performance, production signing and extension distribution retain their separate native verification requirements. No Safari or Firefox browser run was performed for the homepage.
