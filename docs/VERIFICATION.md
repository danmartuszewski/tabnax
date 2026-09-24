# Repository preparation verification

Verified locally on September 20, 2026. This record covers repository organization, publication safeguards, website relocation, and the portable signing default.

| Check | Result |
| --- | --- |
| Git initialization | Local `main` branch initialized; no commits, staged files, or remote configured by this task. |
| Final publication policy and links | `make check` passed across 274 public files (12.8 MiB), including the completed promotion kit and its final verification record. |
| Final secret audit | `make audit` passed with Gitleaks 8.30.1 default rules plus workstation-path detection; no leaks found. No commits existed, so there was no Git history to scan. |
| `make build` | Debug app built with shared ad-hoc signing, including its embedded Safari extension. |
| Pure Swift models | 78 tests passed. |
| Native XCTest | 91 executed: 90 passed, one Accessibility-dependent fixture test skipped, zero failures. |
| Python tests | Four publication-tool regressions and six development-runner tests passed. |
| Browser companion | Gecko/Safari background protocol suites and Safari transport tests passed. |
| Settings model checks | 46 model, 20 mode, and 43 theme assertions passed; 1,056 custom palettes checked. |
| Website browser checks | Six layouts, 18 native gallery images, direct letter selection, browser/app toggles, theme/tone, build dialog, and guide navigation passed. |
| Responsive layout | Homepage and guide checked at desktop and narrow phone widths; no document overflow. |
| Website isolation | Requests for Git config, native source, and an environment file returned 404 when serving only `website/`. |
| Public native images | Sample-data contact sheet reviewed; no GPS/artist/description metadata tags found in the website PNGs. |
| Workflow syntax | Workflow, Dependabot, and issue-template YAML parsed successfully. |

The first incremental native run exposed a cached extension with the previous local certificate. Cleaning the generated Debug build folder and rebuilding resolved the mismatch; the successful native run and build above used ad-hoc signing throughout.

`make check` and `make audit` are the final publication gates and should be rerun immediately before staging/sharing, especially while another task is changing files. Gitleaks checks publishable files and all existing history with redacted output. An empty repository has no historical commits to scan. A clean result is evidence against recognized secret patterns, not proof that all sensitive content or vulnerabilities are absent.

No hosted GitHub CI run, native UI suite, production signing/notarization, browser-store publication, public repository creation, or website deployment was performed during repository preparation. Existing native UI evidence is recorded separately in [macos/VERIFICATION.md](../macos/VERIFICATION.md). Raw logs and browser captures from these checks remain in ignored/local output locations.
