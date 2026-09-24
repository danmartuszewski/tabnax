# Contributing to Tabnax

Start with the [repository map](docs/REPOSITORY.md) and [development guide](docs/DEVELOPMENT.md). The native app is the current implementation; browser prototypes are historical design references.

1. Make a focused branch from `main` and explain the user-visible problem.
2. Keep native code in `macos/`, public website content in `website/`, and cross-project documentation in `docs/`.
3. Run `make check`. For native changes, run `make test-native`; use `make test-ui` for affected native UI flows. Website changes also need a browser check at desktop and narrow widths.
4. Review `git diff` and the exact files to stage. Run `make audit` before sharing. Use sample data in screenshots; do not attach raw desktop, browser, or diagnostic captures.
5. Use [Conventional Commits](https://www.conventionalcommits.org/) titles such as `feat: add Relay search` or `fix: keep Fold prefixes stable`. Release notes and version numbers are generated from them; see [releasing](docs/RELEASING.md).
6. Describe the behavior change, validation, and remaining limitations in the pull request. Update the feature matrix and relevant README when behavior changes.

Never commit credentials, signing keys, provisioning profiles, local settings, build output, or machine-specific paths. Ignore rules protect untracked files; the publication checker also inspects tracked files so an accidental force-add fails CI.

Tests must not grant macOS permissions, register login items, or operate on unrelated real windows/tabs. Use existing isolated preferences and fixture windows. Permission-dependent integration tests may skip without existing trust; document skips accurately.

Tabnax is licensed under the [Apache License 2.0](LICENSE). Contributions are accepted under the same license. Do not add third-party source or artwork without checking its license and recording required attribution in [NOTICE](NOTICE).
