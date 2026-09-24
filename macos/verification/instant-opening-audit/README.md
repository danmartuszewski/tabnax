# Making widget opening nearly immediate — follow-up audit, 20 September 2026

The strongest next change is **preparing the complete hidden widget, including its material and final layout**, then making activation a small session/selection update and window-ordering operation. The current preparation warms individual rows, leaving substantial first-use work behind. Two other confirmed problems are preparation starvation during frequent updates and synchronous construction of every row beyond the 128-row preparation limit.

This is an investigation with isolated experiments. No shipping application source was changed by this audit, no app was replaced, no preferences or permissions were changed, and no commit was made. Benchmark code, source snapshots, and results are kept here.

## What the running app actually tells us

One Tabnax process was running when inspected: PID 87827, `macos/build/dev/Tabnax.app`. The development runner builds Debug with `-Onone`. Saved preferences selected Canopy, dark Liquid Glass, latched Cmd+Tab, and disabled browser tabs.

Nine existing event-tap activations from that process had matching session-correlated markers:

| Recognition to stage | Median | Observed range |
| --- | ---: | ---: |
| Selection state prepared | 0.48 ms | 0.19–0.88 ms |
| Main actor received state | 0.53 ms | 0.21–0.99 ms |
| Panel ordering returned | 24.29 ms | 7.07–30.83 ms |

The input-to-main-actor handoff was already fast in these samples. Most measured latency came afterward. These are historical samples from one running development build, not a controlled Release benchmark, a tail-latency estimate, or a measurement of pixels becoming visible. The recognized-event marker also excludes time before the event-tap callback. Derived samples (`live-activation-samples.json`; local artifact, not published) contain timestamps and stage timings without window titles.

## Controlled renderer measurements

The harness compiles actual presenter/core sources with `-O` and whole-module optimization. Fixtures have ten owning apps, A–Z stable addresses, cached Notes icons, and either 30, 100, or 300 windows. The material is dark Graphite unless Liquid Glass is specified. The size experiment recorded a final panel of 952 × 652 points, with the fixture's default placement inset. Measurements cover `present()` plus forced subtree layout, with `previewOnly = true`.

Each main scenario runs in two independent processes, with twelve open/dismiss cycles per process. Repeated measurements are each process's median of cycles 3–12. Ranges below are observed samples, not confidence intervals or promised production improvements.

| Scenario | First presentation + layout | Repeated presentation + layout |
| --- | ---: | ---: |
| 30 windows, current row preparation | 21.5–21.8 ms | 1.60–1.66 ms |
| 100 windows, current row preparation | 33.4–33.5 ms | 1.73–1.80 ms |
| 100 windows, row preparation, Liquid Glass | 57.0–57.1 ms | 1.75–1.79 ms |
| 100 windows, complete scene previously assembled | 1.84–1.92 ms | 1.52–1.53 ms |
| 100 windows, complete scene assembled, Liquid Glass | 2.61–2.80 ms | 1.99–2.46 ms |
| 100 windows, recurring updates before opening | 97.1–98.2 ms | 1.68–1.72 ms |
| 300 windows, current row preparation | 144.6–144.7 ms | 2.44–2.46 ms |
| 300 windows, complete scene previously assembled | 2.86–2.88 ms | 2.51–2.59 ms |

“Complete scene previously assembled” is a laboratory approximation: the harness calls the ordinary presenter once while `previewOnly` keeps the panel hidden, forces layout, and dismisses it before measurement. It demonstrates reusable work; it is **not** an implementation of safe production preparation. Ordinary `present()` still has session, monitor, placement, and surface side effects. A production implementation must split these responsibilities.

The baseline source was copied before concurrent UI edits. An intermediate copy caught an unfinished header edit and did not compile; that copy was discarded. The full matrix uses the fixed, successfully compiled baseline. A subsequent compiled snapshot of the newer UI reconfirmed the findings: 33.54 ms prepared Graphite, 56.98 ms prepared Liquid Glass, 2.41 ms previously assembled Liquid Glass, 90.93 ms under update churn, and 146.73 ms for 300 prepared windows. These five checks are one process per scenario, so they establish continued relevance rather than a precise before/after comparison of the UI edits.

Full matrix (`opening-results.json`; local artifact, not published) · Newer-source checks (`current-source-check.json`; local artifact, not published) · Baseline hashes (`source-sha256.json`; local artifact, not published) · Newer-source hashes (`current-source-sha256.json`; local artifact, not published) · Preserved source snapshots (`source-snapshots.zip`; local artifact, not published)

## Recommended improvements

| Priority | Improvement | Effort | Evidence and practical effect |
| --- | --- | --- | --- |
| 1 | Prepare a complete hidden scene and reuse it on opening | L | 100-window Liquid Glass preparation still left about 57 ms; an already assembled scene took about 2–3 ms in the isolated fixture. |
| 2 | Make preparation progress during metadata churn | M | Twelve updates spaced 16 ms apart left **zero rows prepared**, because each restarted the 40 ms debounce. Opening fell back to about 97–98 ms. |
| 3 | Materialize only visible rows, a small buffer, and the selected target | L | At 300 windows, 128 rows were prepared and **172 were constructed during activation**. The attached hierarchy reached 3,386 views. |
| 4 | Add a selection-only presentation path and reduce redraws | M | Retained rows help, but full presentations still rebuild grouping/chrome, touch material/layout, and invalidate both canvases. |
| 5 | Compute the final inset-aware frame once | M | Every opening in the size fixture requested 952 × 616, then 952 × 652. Removing the size change modestly improved repeated work, but barely changed cold work. |
| 6 | Measure first-frame work and add an optimized performance run mode | M | Existing markers stop before a confirmed visible frame; the normal development runner uses Debug. |

### 1. Complete hidden scene preparation

In the newer snapshot, `Tabnax/ModePresenter.swift:427–462` prepares only `TargetRow` objects, initially at width 260. It does not attach the final hierarchy, create Canopy headings, configure the panel's Liquid Glass host, or lay out the actual viewport. `present()` configures the material at line 524 and builds the body afterward; panel ordering is at line 766.

In the instrumented baseline's 100-window Graphite run, body preparation consumed about 20–21 ms after the rows had already been created. Final geometry work consumed another 9–10 ms. Liquid Glass increased the initial theme/geometry work and the final-geometry segment, which reached about 25 ms. These stage timings include AppKit work triggered inside the instrumented sections; they do not isolate shader, compositor, or individual setter costs.

Extract a scene-building path that can prepare the real material, headers, visible rows, scroll geometry, and layout while the panel is hidden. Keep the prepared scene keyed to target structure, relevant presentation metadata, settings, appearance/accessibility preferences, and display geometry/scale. Keep opening-session actions separate: freeze actual placement, bind the current session token, update current/previous selection, materialize and reveal the selected row, publish input surfaces, order the panel, and announce accessibility state.

Cache layout for the likely display, but revalidate the actual display at activation. A changed screen or scale must invalidate the affected layout rather than reuse incorrect geometry. Do not retain a stale clickable identity or change the meanings of addresses during an active session. Keep preparation incremental; moving a large synchronous `present()` call into an idle callback would just move the main-thread stall.

### 2. Progressive preparation instead of restarting on every update

Every call to `prepare()` cancels the previous task before starting a fresh 40 ms sleep. `AppDelegate.publishCatalogue()` calls it after mapping every changed snapshot, and dismissal also schedules it. A steady stream of title updates can continually reset the timer. The synthetic churn scenario reproduced this exactly.

Maintain a pending latest snapshot and a queue of work by stable target identity. Update dirty titles/availability in place while allowing already scheduled structural preparation to make progress. Cancel or replace genuinely incompatible work for mode, structure, theme, or display changes; do not restart the entire job for an unchanged row or a title change elsewhere. Give initial preparation a bounded start deadline, prioritize the visible region and recent selection, and check generation/liveness again before applying a batch.

The 40 ms value is an idle debounce, **not an unconditional delay after Cmd+Tab**. Simply deleting that sleep would not address complete-scene assembly or the unbounded opening fallback.

The old repeated-open harness also omitted the actual app's preparation after each dismissal. A separate scenario that awaited preparation between openings measured 3.07–4.47 ms repeated work, versus 1.73–1.80 ms without it. Preparation currently rebinds rows with `selected: false` and default current-state values, and forced layout can also affect subsequent work. This demonstrates that dismissal preparation belongs in realistic performance tests; it does not attribute the entire difference to a single setter.

### 3. Bound work by the viewport

Increasing the 128-row preparation cap would move more startup work and retain more views without bounding the cold fallback. Canopy still traverses and attaches every child in `ModePresenter.swift`'s `canopy()` function. The 100-window fixture retained 1,186 views; the 300-window fixture retained 3,386.

Keep the complete identity/address/navigation model, but create native views for the viewport plus a small overscan region. Recycle them while scrolling. Compute group geometry from metadata so the scrollbar, headings, and column positions remain stable. Always materialize an offscreen keyboard destination before scrolling to it. Keep mouse-wheel navigation based on model order, since the current implementation derives it from attached buttons. Preserve VoiceOver access to all logical destinations and their actions even when a destination has no attached row yet.

Acceptance should include a 1,000-target fixture, offscreen previous-target selection, search, prefix dimming, scrolling across app groups, disappearing targets, and stale clicks after reopening. Native view count and opening work should follow the viewport, not total catalogue size.

### 4. Selection-only updates and narrower invalidation

An unchanged catalogue can still require a new session or highlight. The current opening path bypasses the unchanged-render guard, and cursor changes run the general renderer. It resets canvas drawing at `ModePresenter.swift:544`, reconstructs Canopy grouping/order, writes headers, and configures the material. `ThemeSurfaceView.configure()` ends by requesting layout even when its effective configuration is unchanged.

Cache structural layout and derived groups. On a selection change, update the old/new highlight and current-window indicator, refresh session-bound handlers, and scroll only if necessary. Skip identical frame/style/header assignments and invalidate only changed regions where AppKit allows it. Do not let geometry-only `Target` changes force unrelated text/style work in Canopy; Beacons still needs geometry changes.

The offscreen drawing control added about 30.5–31.3 ms on first draw and 8.7–9.2 ms on repeated draws of the 100-window Graphite fixture. `cacheDisplay` is an offscreen CPU-rendering path, not the normal compositor, so these numbers are not additive predictions for user-visible latency. They do demonstrate that fast `present()`/layout alone does not establish fast drawing.

### 5. One final frame, with the placement inset already applied

The normal renderer requests its default size before it knows body height, then grows the panel after attaching rows. This repeats on reopening. The isolated experiment precomputed Canopy height before the first frame assignment. Repeated Graphite work decreased from 1.59–1.65 ms to 1.38–1.41 ms; repeated Liquid Glass work decreased from 1.81–1.92 ms to 1.35–1.38 ms. First-opening times barely changed: about 33–34 ms Graphite and 55–56 ms Liquid Glass.

The experiment also exposed inconsistent caps: `Placement.frame()` subtracts the placement inset, but `requiredHeight` uses the full visible-frame height. It can therefore request growth even when the final frame is already capped, producing two identical 952 × 652 assignments in the experimental path. Compute the final inset-aware size and chrome geometry before applying frames; skip assignments when the final frame is unchanged.

This is worthwhile cleanup, but the measurements do not support treating it as the main cold-opening fix. The experiment supports only the unfiltered Canopy fixture and is not production layout code. Raw size experiment (`size-experiment-results.json`; local artifact, not published).

### 6. Verify the visible result, with Release and the selected material

Add correlated markers around scene readiness, final layout, drawing/transaction submission, and actual window ordering. Preserve recognition and main-actor delivery as separate stages. `makeKeyAndOrderFront()` returning, `viewWillDraw`, and a Core Animation completion callback should not be labelled “pixels visible.” Use Instruments to inspect the rendering timeline and a physical or suitably calibrated visual comparison when judging native-switcher parity.

A reasonable proposed engineering budget is **p95 at or below 8 ms for activation-side UI preparation**, with no synchronous catalogue-wide construction. Separately aim for the first useful visible frame within two display refresh intervals and compare against the native switcher on the same display and machine. These are proposed acceptance targets, not measured native performance or a guarantee across macOS configurations. Apple documents that a single missed refresh interval, typically about 8–16 ms, can cause a hitch: [Understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness).

Protect the first-frame window from nonessential catalogue publications and settings-preview work. `AppDelegate.swift:113` currently dispatches refresh to the main queue after `present()`; a queued block is not proof that a frame has been composited. Keep liveness removals, cancellation, and focus safety prompt while coalescing ordinary metadata work.

Add a Release/performance option to the development runner with the existing single-instance and signing behavior, then test first opening, repeated opening with the real dismissal/preparation lifecycle, rapid title churn, large catalogues, browser tabs, mixed display scales, display changes, and Liquid Glass. Report missed/cancelled activations and tail latency, not just successful medians.

## Lower priority for the current configuration

Beacons plaque pooling, browser snapshot coalescing/duplicate validation, address-allocation exhaustion, and a general single-instance guard remain useful follow-ups from the previous audit. They are not the strongest explanation for the measured Canopy path: browser tabs were disabled and only one app instance was running. There is also no fade-in to remove: panels already use `animationBehavior = .none`.

## Reproduction and limitations

From the workspace root:

```sh
benchmark=$(bash macos/verification/instant-opening-audit/build.sh)
"$benchmark" canopy 100 --prepare
"$benchmark" canopy 100 --prepare --glass
"$benchmark" canopy 100 --prime-scene --glass
"$benchmark" canopy 100 --churn
"$benchmark" canopy 300 --prepare
python3 macos/verification/instant-opening-audit/run-matrix.py "$benchmark"
```

`build.sh` copies sources to a fresh temporary directory and instruments only that copy. It accepts an optional preserved snapshot directory containing `ModePresenter.original.swift`, `Support.swift`, `InputRouter.swift`, and `core/`. The archive contains `baseline/` and `newer-ui/` directories. `--single-size` is the experimental sizing path; `--prepare-between` reproduces dismissal preparation; `--draw` exercises app-owned offscreen bitmap drawing. Rerunning the matrix overwrites `opening-results.json`.

The harness never starts an event tap or AX discovery, orders no panel, registers no login item, changes no app defaults, and captures no desktop content. It measures synthetic fixtures and excludes real window ordering, WindowServer composition, physical input delivery, and actual first visible pixels. No claim of native macOS parity follows from these component results.
