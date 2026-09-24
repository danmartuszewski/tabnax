# Verification record

Verified on 17 September 2026 using the already-installed Chromium/Playwright CLI and Node. The scoped-restore update passed **490 assertions in the suites run for this change:** 381 browser assertions plus 109 pure-model/contrast assertions. The table contains **552 recorded passing assertions** including 62 earlier edge/status/browser-choice assertions retained from the preceding update. No JavaScript page errors in the completed browser suites. These are simulation checks, not native performance or usability results.

| Suite | Assertions | Evidence |
| --- | ---: | --- |
| [Scoped restore callback](./tests/reset-checks.js) | 71 | Reference Right/Left/Both presets, custom/invalid order recovery, I/O restoration, Apply/Discard/Undo, all six modes, compatible/incompatible pins, persistence/migration, shortcut-only recovery, single-color reset isolation and responsive layout |
| [Browser interaction/layout callback](./tests/browser-checks.js) | 91 | Direct/sequence selection, explicit search, invalid alphabet, preset/reorder/exclusion, mnemonic/pair drafts, apply/discard/undo, pins/collisions/reset, rename/close/add, fixed cells, inclusion, hold surrogate, shortcut recorder, permission wording, themes, persistence, reset, responsive bounds, zoom and standalone packaging |
| [Final edge callback](./tests/edge-checks.js) | 23 | Invalid draft after valid preview, repeat/composition rejection, physical versus character events, left/right Shift release, tab prefix narrowing, invalid-prefix recovery, ten-window visibility, hidden-app inclusion, login simulation, denied/revoked states, address exhaustion and search fallback, expanded compact layout |
| [Draft status checks](./tests/status-checks.js) | 3 | Unsaved label status, persistence across pane navigation and status after discarding |
| [Browser choices callback](./tests/browser-choices-checks.js) | 36 | Automatic/selected modes, Arc/Zen pair selection and search, seven browsers/48 tabs, filter intersection, empty states, label preservation, Undo, persistence, guided setup copy, migration and compact layout |
| [Expanded settings callback](./tests/expanded-settings-checks.js) | 87 | Four themes × light/dark, per-preset overrides, automatic readability, reset/Undo, persistence/migration, all nine anchors, display/spacing, tab scope commands, filters, retirement, shared alphabet transactions, disable/Undo, five-pane responsive layout |
| [Six display modes](./tests/display-modes-checks.js) | 132 | Every mode: exact selection, global search, Arc/Zen tabs and held scope changes; Canopy grouping; Beacons bank; Lattice held cells/prefix grids; Fold stages/pins/churn/shared alphabet transactions; Relay success/failure/closure history; per-mode position/reset/Undo/persistence; old preferences; enlarged labels at 1280/390/320 px |
| [Pure Fold allocator](./tests/mode-model-checks.js) | 20 | Uniqueness and prefix freedom, app/child overflow, singleton stages, child retirement and pins, compatible/incompatible alphabet migration, app-prefix retention and non-mutating candidates |
| [Theme contrast checks](./tests/theme-checks.js) | 43 | All eight curated palettes, 1,056 custom color combinations with independent contrast math, invalid override fallback, immutable presets and original-green tokens |
| [Pure allocator and contrast](./tests/model-checks.js) | 46 | Uniqueness and prefix-freedom for three alphabets × three policies, validation, stable overflow, retirement, pin collision/prefix/reuse checks, bounded capacity, pair/mnemonic examples and ten contrast pairs |

## Visual inspection

The finished panes were captured and visually inspected, along with invalid-input, grid/churn, tab-prefix, compact and dark variants. The window remains compact by default; advanced controls and fixtures expand only on demand.

- Letter-order restore beside its field (`./output/playwright/resets-selection.png`; local artifact, not published)
- Individual color resets, compact (`./output/playwright/resets-colors-compact.png`; local artifact, not published)
- Shore (`./output/playwright/mode-shore.png`; local artifact, not published) · Beacons (`./output/playwright/mode-beacons.png`; local artifact, not published) · Canopy (`./output/playwright/mode-canopy.png`; local artifact, not published)
- Lattice (`./output/playwright/mode-lattice.png`; local artifact, not published) · Fold (`./output/playwright/mode-fold.png`; local artifact, not published) · Relay (`./output/playwright/mode-relay.png`; local artifact, not published)
- Fold with enlarged labels at 390 px (`./output/playwright/mode-fold-compact.png`; local artifact, not published)
- macOS theme with customization (`./output/playwright/themes-macos.png`; local artifact, not published)
- Original green Tabnax theme (`./output/playwright/themes-tabnax.png`; local artifact, not published)
- Custom amber keys and blue selection (`./output/playwright/themes-custom.png`; local artifact, not published)
- Position controls (`./output/playwright/position.png`; local artifact, not published)
- Arc and Zen selected (`./output/playwright/browser-arc-zen.png`; local artifact, not published)
- All browser choices, compact (`./output/playwright/browser-choices-compact.png`; local artifact, not published)
- Browser Tabs settings (`./output/playwright/browser-tabs.png`; local artifact, not published)
- Expanded themes at 320 px (`./output/playwright/themes-compact.png`; local artifact, not published)
- Selection, final (`./output/playwright/selection-final.png`; local artifact, not published)
- General, final (`./output/playwright/general-final.png`; local artifact, not published)
- Appearance, dark Sage (`./output/playwright/appearance-final.png`; local artifact, not published)
- Dark Iris (`./output/playwright/appearance-dark-iris.png`; local artifact, not published)
- Extra large labels and increased contrast (`./output/playwright/appearance-dark-sage.png`; local artifact, not published)
- Invalid alphabet (`./output/playwright/invalid-alphabet.png`; local artifact, not published)
- Fixed cells after window churn (`./output/playwright/grid-churn.png`; local artifact, not published)
- Tab prefix narrowed to matching targets (`./output/playwright/tabs-prefix.png`; local artifact, not published)
- Compact 320 px (`./output/playwright/compact-320.png`; local artifact, not published)
- 200% CSS zoom (`./output/playwright/zoom-200.png`; local artifact, not published)

The original three panes were checked for horizontal overflow at viewport widths 1440, 1024, 768, 620, 390 and 320 CSS pixels against the document client width, including scrollbar space. All five updated panes were checked at 1280, 620, 390 and 320 px, with theme customization expanded. Expanded advanced settings were checked at 320 px. Normal ten-window Shore content fits its preview without scrolling. The six-mode previews were checked at 1280, 390 and 320 px with Extra large labels. Grouped, spatial and grid presentations use the bounded scroller when their structure needs more room. Larger fixtures/large badges can use the bounded preview scroller. CSS zoom is a reflow check, not a substitute for native macOS text-size accessibility testing.

The original ten foreground/background contrast pairs range from **5.53:1 to 14.43:1**. All eight current presets passed text contrast ≥4.5:1 and selection contrast ≥3:1. Across 1,056 custom combinations, the lowest computed key-text contrast was 4.58:1 and selection/surface contrast was 3.00:1. This is token-level WCAG relative-luminance math, not a blanket accessibility certification. Native control sizes, semantic colors, focus bounds, VoiceOver announcements and OS settings still need platform verification. Dimming nonmatching addresses is supplementary; complete labels remain available in the unfiltered view. Tab prefix mode presents matching targets at full contrast.

## Corrections made

The scoped-restore UX review added recovery for the original hand preset, the suggested shortcut and one theme color at a time. Custom orders now retain a reference hand across edits/reloads. Reset tests verify that pins and unrelated preferences survive; incompatible pins block Apply. [Review decisions and contract](./RESET-RECOVERY.md).

The visual pass also corrected Fold’s app-prefix badges to honor label size and strong outlines, with matching treatment for Lattice prefix badges. A screenshot capture initially targeted a nonexistent Stop selector after all images were saved; the capture script was corrected.

The six-mode update fixed cancellation after a scope change while holding Shift, and kept Fold’s draft alphabet in sync when an alphabet edit is reverted before Apply. An initial missing test-only failure checkbox caused a startup error; it was added before the successful suites.

Update checks also verified that changing the window policy preserves the tab session, pending label drafts block scope changes, theme/pane button state does not attach to the document body, and old browser preferences receive new defaults. Initial callback attempts exposed overly broad button selectors and a test trying to apply a draft from another pane; those selectors/navigation steps were corrected before the successful runs.


- Container queries now stack the form and preview at enlarged zoom; the layout test also checks their bounds instead of relying only on document overflow.
- Unsaved label drafts now have an explicit footer status as well as the preview banner.
- A successful shortcut recording now clears the earlier validation error.
- A previously valid draft followed by invalid text explicitly displays “Last valid labels.”
- Dark test-harness select controls use readable foreground colors.
- Ten standard-size windows fit in the preview; overflow remains scrollable for larger collections.
- Tab prefixes now narrow the compact preview immediately instead of leaving matching rows below unrelated rows.
- Held Shift cancellation checks the configured side; releasing the opposite Shift does not cancel the session.
- Address exhaustion has a visible explanation and searchable/clickable unlabelled targets.
- Test synchronization waits for dialog-close mutations before asserting reset state; the initial test attempt read that state too early.

## Reproduction and scope

The repository was served locally with:

```sh
python3 -m http.server 4174 --bind 127.0.0.1 --directory .
```

Actual installed CLI used:

```sh
playwright-cli --session tabnax-settings open http://127.0.0.1:4174/settings-exploration/index.html --headed
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/browser-checks.js
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/edge-checks.js
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/expanded-settings-checks.js
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/status-checks.js
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/browser-choices-checks.js
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/display-modes-checks.js
playwright-cli --session tabnax-settings run-code --filename settings-exploration/tests/reset-checks.js
node settings-exploration/tests/mode-model-checks.js
node settings-exploration/tests/model-checks.js
node settings-exploration/tests/theme-checks.js
```

For the scoped-restore update, the new 71-check callback, main browser suite (91), expanded settings suite (87), six-mode suite (132), and all three pure suites (109) passed. Edge (23), status (3) and browser-choice (36) records remain from the preceding update; they were not rerun for this change. JavaScript syntax and local Markdown links were checked, and the native settings schema parsed successfully with the new mode and position definitions. The added browser controls and expanded list were visually inspected at desktop and 320 px widths. The standalone HTML was verified over localhost and checked for embedded styles/scripts. Direct `file:` navigation is blocked by this browser tool's policy, so no claim is made that its automated file-URL flow ran. The artifact contains no external runtime dependencies and can be opened directly in a normal desktop browser; localStorage support may vary by origin/browser.

The first page load requested a missing favicon; the source now uses a data favicon. No new dependency was installed. The automation used temporary browser/cache infrastructure and a localhost server, with no OS permission changes, native app build, deployment or commit.

Not verified: native global shortcut registration, secure-input detection, real permission state, real window/tab identity, cross-Space/full-screen focus, third-party app compatibility, exact native input latency, hardware layouts/remappers, native assistive technology, memory or energy. The specification treats these as contracts/gates, not established behavior. The six existing gallery concepts and architecture research were read-only inputs. Beacons uses synthetic geometry; the previews do not validate native plaque collisions or occlusion. Relay observes simulated selections, not native focus events. Fold process-generation retirement requires a native lifecycle feed. See [the complete coverage and native gates](./SIX-MODE-COVERAGE.md).

Browser adapter evidence is documented separately in [Browser support](./BROWSER-SUPPORT.md). Installed application dictionaries were read without sending Apple events, reading tabs, requesting permissions or installing extensions. This evidence supports proposed adapter choices but does not add native integration claims to the browser tests.
