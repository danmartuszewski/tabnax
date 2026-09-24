#!/bin/zsh
set -euo pipefail
exec /usr/bin/python3 -B "${0:A:h}/dev.py" "$@"
