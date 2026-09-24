# Development

Run commands from the repository root. Git, Python 3.9+, and Node.js 22+ cover portable checks. Native work requires an Apple silicon Mac with macOS 15+, Xcode with the macOS 26 SDK or newer, and Swift 6. The code uses the macOS 26 glass API behind availability checks. The app's only third-party Swift dependency is Sparkle, fetched by Swift Package Manager on the first build. No npm application dependencies are required. The version is set in `macos/Config/Tabnax.xcconfig`; see [releasing](RELEASING.md).

```sh
make help
make website
make build
make dev
```

`make website` serves only `website/` on loopback. To inspect historical studies, serve an individual study directory, for example `python3 -m http.server 4174 --bind 127.0.0.1 --directory settings-exploration`. Some historical browser callbacks expect a repository-root URL; use a temporary loopback root server only when running those callbacks.

## Native development signing

The checked-in Xcode project signs development builds ad hoc (`CODE_SIGN_IDENTITY = "-"`). A local certificate is optional. To keep a stable local development signature, create ignored `macos/Signing.local.xcconfig`:

```xcconfig
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Your Local Development Certificate
```

Set `XCODE_XCCONFIG_FILE="$PWD/macos/Signing.local.xcconfig"` when running `make build`, `make dev`, or `make test-native`; Xcode applies it without changing the shared project. Copies signed with a different identity may need Accessibility reapproval. Do not add certificates, keychains, passwords, or team secrets to this file or repository. These settings do not create a distributable signed release.

When changing an existing build’s signing identity, Xcode can retain an embedded extension with the previous signature. If it reports mismatched parent/extension certificates, use Product → Clean Build Folder in Xcode and rebuild, or clean the generated cache once with `xcodebuild -project macos/Tabnax.xcodeproj -scheme Tabnax -derivedDataPath macos/build/DerivedData clean`.

## Verification

| Command | Coverage |
| --- | --- |
| `make check` | Public-file policy, relative links, self-contained site assets, scanner regressions, dev runner, browser companion protocol, settings model tests. |
| `make test-core` | Pure Swift models. |
| `make test-native` | Core package, controlled fixture build, native XCTest contracts. |
| `make test-ui` | Native tests plus UI automation using isolated preferences and app identity. |
| `make audit` | Redacted secret scan of current candidate files and all Git history. Requires Gitleaks. |

Tests needing existing Accessibility trust may skip. UI automation uses the desktop and can be affected by foreground apps; run it in a controlled session. Builds do not grant permissions or enable login items. Fixture/render commands are in the [app README](../macos/README.md).

For website changes, verify all six modes, search, direct selection, browser/app toggles, native image dialogs, build guide, keyboard focus, and narrow-screen layout. The browser simulation is separate from the native renderer.

CI uses an Apple silicon `macos-26` runner and Ubuntu for portable checks. [GitHub’s runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) documents these environments. No hosted CI run has occurred until the repository is pushed to GitHub.
