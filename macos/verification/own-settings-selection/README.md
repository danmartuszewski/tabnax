# Settings selection crash — 2026-09-20

The automatic reproduction crashed on its first selection of Tabnax Settings in Canopy. LLDB captured `EXC_BREAKPOINT` in `NSWMWindowCoordinator.performTransactionUsingBlock:` on the `Tabnax reserved focus` worker. The call chain was `FocusCoordinator.focus` → `AXUIElementPerformAction` → `accessibilityPerformRaise` → `NSWindow.makeKeyAndOrderFront`. At the same time, the main thread was dismissing the switcher panel. See `crash-before.log`.

Accessibility calls to the current process execute AppKit synchronously on their calling thread. The coordinator now dispatches self-targeted focus, verification/repair, and restore operations to the main actor. Other applications retain the existing background focus queue, identity checks, cancellation, and bounded verification.

The earlier idempotent keyboard-start fix addressed a separate cancellation issue; it did not fix this crash.

## Repeatable check

Build Debug and close other Tabnax instances first. The existing Accessibility permission is required. With Canopy saved as the layout, run:

```sh
macos/build/DerivedData/Build/Products/Debug/Tabnax.app/Contents/MacOS/Tabnax \
  --settings --verify-own-selection /absolute/path/results.json
```

The Debug-only harness opens the actual selector and selects only this app's Settings window through `InputRouter.choose` and the production focus coordinator, ten times. Each pass checks that Settings is visible and key after selection. It writes JSON and exits with a nonzero status on failure. It does not change preferences or select another app's windows. An interrupted/crashed run will not produce a new report.

`results.json` records the final run. The three `ExactWindowIntegrationTests` also passed, covering stale process rejection, external duplicate-title exact focus, and idempotent capture startup.
