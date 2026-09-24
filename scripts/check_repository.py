#!/usr/bin/env python3
"""Check the actual public file set, not the entire developer workspace."""

from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
LOCAL_PATH = re.compile(r"/Users/[A-Za-z0-9_.-]+/|/Volumes/" + r"Projects/")
PRIVATE_DIRS = {".git", ".claude", ".codex", ".agents", ".playwright-cli", "build",
                "dist", "DerivedData", ".build", ".swiftpm", "xcuserdata", "node_modules",
                "__pycache__", ".venv", "output", "coverage", ".ssh", ".aws", ".gnupg"}
PRIVATE_SUFFIXES = {".pem", ".key", ".p12", ".pfx", ".cer", ".mobileprovision",
                    ".provisionprofile", ".keychain", ".keychain-db", ".pyc", ".log",
                    ".dmg", ".zip", ".xcuserstate", ".sqlite", ".sqlite3", ".db"}
VERIFICATION_SOURCE = {".md", ".swift", ".py", ".sh"}
MARKDOWN_LINK = re.compile(r"!?\[[^\]\n]+\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)")


def public_files(root=ROOT):
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, check=True, stdout=subprocess.PIPE)
    return sorted(set(p.decode("utf-8") for p in result.stdout.split(b"\0") if p))


def forbidden_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts:
        return True
    if any(part in PRIVATE_DIRS or part.endswith((".app", ".xcresult", ".xcarchive", ".dSYM", ".trace"))
           for part in path.parts):
        return True
    if path.name in {".DS_Store", ".npmrc", ".netrc", "credentials.json"}:
        return True
    if path.name == ".env" or (path.name.startswith(".env.") and path.name != ".env.example"):
        return True
    if path.name.startswith("secrets.") or path.name.endswith(".local.xcconfig"):
        return True
    if path.suffix in PRIVATE_SUFFIXES:
        return True
    if name.startswith("design-exploration/verification/"):
        return True
    return name.startswith("macos/verification/") and path.suffix not in VERIFICATION_SOURCE


class References(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        for attr in ("src", "href", "poster"):
            if attrs.get(attr):
                self.links.append(attrs[attr])


def link_error(source, reference, candidates, root=ROOT, website=False):
    url = urlsplit(reference)
    if url.scheme or url.netloc:
        if url.scheme == "file":
            return "machine-local file URL"
        return None
    if not url.path:
        target = root / source
    else:
        if url.path.startswith("/"):
            return "absolute local link"
        target = (root / source).parent / unquote(url.path)
    target = target.resolve()
    try:
        relative = target.relative_to(root.resolve()).as_posix()
    except ValueError:
        return "link escapes repository"
    if website and not relative.startswith("website/"):
        return "website link escapes deployable directory"
    if relative not in candidates and not any(p.startswith(relative.rstrip("/") + "/") for p in candidates):
        return "target is not in the public file set"
    if website and url.fragment and target.suffix == ".html":
        parser = References()
        parser.feed(target.read_text())
        if unquote(url.fragment) not in parser.ids:
            return "missing HTML anchor"
    return None


def check(root=ROOT):
    candidates = set(public_files(root))
    errors = []
    total = 0
    for name in sorted(candidates):
        path = root / name
        if forbidden_path(name):
            errors.append(f"{name}: private/generated file must not be published")
        if path.is_symlink():
            errors.append(f"{name}: symlinks are not allowed in the public source tree")
            continue
        if not path.is_file():
            errors.append(f"{name}: tracked file is missing or is not a regular file")
            continue
        size = path.stat().st_size
        total += size
        if size > 10 * 1024 * 1024:
            errors.append(f"{name}: file exceeds the 10 MiB source/asset limit")
            continue
        data = path.read_bytes()
        try:
            content = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if LOCAL_PATH.search(content):
            errors.append(f"{name}: contains a personal workstation path")
        links = []
        if path.suffix == ".md":
            # Code fences can contain example URLs that are not document links.
            prose = re.sub(r"```.*?```", "", content, flags=re.S)
            links = MARKDOWN_LINK.findall(prose)
            parser = References()
            parser.feed(prose)
            links += parser.links
        elif name.startswith("website/") and path.suffix == ".html":
            parser = References()
            parser.feed(content)
            links = parser.links
        elif name.startswith("website/") and path.suffix == ".css":
            # Quoted data SVGs can contain nested url(...) fragments.
            links = [next(value for value in match if value) for match in
                     re.findall(r'url\((?:"([^"]*)"|\x27([^\x27]*)\x27|([^)]*))\)', content)]
        for link in links:
            error = link_error(name, link, candidates, root,
                               website=name.startswith("website/") and path.suffix != ".md")
            if error:
                errors.append(f"{name}: {error}: {link}")
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        print(f"FAILED: {len(errors)} publication/link issue(s).", file=sys.stderr)
        return 1
    print(f"PASS: {len(candidates)} public files, {total / 1024 / 1024:.1f} MiB; policy and local links checked.")
    return 0


if __name__ == "__main__":
    sys.exit(check())
