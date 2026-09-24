# Firefox and Zen companion

This source extension connects Firefox/Zen to Tabnax through native messaging. It enumerates non-private tab metadata and selects exact tabs; it does not read page contents or browsing history.

- `manifest.json`: extension identity and `tabs`/`nativeMessaging` permissions. Private-window operation is disabled.
- `background.js`: browser events, snapshots, selection and connection lifecycle.
- [SETUP.html](SETUP.html): temporary development installation and native-host setup.
- `tests/`: protocol tests for Gecko and the Safari transport.

From the repository root:

```sh
node macos/BrowserCompanion/tests/companion.test.cjs
node macos/BrowserCompanion/tests/safari-port.test.cjs
```

Use **Settings → Browser tabs → Set up** in the native app to register the user-local host. Temporary extension installation is for development; permanent Firefox/Zen distribution requires a signed add-on. No signing credentials belong in this directory.

The Safari resource copy is covered by the shared protocol tests; maintain protocol compatibility when changing either extension. See [browser setup](../README.md#browsers), [privacy](../../docs/PRIVACY.md), and [security](../../SECURITY.md).
