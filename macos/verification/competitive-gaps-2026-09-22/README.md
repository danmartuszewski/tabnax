# Competitive-gap implementation coordination

Requested on 22 September 2026. Each item runs in a separate Codex task, sequentially, in the existing checkout. The repository has no commits; all existing source is untracked. No commits or staging are authorized.

The source analysis is the knowledge-base note `tabnax/analyses/macos-switcher-competitive-gaps-2026-09-20.md`. Its historical research remains separate from the implementation status added by this work.

| Sequence | Request | Status | Task |
| --- | --- | --- | --- |
| 1 | #2: window actions inside the switcher | Implemented; reviewed; [verification](item-2-window-actions.md) | `01a0c962-87d6-71b0-96ed-3b28f56d9664` |
| 2 | #3: fuzzy search and useful ranking | Implemented; reviewed; [verification](item-3-fuzzy-search.md) | `01a0c980-c2af-78e2-9fd0-a9c2c824b760` |
| 3 | #5: app/window exclusions and shortcut exceptions | Implemented; reviewed; [verification](item-5-exclusions.md) | `01a0c994-737a-7490-8c6e-181361c3d566` |
| 4 | #6: optional recent-window ordering | Implemented; reviewed; [verification](item-6-traversal-order.md) | `01a0c9a9-62ed-7720-a4c3-ec70dc34659f` |
| 5 | Dedicated filtering shortcut, disabled by default | Implemented; reviewed; [verification](search-shortcut.md) | `01a0c9c0-610d-7783-ac27-ec5739d8eecf` |
| 6 | Simultaneous switcher on every screen | Implemented; reviewed; [verification](simultaneous-displays.md) | `01a0c9d4-204b-7b20-8fc8-e98e1b274ec9` |

## Verification contract

Each implementation must include focused regression coverage, portable checks, core/native tests, relevant isolated UI tests, and a verification record in this directory. The coordinator reviews the result before starting the next task. Final cumulative checks run after the last implementation. Permission-dependent or physical-hardware checks must be reported honestly, including skips.

Known baseline from the separate read-only macOS review: 96 core tests passed; 111 native tests passed with one Accessibility-dependent skip; 12 UI tests passed and two appearance tests failed because they query lazy theme controls before scrolling. The first task also repairs this test navigation so subsequent validation has a reliable baseline.

The coordinator owns updates to the original analysis. Only completed, verified items are marked implemented. Additional requested features receive explicit status entries. Existing unrelated changes and findings remain outside this work.

## Completion and cumulative verification

All six tasks completed sequentially. The coordinator reviewed their source changes, regressions, verification records and relevant render evidence before advancing to each next task. The original knowledge-base analysis now marks items 2, 3, 5 and 6 as implemented and records both additional features as implemented. No code was staged or committed; the existing untracked checkout was preserved.

| Final check | Result |
| --- | --- |
| `make check` | Passed |
| Core tests | 124 passed |
| Native tests | 154 passed; one existing Accessibility-dependent cross-app fixture skipped; zero failures |
| Complete UI suite | 26 passed; zero failures or skips |
| Connected displays | Native and UI validation on three actual displays, across all six layouts, with 1×/2× scaling and negative coordinates |

The full UI rerun includes the repaired Position scrolling test. Product code remained unchanged from the passing native gate. Test logs, result bundles, exact changed paths, measured frames and app-owned renders are linked in the [final verification record](simultaneous-displays.md). The coordinator independently checked the final test logs, the connected-display measurements and a representative render.

The dedicated shortcut is under **General → Open in search**, disabled by default with Control–Shift–Space suggested. Simultaneous presentation is under **Position → Show simultaneously on every display**, also disabled by default.

The skipped cross-app fixture requires an Accessibility-authorized test host. Physical unplug/wake/Spaces transitions, live Secure Input and a live IME candidate/VoiceOver session remain manual integration checks; their isolated routing, native editor and topology behaviors have regression coverage. This is implementation/testing completion, not production deployment or a claim of full release certification.
