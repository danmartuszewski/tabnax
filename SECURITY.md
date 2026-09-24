# Security

## Reporting a vulnerability

Do not post secrets, private window titles, browser URLs, or exploit details in public issues. Once this project is hosted on GitHub, use **Security → Report a vulnerability** when private vulnerability reporting is enabled. If that option is unavailable, ask the repository owner for a private reporting channel without including sensitive details. No separate security mailbox is configured yet.

Provide the affected revision, macOS/browser versions, a minimal reproduction using sample data, the observed impact, and any proposed fix. Only the latest release receives fixes, delivered as a new version through Sparkle and Homebrew. No response-time commitment has been established.

## Trust boundaries

- The main app uses cross-app Accessibility and optional browser Automation. It is not App Sandbox confined. Approvals remain controlled by macOS and the browser.
- The Safari extension is sandboxed with a local IPC exception. Gecko and Safari companions exchange bounded JSON with the app through local native messaging/Unix sockets.
- Socket permissions and peer-user checks constrain the bridge to the current user; it is not a security boundary against malicious software already running as that user.
- Private tabs are excluded. Tab titles/URLs and window titles are sensitive runtime data; do not include them in public reports.
- The current website has no third-party scripts, forms, analytics, or backend. Its demo uses sample data.

See [PRIVACY.md](docs/PRIVACY.md) for storage and permission details.

## Sharing this repository

`make check` checks the exact publishable file set (tracked files plus non-ignored untracked files), forbidden artifacts, workstation paths, and links. `make audit` additionally runs the default Gitleaks rules against those candidate files and all existing Git history. Findings are redacted. These checks reduce accidental exposure; they do not prove the absence of every secret or vulnerability.

CI uses read-only repository permissions, pinned actions, and no signing credentials. Pull request code runs on hosted runners using `pull_request`, never privileged `pull_request_target`.

If a credential is exposed, revoke or rotate it first. Removing it from the latest file does not remove it from Git history, clones, or caches. Coordinate history cleanup with the owner after rotation.
