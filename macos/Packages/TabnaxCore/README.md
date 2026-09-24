# TabnaxCore

The native app’s dependency-free Swift 6 package, targeting macOS 15+. It holds pure models and behavior contracts; UI rendering, Accessibility calls, and browser lifecycle live in the containing app.

| Source | Responsibility |
| --- | --- |
| `Settings.swift`, `Theme.swift` | Validated settings, migrations, scoped restore, appearance. |
| `Selection.swift`, `LabelSession.swift` | Stable labels, target identity, session address freezing, overflow. |
| `Ordering.swift` | Optional stable/MRU/alphabetical/state ordering, independent of identity and direct labels. |
| `Navigation.swift`, `ModeLayout.swift` | Navigation and six-mode layout models. |
| `Search.swift` | Field-bounded fuzzy ranking and opt-in bounded choice fingerprints using system CryptoKit. |
| `AppShortcuts.swift` | Persistent app-letter assignments and launch-target contracts. |
| `BrowserProtocol.swift` | Bounded browser messages and validation. |

From the repository root, run `make test-core`. Tests live in `Tests/TabnaxCoreTests/`. The Xcode project consumes this package through its relative local path; there is no separate publishing step.

See the [architecture guide](../../../docs/ARCHITECTURE.md) for the native integration boundary.
