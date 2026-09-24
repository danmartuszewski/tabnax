# Browser verification callbacks

These files are the original asynchronous Playwright callbacks accepting a `page` argument. They are not standalone Node test programs.

| File | Original assertions |
| --- | ---: |
| [verify.js](./verify.js) | 92 |
| [verify-additions.js](./verify-additions.js) | 73 |
| [verify-final.js](./verify-final.js) | 22 |

Use the existing Playwright run-code workflow, with the repository root as the working directory and the gallery served at `http://127.0.0.1:4173/design-exploration/index.html`. The final suite also loads the standalone bundle through the same local server.

Screenshots are written to `design-exploration/verification/screenshots/` relative to the workspace root. The assertions and gallery URL were preserved during relocation; only screenshot output paths changed. See the [verification record](../VERIFICATION.md) for original results and scope.
