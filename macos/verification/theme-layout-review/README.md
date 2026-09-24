# Native layouts and themes

Three subagents reviewed the six layouts separately; the changes were integrated into the shipping native app, not the historical browser prototypes.

| Layout | Implemented improvements | Detailed review |
| --- | --- | --- |
| Shore | Tighter panel sizing; room for search, status and enlarged labels. | [Shore and Beacons](shore-beacons.md) |
| Beacons | Browser tabs and apps have truthful bank sections; growing banks no longer cover their own plaques. Plaques share the selected material. | [Shore and Beacons](shore-beacons.md) |
| Canopy | App counts and heading dividers; browser/window context appears in subtitles and accessibility descriptions. | [Canopy and Lattice](canopy-lattice.md) |
| Lattice | Groups explicitly say “Open group”; measured wrapping keeps the address inventory visible; held slots stay disabled. | [Canopy and Lattice](canopy-lattice.md) |
| Fold | Clearer next-letter guidance, containing-app highlight, complete addresses during search and consistent pane separation. Compact app cards stack their icon/key/name without overlaps at enlarged sizes. Its implied-family shortcut behavior is preserved. | [Fold and Relay](fold-relay.md) |
| Relay | Stacked current/previous cards at narrow widths, explicit missing-history states, a counted shelf and accurate unavailable-Return help. | [Fold and Relay](fold-relay.md) |

## Themes

Settings → Appearance offers Graphite, Tabnax, Sage, Iris, Frosted Glass and macOS Glass, with preview cards, a selected checkmark and accessible names. Theme choice saves immediately and restores after relaunch. Light/dark overrides remain isolated per theme; existing preset identifiers and saved choices remain compatible.

Frosted Glass uses `NSVisualEffectView`. macOS Glass uses Apple's public [`NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) on macOS 26+, with its controls inside `contentView`. Earlier macOS uses frosted glass. A single material host is retained per panel, including Beacons plaques. Rows expose the material while keycaps and selected rows retain readable backing.

System appearance is followed unless Light or Dark is selected. Reduce Transparency or Increase Contrast replaces glass with the solid palette. Stronger outlines and enlarged labels remain available. No custom movement or transition animation was added.

## Verification

- Native Debug build passed with Xcode 27 on macOS 26.6.2.
- All 76 core tests passed, including five new persistence, override, contrast and material-fallback tests.
- All 55 native tests passed after the final changes, including compact Fold containment, Fold/Relay keyboard/layout regressions, Beacons target-kind sections and material lifecycle/export regressions.
- The new UI test selected all six themes and confirmed macOS Glass persisted after app relaunch; passed.
- Live native Liquid Glass was visually inspected in the isolated Settings preview.
- Own-view renders cover every layout in light macOS Glass and dark Frosted Glass, plus compact/enlarged Fold, Relay, Canopy and Lattice, Lattice overflow and Canopy/Fold search. See renders (`renders/`; local artifact, not published).

Offscreen PNG exports intentionally use opaque theme palettes. AppKit's `cacheDisplay` omits the live Liquid Glass compositor; the export helper temporarily uses a solid host and then restores the live material. These images verify content, spacing and colors, not desktop refraction. The in-app preview and actual switcher retain native glass.

The macOS 15 fallback and accessibility decision matrix have automated coverage; visual runtime checks here used macOS 26.6.2. No OS accessibility preferences were changed. No commits were created.
