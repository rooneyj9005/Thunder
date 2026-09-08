#!/usr/bin/env bash
set -euo pipefail

# Prints the jar filenames the pack expects on one side, sorted, one per line.
#
# index.toml lists every metafile, and each metafile names the jar it installs
# and the side it belongs on. That makes the pack its own answer to "what should
# a correct instance hold", and this script is where that answer is worked out.
#
# The CI install checks and the local test harness both compare against it, so
# the side rule (an absent side means both) lives in one place instead of being
# reimplemented either side of the fence.
#
# Usage: checks-mods.sh <server|client|both>

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <server|client|both>" >&2
  exit 2
fi

SIDE="$1"

case "$SIDE" in
  server|client|both)
    ;;
  *)
    echo "ERROR: Side must be server, client or both, not '$SIDE'." >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! -f "$ROOT_DIR/index.toml" ]]; then
  echo "ERROR: $ROOT_DIR/index.toml is missing, so the pack cannot say what it holds." >&2
  exit 1
fi

sed -nE 's/^file = "(mods\/.*\.pw\.toml)"$/\1/p' "$ROOT_DIR/index.toml" |
  while IFS= read -r metafile; do
    [[ -f "$ROOT_DIR/$metafile" ]] || continue

    mod_file="$(sed -nE 's/^filename = "(.*)"$/\1/p' "$ROOT_DIR/$metafile" | head -n 1)"
    mod_side="$(sed -nE 's/^side = "(.*)"$/\1/p' "$ROOT_DIR/$metafile" | head -n 1)"
    mod_side="${mod_side:-both}"

    [[ -n "$mod_file" ]] || continue

    if [[ "$SIDE" == "both" || "$mod_side" == "both" || "$mod_side" == "$SIDE" ]]; then
      printf '%s\n' "$mod_file"
    fi
  done | sort
