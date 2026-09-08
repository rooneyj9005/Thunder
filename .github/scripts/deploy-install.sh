#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <pack-toml-url> [work-dir]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACK_URL="$1"
WORK_DIR="${2:-$ROOT_DIR/tmp/tests/install}"

if [[ "$WORK_DIR" == "/" || "$WORK_DIR" == "$ROOT_DIR" ]]; then
  echo "ERROR: Refusing to wipe '$WORK_DIR'." >&2
  exit 1
fi

cd "$ROOT_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

PACKWIZ_URL="$PACK_URL" PACKWIZ_SIDE=server bash "$ROOT_DIR/tools/install.sh" --dir "$WORK_DIR"

bash "$ROOT_DIR/.github/scripts/checks-install.sh" "$WORK_DIR" server --forge
