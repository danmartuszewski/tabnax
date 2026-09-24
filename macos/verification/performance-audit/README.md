# Cmd+Tab performance audit — 2026-09-19

The primary recommendations have since been implemented. See [implementation changes, measurements, and validation](IMPLEMENTATION.md); the original audit below is preserved as the baseline record.

Three agents reviewed activation/rendering, AX window discovery, and browser/background work. The parent agent profiled the actual AppKit presenter in an isolated harness and inspected the running configuration. This audit did not change application source, stop processes, change preferences/permissions, or create commits. Other work changed the source during the audit; the final renderer measurements were rerun from a fixed source snapshot, and findings were checked against that snapshot.

The strongest measured opportunity is preparing and retaining the Canopy view before activation. First-use row construction costs substantially more than selection or label calculation. Main-thread AX title reads are a separate credible source of intermittent delays, although no live AX stall was measured.

## Current environment and measurement limits

- Saved preferences: Canopy, A–Z alphabet, stable labels, Cmd+Tab, latched opening, click mouse control, browser tabs disabled.
- Two Debug Tabnax processes were running: PID 19132 from the user's Xcode DerivedData and PID 19812 from `macos/build/RunDerivedData`. This is a baseline confounder and a potential shortcut-ownership problem, not proof of the delay's cause. Each process can attempt its own event tap; Cmd+Tab is tap-only. Reproduce with one intended build before drawing end-to-end conclusions. A single-instance guard would prevent recurrence outside the development runner.
- The native Debug target uses `-Onone`; Release uses `-O`. The principal renderer measurements below used freshly compiled actual sources with `-O` and whole-module optimization, so the observed first-use cost is present even in optimized code.
- Toolchain: Apple Swift 6.4, arm64. Final snapshot source hashes are saved in `source-sha256.json`; a temporary copy is at `/private/tmp/tabnax-audit-final/macos`. Source line references below describe that snapshot and may shift as other work continues.
- No physical Cmd+Tab-to-visible-frame baseline was captured. These are synthetic component measurements on this machine, without AX discovery, event delivery, native panel ordering, final compositing, or real application content. Existing logs do not establish the full end-to-end latency.

## Measured renderer cost

The harness constructs `SwitcherPresenter` before timing, uses its real `present()` with `previewOnly = true`, and forces subtree layout after presentation. This excludes presenter initialization, as the application already creates its presenter at startup. Fixtures contain ten owning apps and either 30 or 100 windows, with the saved A–Z/stable configuration. Each process runs twelve open/dismiss cycles. “Repeated” is the median of cycles 3–12; the first repeated cycle is excluded from that median.

| Fixture | First presentation + layout, across separate processes | Repeated presentation + layout |
|---|---:|---:|
| Canopy, 30 windows, icons/menu symbols preloaded | 52.5–60.4 ms (3 processes) | 6.90–7.53 ms |
| Canopy, 100 windows, icons/menu symbols preloaded | 90.0–94.8 ms (2 processes) | 17.77–18.17 ms |

Preloaded runs use cached Notes app artwork for the fixture owners and request common menu symbols before timing. This approximates startup asset warming; it does not reproduce the complete application's startup history. The colder fixture exaggerates work that the real status menu and catalogue may already warm. The warm-assets result is the more relevant baseline. These ranges are observed samples, not confidence intervals or promised improvements.

Before concurrent renderer/theme changes, a separately instrumented temporary copy of the presenter localized a cold-placeholder Canopy/30 run: placement, selection derivation, theme and geometry finished by 0.40 ms; header preparation by 13.61 ms; body construction by 92.96 ms; final presenter work by 98.11 ms. Body construction was the largest segment in that run. The instrumentation was never applied to application source.

Final raw samples: `presenter-final-snapshot-results.json`. Earlier renderer samples are retained in `presenter-results.json`, `presenter-warmed-assets-results.json`, and `presenter-stages.txt`. On that earlier version, cold placeholder first calls ranged from 94.2–130.5 ms for 30 windows, versus 47.8–49.0 ms with assets preloaded. They illustrate the importance of startup cache state; they are not measurements of the final snapshot. The pure-core and lookup measurements were also taken earlier in the audit.

## Prioritized opportunities

### 1. Prepare the first viewport before activation; retain the hierarchy afterward

Evidence: `Tabnax/ModePresenter.swift:370` treats every new session as an opening and bypasses the unchanged-render fast path. Line 518 removes every body subview. Canopy reattaches headings and every child row at lines 769–793. The panel is ordered at line 659, after constructing the complete body. `TargetRow` creates six child views at lines 1100–1114. Its bind always requests layout at line 1199, and tracking areas are removed/recreated at lines 121–127.

The panel, row objects, heading labels and images already have caches. Adding another generic object cache misses the remaining work: first row construction, hierarchy detachment/reattachment, rebinding and layout invalidation.

Recommended change:

- Prepare the current mode's first viewport after startup/catalogue stabilization, in bounded main-actor batches. Keep preparation separate from opening a session, registering input surfaces, announcing accessibility events, or ordering windows.
- Preserve the attached hierarchy while hidden. On reopening, refresh session-bound actions, current selection and changed metadata; rebuild structure only when target order, geometry, mode or relevant styling changes.
- Cache derived row styling and request layout only when text metrics, scale, width or geometry changes.
- For larger catalogues, materialize the viewport plus a buffer and the highlighted target, then recycle rows while scrolling. The current complete Canopy traversal makes cost grow with windows below the viewport too.

Do not call `present()` blindly while idle: it has session, placement, monitor, scrolling and accessibility side effects. Split out preparation explicitly. Freeze placement when the user actually opens the panel. Preserve session guards against stale clicks, stable addresses, hover suppression, search, offscreen keyboard navigation and VoiceOver access. Prewarming itself must not monopolize the main actor.

Expected benefit: reduced first-use CPU work and repeated-open layout work. Exact physical latency savings remain to be measured after implementation.

### 2. Move AX title reads off the main actor

Evidence: `Tabnax/WindowCatalogue.swift:221–227` handles title notifications on the main actor and directly calls `axValue(element, kAXTitleAttribute)`. The `axValue` helper invokes synchronous cross-process `AXUIElementCopyAttributeValue` in `Tabnax/Support.swift:141`. Other desktop discovery is already on bounded workers.

A busy external app can make this call occupy the same thread that must deliver and construct the switcher. This is a verified blocking path, not a measured stall in this audit.

Recommended change: coalesce pending title changes by target, read on the existing worker infrastructure, and apply only if the process token, window identity and request generation still match. Keep the prior title on timeout. Follow the existing asynchronous bounds-update pattern. Check rapid title changes, close/reopen, process relaunch, delayed answers and permission loss.

### 3. Reduce refresh work that competes with the first frame

Evidence:

- `Tabnax/AppDelegate.swift:112–113` presents the cached state and then schedules both refreshes. There is no synchronous wait for a fresh desktop before presentation. A main-queue async dispatch is nevertheless not a display-completion boundary.
- `Tabnax/BrowserCatalogue.swift:143–167` discovers and publishes even with browsers disabled. Lines 169–172 publish for every non-Tabnax app activation, including unchanged active-browser state. This invokes the main-actor mapping pipeline in `AppDelegate.swift:393` even with zero tabs.
- Every process discovery completion calls `publish()` at `WindowCatalogue.swift:325`. That rebuilds targets, registry, address bookkeeping and sorting before its unchanged-snapshot guard at line 471. The guard already avoids unchanged downstream presentations; it does not avoid this earlier work.

Recommended change: skip disabled-browser opening work, publish browser target changes only when records/eligibility/liveness actually change, and separate Settings connection-status updates from target changes. Preserve focus cancellation and process/connection lifetime checks. Batch AX completion publications before rebuilding the full catalogue, while keeping destruction and permission loss prompt. Coalesce rather than waiting for every potentially unresponsive app before publishing useful data.

This is a medium-priority contention reduction. The measured warm seven-browser lookup loop was only 0.269 ms median (0.301 ms p95); the downstream redundant work and scheduling are more relevant than caching Launch Services calls in isolation.

### 4. Remove duplicate startup discovery and prioritize useful cold data

Evidence: `AppDelegate.swift:389` calls `catalogue.start(); catalogue.refresh()`. `WindowCatalogue.start()` already calls `reconcileProcesses(); refresh()` at line 106, and `refresh()` reconciles again at line 122. When the catalogue starts normally, the second refresh marks already-busy processes dirty at line 277, scheduling another discovery after completion at line 327.

Recommended change: make startup own a single initial refresh, while retaining explicit refresh for a retry of an already-running catalogue. Schedule the foreground/recent processes ahead of ascending PID order (`WindowCatalogue.swift:123`). This reduces cold-start background work and improves the chance that the useful cached snapshot exists before the first activation.

An active session intentionally excludes newly discovered identities (`Selection.swift:450` onward). Preserve that guarantee; improve pre-opening cache readiness rather than introducing new label meanings into an active session.

### 5. Measure the actual activation boundary before claiming success

`InputRouter.swift:267` calls `openSession()` before the activation signpost at lines 272–273. `ModePresenter.swift:659` emits `panelCommit` immediately after ordering the panel, before responder, surface, scrolling and accessibility work. Neither marker establishes first composited display.

Add session-correlated markers for recognized Cmd+Tab, state preparation, main-actor delivery, body construction, layout/display submission and presentation completion where observable. Report key-to-main-actor and UI preparation separately from compositor/visible-frame evidence. Compare first opening after launch, repeated openings and opening under title/discovery activity. Use the same fixture/window count, display, mode, appearance and single optimized app instance. Include missed/cancelled activations rather than measuring only successful openings.

## Lower-priority and mode-specific findings

- **Selection work is small in current Canopy.** Real core sources with A–Z/stable, 80 samples after 10 warmups: optimized `update → open` medians were 0.031/0.142/0.602 ms for 20/100/500 windows; Debug medians 0.119/0.506/2.241 ms. Opening repeats navigation derivation, but this is below the measured renderer cost. Do not use `CatalogueSnapshot.revision` alone to skip updates: browser/preferences can change mapped content without advancing the window catalogue revision. See `SelectionBenchmark.swift` and the two selection CSVs.
- **Label mapping is also small with browsers disabled.** Optimized `LabelSession.map`, 100 warm samples: 0.032 ms median for 10 apps/20 windows; 0.114 ms for 25/75; 0.367 ms for 50/150. `LabelMapBenchmark.swift` and `label-map-results.json` contain fixtures and results.
- **Tab-heavy address exhaustion is more costly.** With the default ten-letter alphabet, 300 tabs plus 75 windows mapped in 3.569 ms median; 1,000 tabs plus 150 windows took 12.451 ms. Repeated exhausted mnemonic-book work in `Selection.swift:104–120` is worth addressing if tab-heavy configurations matter. A temporary exhaustion-cache experiment reduced these costs, but it was not applied or fully correctness-tested; retirement/reset/pin behavior requires coverage.
- **Beacons can retain plaque panels.** `ModePresenter.swift:1023` discards all plaque references on dismiss; lines 595–614 create/reassign wrappers and order plaques before the main bank. Pool a bounded number of plaques and update only changed surfaces. This does not explain current Canopy behavior.
- **Browser snapshot work has further opportunities when enabled.** Messages validated off-thread in `BrowserBridge.swift:48` are validated again on the main actor at `BrowserCatalogue.swift:274`; identical snapshots then republish. Duplicate validation alone measured 0.131 ms for 1,000 short-title tabs and 0.500 ms for 4,000, so removing redundant publication matters more. Filter irrelevant companion update events while preserving connection and result ordering.

## Reproduction

The presenter script compiles into a fresh temporary directory and does not launch the application, create an event tap, show a switcher panel, change settings or grant permissions:

```sh
bash macos/verification/performance-audit/run-presenter.sh canopy 30 --warm-assets
bash macos/verification/performance-audit/run-presenter.sh canopy 100 --warm-assets
# Omit --warm-assets for the cold-placeholder control.
```

To reproduce the pure-core fixtures, compile each harness together with `macos/Packages/TabnaxCore/Sources/TabnaxCore/*.swift`, using `swiftc -O -whole-module-optimization -swift-version 6` and a writable temporary `-module-cache-path`. Use `-Onone` for the Debug comparison. Harnesses print their results; none mutate application settings.

The final snapshot already fills built-in browser caches from configuration/permission updates; no additional startup-cache recommendation remains for that path.

The app's existing caches, deferred desktop refresh, bounded AX workers, off-main Apple Events, cached icon images/permission probes and asynchronous browser socket writes are useful existing work. The recommended next implementation should target the remaining measured UI construction and blocking main-thread IPC.
