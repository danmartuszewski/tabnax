# Native settings implementation

Source of truth: `settings-exploration/` contracts and runnable settings design. The original `design-exploration/` gallery remains historical input. No commits or distribution deployment are part of this work.

| Phase | Steps | Done | Status |
| --- | --- | --- | --- |
| 0: prerequisites | 2 | 2 | Complete |
| 1: settings and assignments | 3 | 3 | Complete |
| 2: native presentation and input | 3 | 3 | Complete |
| 3: browser connections | 2 | 2 | Implemented; live approval gate below |
| 4: verification | 4 | 3 | Automated/visual complete; live approval gate |

- [x] **0.1 (S)** Audit native app against design. Dependencies: none. Files: native sources, settings contracts. Acceptance: six existing modes and missing settings identified.
- [x] **0.2 (S)** Establish Swift and native test baseline. Dependencies: 0.1. Files: scripts, verification records. Acceptance: record passes, failures and environmental skips separately.
- [x] **1.1 (M)** Versioned validated settings, migration, scoped restores and Undo. Dependencies: 0.2. Files: core settings, native preferences. Acceptance: invalid/future settings preserved; legacy order retained; independent resets tested.
- [x] **1.2 (L)** Selection transactions, policies, bounded labels and session pins. Dependencies: 1.1. Files: core allocation, catalogue, settings. Acceptance: prefix freedom, retirement, stable filtered identities, Apply/Discard and Undo across namespaces.
- [x] **1.3 (L)** Five native settings panes and interactive shared-renderer preview. Dependencies: 1.1–1.2. Files: SettingsController. Acceptance: every designed control operates, readable validation, keyboard access, responsive layout.
- [x] **2.1 (M)** Themes, accessible scaling and per-mode display placement. Dependencies: 1.1. Files: core themes/position, ModePresenter. Acceptance: all six modes, light/dark presets, custom contrast and clamped placement.
- [x] **2.2 (L)** Recorded activation, latch/hold, side filtering and key interpretation. Dependencies: 1.1. Files: InputRouter, settings. Acceptance: complete key-pair ownership, release cancels hold, unsupported/reserved input rejected.
- [x] **2.3 (L)** Click and wheel preferences with mode-aware navigation. Dependencies: 2.1–2.2. Files: core navigation, InputRouter, ModePresenter. Acceptance: mouse Off retains accessibility; wheel never commits; stale sessions and outside clicks safe.
- [x] **3.1 (L)** Native tab catalogue and independently observed browser connections. Dependencies: 1.2, 2.2. Files: browser adapters, extension, host, settings. Acceptance: Arc/Zen and other listed browsers have honest setup paths, private exclusion and exact identity checks.
- [x] **3.2 (M)** Tabs in all six modes and browser filters. Dependencies: 3.1, 2.1. Files: catalogue, selection, presenter. Acceptance: separate paired labels; scopes and filters preserve labels; no fabricated connections.
- [x] **4.1 (L)** Automated core/native/UI tests after each stage. Dependencies: each stage. Files: tests, scripts. Acceptance: regression suite passes; fixture-only OS tests avoid unrelated user windows.
- [x] **4.2 (M)** Native renders and interaction review for all settings panes and modes. Dependencies: 1–3. Files: verification images and results. Acceptance: no clipping, preview matches actual renderer, controls wired to behavior.
- [x] **4.3 (S)** Final double-check and documentation. Dependencies: 4.1–4.2. Files: README, coverage and verification. Acceptance: distinguish tested behavior from permission/device/browser distribution gates.

- [ ] **4.4 (M)** Live browser and normal-launch permission verification. Dependencies: 3.1, user-owned macOS/browser approvals. Files: verification record. Acceptance: exact-tab switching verified in approved running browsers, Arc/Zen included; record unapproved browsers and signed-distribution requirements separately. OS consent is not fabricated or changed by automated tests.

Included: all current settings-design features and initial mouse-control contract. Deferred: modifier-only activation, persistent app pins, global wheel navigation outside Tabnax, browser history/archive, remote debugging. Out of scope: production signing/notarization, publishing browser-store extensions, changing OS consent without the user’s action.

Decisions: use SwiftUI for native settings forms and AppKit for switcher controls and the existing native mode renderer; the settings preview embeds that renderer. Windows/Tabs use the designed 1/2 keys; existing Running Apps remains available on 3 with visible help. Saved settings contain preferences only, never assertions of permissions or browser connection health. Browser integration may require browser-owned approval/install.

Rollback: preserve existing preferences during migration; versioned settings commit only after validation. Keep bounded runtime Undo for settings and address maps; external windows are never recreated by Undo. Retain old configuration data if unreadable or newer than supported. Revert source changes and rebuild for full code rollback; no production deployment occurs.

Implementation evidence: [README](README.md), [mode coverage](MODE-COVERAGE.md), [native review](verification/SETTINGS-REVIEW.md), [current verification](VERIFICATION.md). The browser source study is unchanged. Native tab pins and namespace-scoped resets follow its assignment contract; the extra Running Apps namespace remains available on key 3.
