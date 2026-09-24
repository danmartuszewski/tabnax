#!/usr/bin/env python3
"""Download one pinned scanner and verify SHA-256 before extracting its binary."""

import argparse
import hashlib
import io
from pathlib import Path
import platform
import tarfile
from urllib.request import urlopen

VERSION = "8.30.1"
ARTIFACTS = {
    ("Darwin", "arm64"): ("darwin_arm64", "b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5"),
    ("Darwin", "x86_64"): ("darwin_x64", "dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709"),
    ("Linux", "x86_64"): ("linux_x64", "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="Directory outside the repository for the binary")
    args = parser.parse_args()
    key = (platform.system(), platform.machine())
    if key not in ARTIFACTS:
        parser.error("No pinned artifact for this platform; install Gitleaks separately.")
    suffix, digest = ARTIFACTS[key]
    url = f"https://github.com/gitleaks/gitleaks/releases/download/v{VERSION}/gitleaks_{VERSION}_{suffix}.tar.gz"
    with urlopen(url, timeout=60) as response:
        archive = response.read(32 * 1024 * 1024)
    if hashlib.sha256(archive).hexdigest() != digest:
        raise SystemExit("Gitleaks checksum mismatch; nothing was installed.")
    args.destination.mkdir(parents=True, exist_ok=True)
    target = args.destination / "gitleaks"
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        member = tar.getmember("gitleaks")
        if not member.isfile():
            raise SystemExit("Expected a regular executable in the verified archive.")
        with tar.extractfile(member) as source, target.open("xb") as output:
            output.write(source.read())
    target.chmod(0o755)
    print(f"Verified Gitleaks {VERSION}: {target}")


if __name__ == "__main__":
    main()
