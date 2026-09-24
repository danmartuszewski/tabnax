# Interface cleanup — 20 September 2026

The switcher now puts destinations and their letters first. This review covers the shipping native app, its six layouts, all six Settings panes, and the menu bar. Historical browser prototypes were left alone.

## Element decisions

| Surface / element | Decision and reason |
| --- | --- |
| Switcher layout name, total count, layout explanation | Removed. These describe the selected presentation rather than help choose a destination. Layout choice and a short explanation remain in Settings. |
| Persistent address-policy message | Removed from normal operation. Connection problems, missing addresses and other actionable warnings remain visible. |
| Three-line shortcut footer | Replaced with one compact bar: Search, navigation hint, shortcut help and Close. The native help menu lists commands relevant to direct selection or search. |
| Search | Kept native text/IME editing; results update immediately. Search is clickable; Done returns to direct letter selection. |
| Partially typed address | Kept only while typing. Shows the current prefix, “Next letter”, and a clickable back button. |
| Window titles, app artwork, addresses | Kept. These identify the destination. Full titles and context remain in tooltips and accessibility labels. |
| Repeated app subtitles | Removed inside Canopy/Fold groups and from app rows where the app name was already the title. Window state and useful browser/window context remain. Single-line rows are vertically centered. |
| Selected/current indicators and unavailable states | Kept. They explain what selection will do and which destinations can be used. Concurrent window-restore work adds minimized badges separately. |
| Section counts | Kept beside app/category groups where they help scan the available destinations. Removed the redundant global count. |
| Empty results and no-window states | Kept, with plain language and a Refresh action when there are no destinations. |
| Settings slogans and introductory paragraphs | Removed decorative slogans; pane titles and short purpose guidance explain the controls below them. |
| Settings layout catalogue | Replaced six simultaneous explanations with one description of the selected layout. All six choices remain. |
| Settings keyboard instructions and recovery steps | Short primary instructions; longer behavior details and troubleshooting use native disclosure controls. |
| Letters/Apps draft messages | Consolidated into the persistent Apply/Discard bar, shown only for pending changes or errors. The bar remains accessible across panes. |
| Appearance | Removed repeated material implementation notes and always-visible hex values. Theme swatches, native color controls, contrast warnings, resets and legibility controls remain. Theme details remain on hover. |
| Position | Kept controls, placement illustration, actual values and concise per-layout guidance. Removed repeated layout prose; the concurrent Settings task further clarified the example displays. |
| Browser connections | Kept each browser’s observed status and setup action; removed the badge repeating that same approval status. Private-tab exclusion remains explained. |
| Settings preview | Removed layout prose, duplicate saved/draft labels and orange “Preview” warning inside the renderer. Kept sample identification, interaction controls and one explanation that preview actions stay in Settings. |
| Menu bar | Removed the duplicated layout name and “Ready to switch” success card. Shortcut and actionable health warnings remain. Refresh/Restart moved into Troubleshooting. |
| First run, permissions, destructive resets, read-only errors | Kept. These affect whether the app works or whether changes are saved. |

## Layout improvements

| Layout | Changes |
| --- | --- |
| Shore | Removed header prose and reduced panel chrome. More room for titles; app rows no longer repeat their name below themselves. |
| Beacons | Replaced four geometry-failure categories with one Windows group; Browser tabs and Apps remain distinct. Plaque collision handling stays in the placement model. |
| Canopy | Removed repeated app subtitles. Initial panel height fits its columns rather than leaving a large empty region. App grouping, artwork, counts and full addresses remain. |
| Lattice | Overflow cards show a bounded summary instead of expanding into a complete inventory. Full inventory is available through hover/VoiceOver. Keyboard navigation scrolls overflow groups into view. |
| Fold | Shorter app/child headings, simpler initial instruction, no repeated app subtitles, and keyboard scrolling follows app-group highlights. Family counts are computed once per presentation. |
| Relay | Search shows the matching destination cards directly, without empty current/previous placeholders. Direct mode retains the current/previous pair and its distinct Return behavior. |

Initial panels fit their contents. Once open, they retain the space already used while filtering or changing Fold families, so controls do not move under the pointer. Panels remain bounded by the display; larger content scrolls through AppKit.

## Native macOS choices

The implementation retains AppKit panels, `NSScrollView`, `NSSearchField`, native menus, SF Symbols and cached/reused rows. Search uses `sendsSearchStringImmediately`. Branch selection uses [`NSView.scrollToVisible`](https://developer.apple.com/documentation/appkit/nsview/scrolltovisible(_:)). Settings keeps SwiftUI controls and native disclosure groups.

The existing material host uses public [`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) on macOS 26+, with `NSVisualEffectView` on earlier supported systems and solid surfaces for accessibility preferences. A new framework or cosmetic animation would not itself establish a performance improvement. Apple's [performance guidance](https://developer.apple.com/videos/play/wwdc2025/306/) recommends profiling and reducing unnecessary updates; the retained renderer and optimized benchmark support that approach.

No new dependency, screen capture, polling loop or transition animation was added. Row preparation also applies the grouped-row presentation before activation, avoiding an unnecessary first-presentation rebind.

## Verification

- Optimized Release app build passed on macOS 26.6.2 with Xcode 27. Log: `macos/build/ui-cleanup-release-build.log`.
- Core: **78 tests passed**. Log: `macos/build/ui-cleanup-core-tests.log`.
- Native: **78 passed, one Accessibility-dependent fixture test skipped, zero failures**. Includes search/back routing, branch scrolling, retained row behavior, six-layout rendering and the integrated restore/badge checks. Log: `macos/build/ui-cleanup-native-tests.log`.
- UI: **seven selected scenarios passed**: direct overflow; Escape; mouse Search → Done → prefix Back → Close; six browser-tab layout previews; theme persistence; draft navigation/apply/discard/persistence; per-layout placement/reset. Two Settings scenarios passed on an isolated retry after the initial run encountered a desktop app crash/focus interference. Logs: `macos/build/ui-cleanup-ui-tests.log` and `macos/build/ui-cleanup-ui-retry.log`.
- Reviewed own-view exports for every layout, search in each layout, enlarged labels in compact Canopy/Lattice/Fold/Relay, Lattice prefix navigation and all six Settings panes. Screenshots in renders (`renders/`; local artifact, not published) use isolated sample preferences. Glass exports use the existing opaque fallback and verify content/layout rather than live desktop refraction.

The UI test results describe the cleanup test build. The concurrently active **Review and improve Go settings** task subsequently changed Settings; its final Settings verification belongs to that task. The latest screenshots preserve those refinements. Restore work is tracked in **Fix option-key window restore**.

### Renderer measurement

An optimized, prepared Canopy renderer with 100 synthetic windows and ten apps measured **24.95 ms** for first presentation plus forced layout, and **1.45 ms median** for repeated presentations (cycles 3–12; observed range **1.41–3.35 ms**). This is one process with twelve cycles; preparation happened before opening. These are component measurements, excluding event delivery, AX discovery, WindowServer ordering and final compositing. They do not establish total shortcut-to-visible-frame latency or a universal speedup. Raw samples (`performance.json`; local artifact, not published).

The remaining broad performance work—viewport virtualization for very large catalogues and end-to-end first-frame profiling—is outside this interface cleanup. No framework migration was needed to remove the identified UI work.

Concurrent Option-key restore, minimized-indicator and Settings refinements were preserved. No commits were created.
