# Privacy and permissions

This describes the current source implementation, not an independent security audit or future release promise.

## Native data

Tabnax reads running application identity, window titles/state/geometry, and exact AX window handles to present and focus destinations. Approved browser connections supply non-private tab identity, title, URL, and browser/window context. Search terms are processed locally. Treat window and tab metadata as private even though the app does not read page contents.

Settings and persistent app assignments use local macOS preferences. Temporary window/tab identities and session labels track their targets’ lifetime. Browser setup can register a user-local native messaging host pointing at the development app. Runtime sockets live under the per-user `pl.tabnax` temporary directory. No cloud account, telemetry backend, or remote synchronization is implemented.

Signed releases check for updates with [Sparkle](https://sparkle-project.org). On the second launch Sparkle asks whether to check automatically; the choice can be changed from the update window. A check downloads `appcast.xml` from the project's GitHub releases, which GitHub can log like any web request, including the IP address, app version, and macOS version in the user agent. Sparkle's anonymous system profile is not enabled. Updates install only when the EdDSA signature and Developer ID signature both match. Debug and local builds have no updater.

Search-choice memory is optional and disabled by default. Enabling **General → Search → Remember search choices** stores at most 128 recent choices in local preferences as salted SHA-256 query/target fingerprints. Raw queries and titles are not written to this store. These fingerprints influence ranking only; they are not encryption and are never used to identify a window for focus. Clear, switching the option off, or restoring defaults deletes this state; Undo does not restore it. Settings previews do not record choices.

Recent-window ordering keeps only runtime target identities: the current window and up to 32 previous observed windows. This history is not saved across app restarts. Sorting preferences persist; cycling and desktop spotlight preview do not record real recency.

## Permissions

| Permission | Purpose |
| --- | --- |
| Accessibility | Discover/focus windows and operate the consuming keyboard event tap. |
| Browser Automation | Allow Apple-event adapters to list and select tabs. |
| Browser extension approval | Enable the Firefox/Zen or Safari companion. |
| Login item registration | Start Tabnax at login, only when enabled. |

The app does not request Screen Recording or additional Input Monitoring. Companions request `tabs` and `nativeMessaging`; they have no page-content scripts, history permission, profile-database access, or remote-debugging connection. Private tabs are excluded. Consent is controlled by macOS and the browser; resetting settings does not reset system consent.

## Website

The static website uses bundled scripts, styles, images, and in-memory sample data. It has no analytics, tracking cookies, account, signup form, or backend. Copying a development command uses the clipboard only after a button click. A future hosting provider may keep request logs under its own policy; no public host is configured by this repository setup.

## Screenshots and diagnostics

Publish only app-owned renders with reviewed sample data. Raw desktop captures, browser snapshots, traces, and logs are excluded from Git because they can contain personal data or local paths. Before sharing a report, inspect it for titles, URLs, usernames, environment variables, tokens, and file paths. Public gallery provenance is in the [website README](../website/README.md).
