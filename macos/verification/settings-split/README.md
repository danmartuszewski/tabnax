# Letters and Apps settings split

The former Selection pane is now two adjacent tabs:

- **Letters:** hand preset, alphabet/order, assignment policy, key interpretation, and expandable advanced session pins/reset.
- **Apps:** fixed application letters, assignment list, and a separate Launching section.

**Open Tabnax in** is now in General, with one control for the default opening scope. General also separates Windows from Startup. Browser tabs contains browser-specific inclusion, range and connections. The toolbar retains the established native styling, with six tabs fitting the existing minimum window width.

Letters and Apps share one label transaction because their alphabets and reserved keys interact. Changing tabs preserves the draft. Apply/Discard is visible on either label pane and on all other panes while a draft is pending. App navigation previews Apps; returning to Letters previews windows or the pending tab reset. A staged reset captures its original namespace, so later app edits cannot accidentally reset a different label set.

**Validation:** eight own-view renders were reviewed: every pane in light appearance, plus Letters and Apps at compact size in dark appearance. Three UI flows passed: cross-pane editing/Apply/Discard/relaunch persistence and the moved default-scope control; the app-picker/assignment/launch-switch flow; and browser-tab previews in all six display modes. All 26 native tests passed, with one existing Accessibility-dependent fixture skipped. An initial launcher-fixture race was corrected by waiting for the fixture to finish launching before testing activation; the full native suite then passed.

Results are in `build/DerivedData/Logs/Test/Test-Tabnax-2026.09.17_20-35-01-+0200.xcresult` (all three UI flows passed; initial native fixture timing failure) and `Test-Tabnax-2026.09.17_20-37-21-+0200.xcresult` (native rerun passed). Console summaries are retained in `test-summary.log`. No OS permissions or saved user settings were changed.

Debug and Release builds succeeded and both app bundles passed strict deep signature verification. The development app was rebuilt and reopened with `scripts/dev.sh --once`; the advanced session pins disclosure was expanded and collapsed successfully in the running settings window.
