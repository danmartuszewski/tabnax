# Cmd+Tab performance improvements — 19 September 2026

The four primary code improvements from the [audit](README.md) are implemented, along with activation tracing. Three agents handled window discovery, browser refreshes, and router tracing/tests; the parent agent implemented presenter preparation and view reuse, integrated the changes, and verified the result. No commit was created.

## Changes

- **Prepare rows before activation.** Startup and hidden catalogue changes schedule preparation of up to 128 rows after a 40 ms debounce. Work yields between batches targeting 2 ms; an individual AppKit operation can exceed that budget. Preparation does not open a session, order windows, install input monitors, or publish accessibility announcements. Opening and settings changes cancel pending preparation.
- **Reuse the attached view hierarchy.** Reopening retains unchanged rows and headings. Rows skip identical bindings and avoid unnecessary layout invalidation; tracking areas survive geometry changes. Selection, session-bound actions, ordering, appearance, and changed metadata still update.
- **Remove synchronous AX title reads from the main actor.** Title notifications are coalesced on workers. Process/window identity and request-generation checks discard stale replies, including replies after removal, reset, or newer notifications.
- **Reduce competing refresh work.** Ordinary discovery publications are batched; destruction and permission loss remain immediate. Opening skips disabled-browser refreshes, unchanged browser targets avoid catalogue publication, and connection-status changes have a separate callback. Startup owns one initial discovery, prioritizing foreground/recent processes.
- **Trace activation stages.** Session-correlated logs distinguish recognition, state preparation, main-actor delivery, panel ordering, and presentation preparation. The final marker is not proof of a composited frame.

Application changes are in `Tabnax/ModePresenter.swift`, `AppDelegate.swift`, `InputRouter.swift`, `WindowCatalogue.swift`, and `BrowserCatalogue.swift`. Regression tests are registered in `Tabnax.xcodeproj/project.pbxproj`; the existing browser approval test now distinguishes status changes from target changes.

## Measurements

The same optimized presenter harness was run against a source copy saved at the start of implementation and the changed code. Fixtures use Canopy, ten owning apps, A–Z/stable labels, and preloaded icons/menu symbols. Each scenario has two independent processes and twelve open/dismiss cycles per process. Repeated values are each process's median of cycles 3–12. Values below include `present()` plus forced subtree layout.

| Windows | First before | First after preparation | Repeated before | Repeated after preparation |
| --- | ---: | ---: | ---: | ---: |
| 30 | 51.3–52.2 ms | 17.7–17.8 ms | 6.64–6.75 ms | 1.21–1.25 ms |
| 100 | 93.2–94.5 ms | 27.7–28.1 ms | 17.11–17.16 ms | 1.58–1.64 ms |

This is approximately **66–70% less first-presentation work** and **82–91% less repeated-presentation work** in these fixtures. Preparation moves work before activation; it does not eliminate startup work. Its elapsed time, including debounce and yields, was 99–101 ms for 30 windows and 172–174 ms for 100. If activation arrives before preparation completes, ordinary presentation remains the fallback. Without preparation, the changed code's first calls were still 51.6–54.3 ms and 94.0–95.1 ms; repeated calls improved to 1.34–1.47 ms and 1.74–1.77 ms.

These are component measurements with `previewOnly = true`, not physical Cmd+Tab-to-visible-frame results. They exclude event delivery, AX discovery, native panel ordering, and final compositing. The small sample ranges describe observed runs, not confidence intervals. No end-to-end speedup is claimed.

Raw samples (`implementation-results.json`; local artifact, not published) retain all measurements. The original audit's measurements remain separate because other source changes occurred between that audit and implementation. The implementation baseline is at `/private/tmp/tabnax-performance-implementation/before/`; current source hashes are in implementation-source-sha256.json (`implementation-source-sha256.json`; local artifact, not published).

To reproduce against the current source from the repository root:

```sh
bash macos/verification/performance-audit/run-presenter.sh canopy 30 --warm-assets --prepare
bash macos/verification/performance-audit/run-presenter.sh canopy 100 --warm-assets --prepare
```

Omit `--prepare` to measure the fallback cold path. Each invocation compiles actual native/core sources with Swift 6, `-O`, and whole-module optimization into a fresh temporary directory. The prepared harness is [PreparedPresenterBenchmark.swift](PreparedPresenterBenchmark.swift).

## Validation

- **76 core tests passed.** Log: `macos/build/performance-core-tests.log`.
- **72 native tests passed; one Accessibility-dependent fixture test skipped; zero failures.** The new tests cover retained rows and current-session actions, changed titles/unavailability/search, appearance and mode changes, preparation cancellation, title-read coalescing/stale replies, publication batching, and browser refresh/publication suppression. Log: `macos/build/performance-native-tests.log`.
- **Debug fixture/app builds and Release app build passed.** Release log: `macos/build/performance-release-build.log`.
- **All six native layout previews were rendered and visually inspected:** Shore (`renders/shore.png`; local artifact, not published), Beacons (`renders/beacons.png`; local artifact, not published), Canopy (`renders/canopy.png`; local artifact, not published), Lattice (`renders/lattice.png`; local artifact, not published), Fold (`renders/fold.png`; local artifact, not published), and Relay (`renders/relay.png`; local artifact, not published). These are isolated app-owned renders in the dark Graphite theme.

Native result bundle: `macos/build/PerformanceDerivedData/Logs/Test/Test-Tabnax-2026.09.19_21-02-25-+0200.xcresult`. Validation used the isolated `pl.tabnax.performance-tests` bundle identity. No user preference or OS permission was changed, and the user's running app was not replaced. A normal development rebuild/relaunch is needed to use the changes in that app.

## Remaining opportunities

Full viewport virtualization, Beacons plaque-window pooling, tab-heavy address-exhaustion optimization, removal of duplicate browser validation, and a single-instance guard remain separate follow-ups. Preparation is bounded, but ordinary presentation still traverses the complete displayed catalogue. Live activation under discovery/title churn and first composited-frame latency remain unmeasured.
