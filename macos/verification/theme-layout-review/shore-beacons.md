# Shore and Beacons review

Reviewed the native presenter, selection model, placement solver, existing icon-alignment renders, and mode coverage documentation. The current code combines windows, browser tabs, and apps in one target pool; older screenshots and namespace descriptions are historical evidence only.

## Shore

1. **Addressed: excess space in the narrow index.** The previous geometry allowance added 196 points to the row height, while the current presenter uses 159 points for its ordinary header and footer. Shore now uses the actual chrome allowance, adding space explicitly for search and status banners. Filtering retains the full session's row allowance so typing does not resize the panel on every key.
2. **Theme integration requirement: keep the list visually continuous.** The shared row renderer previously drew an opaque surface over every row and the document view drew another opaque surface. A material-backed Shore panel needs transparent unselected rows and document content so the glass remains visible. Keep the selected row's tint and border distinct, with an opaque fallback for Reduce Transparency.
3. **Deferred: make the current-window indicator more discoverable.** The current four-point dot is visually subtle and its meaning is absent from the row's accessibility label. A small textual or symbolic current-window marker, accompanied by the same spoken status, would be easier to interpret. Do not repurpose the selection border for this status.
4. **Deferred: contextual keyboard hints.** The persistent three-line footer is relatively prominent in a narrow layout. A later change could promote the active interaction while preserving access to all commands, especially search and the current Escape behavior.

Preserve direct addresses, original ordering, full-title tooltips, disabled unavailable targets, nonwrapping wheel behavior, and the existing first-click and accessibility press actions. Shore continues to ignore lateral navigation.

## Beacons

1. **Addressed: plaques could overlap an enlarged bank.** The original plan reserved the initial bank frame, then the panel grew after section layout. Plaques intersecting the final bank footprint now move into the bank. Each move contributes to the next height calculation until there is no overlap; at most the existing 24 plaques can be removed. Surviving plaques retain their positions.
2. **Addressed: misleading reasons for tabs and app launchers.** These targets have no individual desktop geometry but previously entered the window-placement classifier. They now appear under separate Browser tabs and Apps headings, using exact snapshot identities. Only windows participate in plaque planning.
3. **Addressed: overconfident bank language.** “Hidden behind another window” conflated hidden or unavailable targets with proven occlusion. The revised heading says “Hidden or unavailable windows”; other headings describe off-screen windows, unavailable positions, and insufficient room for a label.
4. **Theme integration requirement: each plaque needs its own material host.** A clear wrapper around an opaque row cannot express native glass. The parent implementation should provide a real native material behind each plaque, clip it to the plaque radius, and apply the same appearance as the main bank. Labels and key caps need sufficient separation from busy underlying windows.
5. **Deferred: validate bank navigation order against section order.** Pointer-wheel navigation follows rendered controls, while the shared keyboard navigation uses the target list. Bank categories can change visual order relative to that shared list. Altering keyboard semantics is outside this visual pass; verify with representative mixed-window fixtures before changing either order.

Preserve conservative geometry correlation, collision avoidance, display bounds, stable target identity, full direct labels, click identity capture, and bank-only wheel navigation. No geometry should be inferred for browser tabs or app launchers.

## Validation

- `xcrun swiftc -frontend -parse macos/Tabnax/ModePresenter.swift` passed after these edits.
- Source edits are confined to the Shore geometry override and Beacons renderer case.
- Full native build and rendering checks belong to the combined theme implementation after all presenter edits land.
- Representative follow-up checks: one-row and long Shore lists; search, warning banner, and enlarged labels; mixed Beacons windows/tabs/apps; a growing bottom, center, or top anchored bank; dark/light glass over bright and busy backgrounds; Reduce Transparency and Increase Contrast.

No commits were created.
