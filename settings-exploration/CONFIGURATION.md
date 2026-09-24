# Configuration and runtime model

This is a proposed native model plus an explicit mapping to the executable browser study. Do not treat the browser's stored shortcut string or fixture IDs as native configuration types. No app implementation is included.

Structural validation is also captured in [settings.schema.json](./settings.schema.json). Semantic key availability, reserved shortcuts, prefix freedom and capability checks remain mandatory in the native adapter.

## Proposed native settings

```json
{
  "schemaVersion": 1,
  "displayMode": "shore",
  "modePositions": {},
  "activation": {
    "trigger": {"keyCode": "space", "modifiers": ["control", "option"], "side": "either"},
    "behavior": "latch"
  },
  "selection": {
    "handPreset": "right",
    "baseHandPreset": "right",
    "orderedKeys": ["J", "K", "L", "U", "I", "O", "N", "M", "H", "P"],
    "interpretation": "physical",
    "baseLayoutID": "captured-and-verified-at-setup",
    "policy": "stable",
    "maxAddressLength": 4
  },
  "windows": {"includeMinimized": true, "includeHiddenApps": true},
  "position": {"display": "focused", "anchor": "middle-right", "inset": 24},
  "browserTabs": {"enabled": true, "range": "all", "defaultScope": "windows", "selection": "automatic", "selectedBrowsers": ["arc", "zen", "safari", "chrome", "firefox", "edge", "brave"]},
  "appearance": {"source": "system", "labelPalette": "graphite", "labelScale": "standard", "strongOutlines": false, "colorOverrides": {}},
  "startup": {"launchAtLoginRequested": false}
}
```

`orderedKeys` above is human-readable shorthand. Production physical entries should hold validated virtual key tokens and display labels separately, e.g. `{keyToken, displayGlyph, baseLayoutID}`. A glyph is neither a USB scan code nor an AX identity. Do not hardcode this sample's `space` string as a platform key code. Locale, base layout and physical-token migration belong in the validated native input adapter.

Schema constraints: strict version, enum values, 6–20 unique supported key tokens, no command-reserved keys, no untranslatable labels, one validated shortcut, bounded label scales and palette names. `maxAddressLength` is an internal versioned algorithm constant, not a user-facing slider. The last ordered key is the branch for stable/mnemonic policies. Pair policy uses equal-length two-key leaves instead. Apply validates the whole preference and assignment transaction, not separate incompatible fields.

Keep OS-accessibility settings outside this file. They are observed runtime inputs. Never persist `accessibilityGranted: true`, assume a stored launch request means registered, or have restore defaults revoke consent. Placement, browser-tab preferences and color overrides are included following the user’s request. The schema remains a pre-release version 1 proposal; native deployment needs an explicit migration from whichever version actually ships. `browserTabs.enabled` expresses intent, never proof of browser consent or connection. Preserve Windows as the default scope when tabs are disabled. `displayMode` defaults to `shore`. The existing `position` is Shore’s placement; `modePositions` holds optional overrides for the other five modes. Absent overrides resolve to their documented defaults. This keeps older prototype placement intact. The mode selector is limited to the six implemented renderers; unknown browser values fall back to Shore.

## Separate state objects

```text
SettingsDocument
  valid persisted preferences + revision
SettingsDraft
  proposed selection preferences + tentative flat-window/tab/Fold snapshots + validation issues
AddressSession
  generation, namespace, observed catalogue revision
  independent windows/tabs maps; shared alphabet revision
  identity -> complete label
  identity -> visual slot ordinal
  retired labels + optional session pins + next slot ordinal
FoldAddressSession
  app allocator + child allocator per running app generation
  full window address = app prefix + child address; separate from flat labels
FocusHistory
  current + previous distinct live window; update only after confirmed focus
  runtime only; settings Undo must not create a focus event
Catalogue
  ProcessGeneration + WindowToken; title/context/icon/status; capability and liveness confidence
SwitcherSession
  immutable settings revision + address generation + target snapshot
  input state: inactive | direct(prefix) | search(query, highlightedIdentity) | selecting(intent)
ObservedAvailability
  accessibility trust, input transport status, layout translations,
  login-item registration status, per-target focus capability,
  browser adapter connection generations and consent, usable display frames
UIState
  last settings pane, disclosures, preview focus; no permission assertions
```

Window/session state does not live in ordinary preferences. Titles and sample search history are not persisted. Session pins are runtime data; persistent app reservations are a future separate namespace keyed by verified app identity. A native commit validates the candidate trie before publishing it to the input router; renderer references the same immutable generation.

## Transactions and migration

1. Load last known-good config; validate version and all fields before exposing input routes. Preserve a corrupt/unsupported file for recovery rather than overwriting it automatically. Unknown future schema is read-only with a clear incompatibility message.
2. Migrate supported older versions deterministically into a temporary candidate. Preserve user-selected key order. Never treat a migration as permission to silently remap live windows.
3. For harmless changes, validate, atomically persist, then publish the new revision for the next session. For shortcut changes, register/verify the candidate while preserving the previous working trigger, then replace it transactionally. Failed registration reverts UI and leaves the previous configuration intact.
4. For label changes, compute candidates for each affected namespace, validate uniqueness/prefix-freedom/pins, show changed count and examples, and allow sandbox input. Apply cancels stale capture, reconciles catalogue revision, recomputes if necessary, publishes map/config together and persists preferences atomically. If catalogue changed enough to invalidate the preview, keep draft and explain the changed count.
5. Maintain a bounded in-session undo stack for committed preference revisions and valid address snapshots. Native undo never resurrects external windows. Reconcile identities and report partial restoration when needed.
6. Reset-defaults snapshots current state, restores preferences and a fresh address generation, then provides Undo. No native release, deployment or OS configuration change is part of this prototype.

## Browser implementation mapping

`model.js` is dependency-free and exports pure functions both to the browser (`TabnaxModel`) and Node. It contains fixture windows, alphabet validation, leaf generation, stable/mnemonic/pair allocation, retirement and pin validation. `modes.js` owns Fold allocation, mode definitions and all six preview renderers. `app.js` owns UI transactions, sample targets, key capture scoped to the preview, theme controls and local persistence. `styles.css` contains base theme presentation and responsive presentation. `package-standalone.py` embeds these into `tabnax-settings.html` without network resources or a build dependency.

The actual localStorage payload at `tabnax.settings-study.v1` is:

```json
{
  "config": {
    "version": 1,
    "displayMode": "shore",
    "modePositions": {},
    "appearance": "system",
    "theme": "graphite",
    "themeOverrides": {},
    "position": {"display": "focused", "anchor": "middle-right", "inset": 24},
    "browserTabs": {"enabled": true, "range": "all", "defaultScope": "windows", "selection": "automatic", "selectedBrowsers": ["arc", "zen", "safari", "chrome", "firefox", "edge", "brave"]},
    "labelSize": "standard",
    "strongLabels": false,
    "login": false,
    "minimized": true,
    "hidden": true,
    "shortcut": "⌃ ⌥ Space",
    "activation": "latch",
    "modifierSide": "either",
    "keyMode": "physical",
    "selection": {"hand": "right", "baseHand": "right", "alphabet": "JKLUIONMHP", "policy": "stable"}
  },
  "pane": "selection"
}
```

The browser validates alphabet/policy and catches unavailable/malformed storage. It is a local study rather than a hardened migration implementation. Storage can differ between file and localhost origins. A reload recreates synthetic windows and label sessions. Scenario controls deliberately start a fresh dataset and clear sample history; this is not ordinary native window churn. Add/close/rename controls test churn within one session. Tab fixtures force pair labels in a separate namespace while retaining the user’s saved window policy. Product scope controls preserve both maps during switching; only the test dataset picker starts a fresh catalogue. The opening-view preference selects the namespace on reload. Older v1 browser preferences merge defaults for position, browserTabs, themeOverrides, displayMode and modePositions. Relay focus history and Fold allocations are rebuilt runtime state, never persisted in this payload.

`window.TabnaxStudy.inspect()` returns a cloned snapshot for read-only verification, including config, current/draft flat and Fold allocators, focus history, targets, the inactive catalogue, active input state and test harness. It cannot grant permissions or invoke native APIs. Test harness toggles are never written to functional preferences.

## Theme tokens and contrast pairs

| Pair | Light | Dark |
| --- | --- | --- |
| Switcher text / surface | `#22272c` / `#fafafa` | `#f1f3f5` / `#24282e` |
| Secondary text / surface | `#62666c` / `#fafafa` | `#b7bec8` / `#24282e` |
| macOS label (`graphite`) | `#292d33` / `#e5e7e9` | `#fafbfc` / `#424a54` |
| Tabnax key label | `#28361b` / `#d9f68c` | `#28361b` / `#d9f68c` |
| Tabnax text / surface | `#293323` / `#f5f7ef` | `#f6f8ee` / `#202720` |
| Tabnax secondary / surface | `#59634f` / `#f5f7ef` | `#bac3b3` / `#202720` |
| Sage label | `#254a36` / `#dcebdd` | `#1d3b28` / `#c0d9ba` |
| Iris label | `#4d367d` / `#e7e1fa` | `#362258` / `#d0c2ee` |

Native semantic colors replace literal form/chrome colors. Preset badge pairs can remain curated tokens after native contrast verification. The optional outline must remain visible against the actual composited surface. System-contrast handling can strengthen boundaries and secondary text but never weaken the listed text pairs. The HTML sample scales badge text; native accessibility must also scale other essential content.

## Custom theme storage

The native proposal stores custom colors under `appearance.colorOverrides`; the browser uses `config.themeOverrides`. Both use the same shape, with optional presets and appearances:

```json
{"tabnax":{"dark":{"keyBg":"#d9f68c","selection":"#a8d15c"}}}
```

Only six-digit hex values are accepted. Store requested colors and derive readable text, key borders and an adjusted selection color at rendering time. `model.js` owns curated tokens, color resolution and contrast math. Never mutate the preset table when customizing. Reset removes the selected preset’s override entry, preserving all others. Undo restores the prior preferences and address snapshots. Palette/appearance, mode, placement and scope changes do not reassign labels. Changing the shared alphabet commits affected flat-window, tab and Fold snapshots together; a flat policy edit leaves Fold unchanged. See [the full mode/state contract](./SIX-MODE-COVERAGE.md). See [the complete behavior contract](./POSITION-TABS-THEMES.md).

Browser discovery mode and selected browser IDs are preferences; observed installation, approval, running state, extension handshakes and connection generations are runtime state. Missing `selection`/`selectedBrowsers` in earlier v1 browser payloads receive the defaults above. An empty selected list is valid and shows an empty state; unknown IDs are not enabled. The selected subset survives a switch to automatic mode and back. These filters intersect with range and private-tab exclusion without reallocating addresses. [Connection contract and evidence](./BROWSER-SUPPORT.md).

## Scoped restore metadata

`selection.baseHandPreset` in the native proposal and `selection.baseHand` in the study identify the Right/Left/Both preset from which a custom alphabet was edited. The current named preset takes precedence; custom edits preserve the reference. Migrate missing metadata from a named hand or exact preset alphabet, otherwise Right hand, without changing the alphabet itself. Resetting the order remains a draft/apply transaction with pin validation. Shortcut recovery affects only the chord; color recovery removes one current-appearance token override. See [the UX review and complete reset contract](./RESET-RECOVERY.md).
