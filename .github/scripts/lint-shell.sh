#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "ERROR: shellcheck is required but was not found on PATH." >&2
  exit 1
fi

shellcheck \
  install.sh \
  startup.sh \
  update.sh \
  .github/scripts/*.sh
