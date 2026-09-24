# Native settings design parity

The HTML study at `settings-exploration/tabnax-settings.html` is the visual reference. This refinement implements its controls with SwiftUI and AppKit; no web view or screen-capture permission is used.

- **Scope tabs:** full-width inset segments, numeric shortcut hints, clear selected state, and accessible names. Settings shares the component with the real switcher; the real switcher also exposes its existing Running apps scope. Browser tabs reflect the browser-enabled setting.
- **Position:** directional nine-anchor control, readable anchor names, display choice, edge inset, per-mode reset, and immediate desktop preview. Main/External are explicitly illustrated displays, as in the design. The desktop shows the menu bar, working window, Dock, and mode-specific switcher layout. Windows and browser tabs use the same placement preference; Beacons illustrates its separate window plaques and movable bank.
- **Geometry:** the real panel and illustrated preview share `SwitcherGeometry` and `Placement.frame`. The preview projects a four-target example into its desktop, including safe-area clamping and macOS-to-view coordinate conversion. It does not claim to mirror the user's current monitor arrangement.
- **Chrome:** design headings, quiet toolbar selection, section spacing, softer surfaces, and a wallpaper-backed interactive preview. The preview still uses the actual native renderer and cannot switch to another app.
- **Selection:** visible clickable letter keys, overflow-prefix treatment, nearby restore action, reordering, and existing Apply/Discard/Undo behavior.
- **Appearance:** larger keycap theme swatches and visible customization hex values. The existing native color picker, contrast correction, and scoped resets remain functional.
- **Browsers:** installed application icons accompany connection names and observed status. Setup and permission behavior are unchanged.
- **Targets:** more compact native rows, smaller embedded-preview typography, softer unselected borders, and complete selection codes. Enlarged labels retain larger row/tile geometry.

Tests cover preview projection for all six modes, all nine anchors, and all three representative insets (12, 24, 64); native callbacks and preference transactions; and UI flows for scope changes, position changes, mode isolation, persistence, reset, selection editing, and shortcut recording. Completed run identifiers and render results are recorded in `macos/VERIFICATION.md` after verification.
