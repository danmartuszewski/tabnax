# App icon alignment review

The user-provided design crop is the reference for icon alignment with the title/subtitle block. The native renderer uses each label's measured height and a two-point gap, centers the resulting block with its icon, and accounts for transparent padding in macOS application artwork. Tiles place the same text block below a centered icon/key row. Canopy headings use the same icon and text columns as their children.

The 26 PNGs here are app-owned renders of isolated samples, not display captures. They cover the six native switchers, Windows and Browser tabs in all six Settings variants, enlarged labels in compact windows, and the Fold and Lattice child views. `settings-shore-windows.png` is the closest comparison to the supplied crop. `settings-shore-tabs.png` also verifies Arc and Zen artwork. Position's schematic symbols and browser connection rows already use centered SwiftUI stacks and needed no change.

All three focused UI checks passed: `testSixModeBrowserTabPreviews`, `testMouseOffAndWheelNeverCommitPreview`, and `testPreviewTargetsAndImmediateOverflow`. Their console results are preserved in `ui-results.log`. A final three-point horizontal correction to the non-embedded Canopy header was built and visually verified afterward; it does not alter input behavior. Debug/Release builds and the local Release signature check passed. `release-sha256.txt` identifies the rebuilt executable.

Settings render commands now also accept `--prefix j`, allowing Fold and Lattice child layouts to be checked without changing real preferences.
