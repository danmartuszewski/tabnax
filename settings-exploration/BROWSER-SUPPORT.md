# Browser coverage and minimal setup

Updated 17 September 2026. **Arc and Zen are required targets**, following the user’s explicit request. Safari, Chrome, Firefox, Edge and Brave round out the proposed initial browser list. This document specifies the connection approach; the browser prototype still uses synthetic tabs. No real tab data was read, no browser was controlled and no permission or extension was installed during this work.

## User experience

Default **Use tabs from: All available browsers**. The native app should discover supported installed browsers and their availability automatically. The user can instead select **Choose browsers…** and tick only the browsers they want. Arc and Zen appear first. Browser inclusion intersects with All included browsers / Active browser / Active browser window; it does not override those filters.

Discovery is read-only. It does not launch every browser or prompt for every permission. An already-authorized connection should work immediately. A selected browser that needs access shows a clear action in its own row, with a brief explanation before the native permission request. Connect browsers independently so one denied or unsupported connection cannot block the others. Automatic mode includes available supported browsers, not private tabs or unapproved data sources.

The goal is **choose a browser, approve access if needed, use it**. Avoid terminal commands, Developer Mode, manually copied files, debugging ports and editing browser preferences. For an add-on connection, Tabnax handles app-side registration and verification; the browser still owns installation and consent. Do not claim that OS or browser approval can be eliminated.

Persist the selected browser IDs and automatic/selected mode. Keep connection health, installation detection, permissions and profile sessions as observed runtime state. Disabling a browser stops its catalogue updates and removes its eligible targets while preserving address reservations for still-live identities. Re-enabling reconciles the adapter generation before restoring labels. Browser settings changes must not reassign other window or tab labels.

## Proposed connection approaches

| Browser | Preferred approach on macOS | Expected user action | Evidence and remaining work |
| --- | --- | --- | --- |
| **Arc** | Built-in Apple-event adapter | Select it; approve Automation if requested | Installed dictionary exposes windows, tabs, tab IDs, tab `select`, Spaces and space `focus`; verify real focus, Spaces, shared tabs, pinned/favorite tabs and incognito exclusion |
| **Zen** | Firefox-compatible companion add-on with native messaging | Select it; follow guided add-on installation if required | Zen officially supports Firefox extensions; no scripting dictionary was found in its installed bundle. This makes an add-on the preferred hypothesis, not proof that every other approach is impossible. Verify native-host discovery and workspace behavior |
| Safari | Evaluate built-in scripting first; extension if necessary | Select it; guided approval/setup if needed | Dictionary has tabs and current-tab selection. Stable per-tab IDs and private-window classification are not established by the inspected tab definition; resolve before promising a built-in-only adapter |
| Chrome | Built-in Apple-event adapter | Select it; approve Automation if requested | Installed dictionary exposes tab IDs, window mode and active-tab index; verify identity and exact focus |
| Firefox | Companion add-on with native messaging | Select it; guided add-on installation | Documented WebExtensions APIs provide tab metadata and selection; installed bundle has no scripting dictionary; test profile connections |
| Edge | Built-in Apple-event adapter | Select it; approve Automation if requested | Installed dictionary exposes the relevant Chromium-style tab/window properties; validate independently |
| Brave | Built-in Apple-event adapter | Select it; approve Automation if requested | Installed dictionary exposes the relevant Chromium-style tab/window properties; validate independently |

**These are implementation recommendations, not completed integrations.** A dictionary establishes a declared interface, not reliable runtime behavior. No extension is planned for the built-in candidates unless a specific requirement cannot be met. The final adapter must satisfy privacy, identity and exact-target selection; simplicity must not depend on guessing titles or reading browser profile databases.

## Evidence checked

Local, read-only application metadata and scripting dictionaries were inspected on 17 September 2026:

| Application version | Bundle identifier | Declared dictionary |
| --- | --- | --- |
| Arc 1.164.0 | `company.thebrowser.Browser` | `Arc.sdef` |
| Zen 1.19.3b | `app.zen-browser.zen` | None found |
| Safari 26.6.2 | `com.apple.Safari` | `Safari.sdef` |
| Chrome 152.0.7977.84 | `com.google.Chrome` | `scripting.sdef` |
| Firefox 147.0.2 | `org.mozilla.firefox` | None found |
| Edge 153.0.4234.32 | `com.microsoft.edgemac` | `scripting.sdef` |
| Brave 142.1.84.132 | `com.brave.Browser` | `scripting.sdef` |

Files were inspected under each application’s `Contents/Info.plist` and `Contents/Resources`. Nothing sent Apple events or enumerated the user’s tabs. Version evidence is local to this installation and date.

Primary references:

- Arc’s own release notes describe its AppleScript API for querying tabs and Spaces. This supports the native adapter direction alongside the installed dictionary. [Arc macOS release notes](https://resources.arc.net/hc/en-us/articles/20498377604887-Arc-for-macOS-2023-Release-Notes).
- Zen documents installing extensions from Mozilla’s add-on store. This supports trying a shared Firefox/Zen extension; it does not establish compatibility with Tabnax’s proposed native host. [Zen extensions](https://docs.zen-browser.app/user-manual/extensions).
- Firefox’s tab API requires suitable permission for titles/URLs, and tab IDs are browser-session scoped. Use an explicit browser/profile/connection generation with IDs. [Mozilla tabs API](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs).
- Native messaging requires an extension permission and an app manifest installed with the native application. Tabnax should own that installation so the user never copies configuration files. Zen’s discovery paths remain to be verified. [Mozilla native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging).
- Selecting an active tab does not necessarily focus its window. Treat selection and window focus as separate verified actions. [Mozilla tabs.update](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs/update).
- macOS controls cross-application automation through user consent and Privacy & Security settings. A checkbox expresses intention; it cannot substitute for that consent. [Apple automation permissions](https://support.apple.com/en-gb/guide/mac-help/mchl07817563/mac).

## Arc and Zen details

Arc Spaces and Zen workspaces are browser concepts, distinct from macOS Spaces and windows. Preserve their names as optional context only when the adapter can determine them reliably. Show pinned/favorite state when known. Do not fabricate a workspace from a window title or hide a tab merely because it is not in the currently selected workspace.

The base scope remains live tabs. Arc archive entries, history and unrelated bookmarks are out of scope. Deduplicate tabs mirrored across Arc windows and check Zen’s window/workspace semantics using actual adapter identities. A tab moving between windows/workspaces retains a label only when identity continuity is confirmed. Respect split views without guessing which pane received focus. Suspended or unloaded tabs need an explicit capability result; verify whether selection revives the same identity.

The extension should request only tab metadata and native communication needed for switching. Avoid page-content access, content scripts, remote debugging and screenshot APIs. Reject private/incognito data before it enters the catalogue. If the adapter cannot reliably distinguish it, the browser must remain unavailable until that requirement is resolved.

## Prototype behavior and acceptance

The updated prototype contains **48 sample tabs across seven browsers**. Arc and Zen appear first in the preview. Arc is the sample active browser; Prototype controls can change that sample to exercise range filtering. This scenario is not persisted and says nothing about the user’s active browser.

Automatic mode includes every sample browser; individual checkboxes are disabled until Choose browsers is selected. A selected subset is remembered when switching back and forth. All-excluded and excluded-active-browser cases show an empty state. Global browser-tab disabling preserves the selection. Setup buttons describe the proposed route and explicitly disclose the simulation. They do not fake successful connections.

Acceptance covers Arc/Zen direct labels and search, selecting only those browsers, range intersections, unchanged labels, Undo, persistence, old-preference migration and narrow layouts. Native acceptance additionally requires exact focus, cold/closed browser behavior, updates/restarts, profile isolation, denial/revocation, private exclusion, workspace moves, split views and reconnection recovery for each supported browser. Connection setup must complete through the app/browser UI without asking the user to edit files or run commands.
