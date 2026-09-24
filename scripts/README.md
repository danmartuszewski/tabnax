# Repository tooling

These scripts use the Python standard library and Git. Run them from any directory; they locate the repository from their own paths. `make` targets are intended for the repository root.

- `check_repository.py`: checks tracked files plus non-ignored untracked files, including tracked files that now match `.gitignore`. Rejects private/generated artifacts, symlinks, oversized assets, personal paths, and broken local links. HTML website links must stay inside `website/`.
- `audit.py`: exports that checked file set to a temporary directory, scans it with Gitleaks, and then scans all existing Git history. It does not stage or commit anything. Output is redacted.
- `install_gitleaks.py`: downloads Gitleaks 8.30.1 to an explicitly selected directory and verifies its pinned SHA-256 before extracting the executable. Supports arm64/x86_64 macOS runtimes and Linux x86_64; refuses to overwrite an existing binary.
- `tests/test_publication.py`: regression coverage for force-added ignored files, forbidden artifacts, and website deployment boundaries.

To install a disposable scanner and audit locally:

```sh
scanner_dir="$(mktemp -d)"
python3 scripts/install_gitleaks.py "$scanner_dir"
GITLEAKS_BIN="$scanner_dir/gitleaks" make audit
```

The installer requires network access. Other checks use local files. The artifact version and hashes come from the [official Gitleaks release](https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1); review upstream checksums before updating them. The scan uses [Gitleaks’ default rules](https://github.com/gitleaks/gitleaks) plus a workstation-path rule. It is a publication check, not a full application vulnerability audit or image-content scanner.
