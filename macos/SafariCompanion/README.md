# Safari companion

The `TabnaxSafari` target is embedded in the native app. Safari owns extension approval; Tabnax cannot enable it silently.

`Resources/background.js` implements the browser protocol. `Resources/safari-port.js` adapts Safari messaging, while `SafariWebExtensionHandler.swift` connects it to the native app’s local bridge. `BridgeLock.swift` provides shared synchronization. The extension has its own sandbox entitlements and a narrow local IPC exception.

Build through `make build` or the shared Tabnax Xcode scheme. Run `node macos/BrowserCompanion/tests/safari-port.test.cjs` from the repository root for the transport contract checks; the companion suite also checks the Safari background script.

Development may require Safari’s unsigned-extension setting. A production build needs owner-controlled signing, notarization, and a clean-install approval test. Do not commit certificates, keys, or provisioning files. See the [native browser guide](../README.md#browsers).
