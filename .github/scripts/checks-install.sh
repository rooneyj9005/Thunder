#!/usr/bin/env bash
set -euo pipefail

# Checks that an install or an update actually produced the pack, not just that
# it exited zero. packwiz-installer finishes happily against metadata that
# resolved to nothing, so a test reading only the exit code would call an
# empty directory a pass. The deploy workflow rolls Pages back on that result,
# and it needs to mean something.
#
# Usage: checks-install.sh <dir> <server|client|both> [--forge]
#
#   --forge  also require the Forge server install (unix_args.txt or server.jar).
#            tools/install.sh produces it; tools/update.sh does not.

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <dir> <server|client|both> [--forge]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$1"
SIDE="$2"
REQUIRE_FORGE=0

case "${3:-}" in
  "")
    ;;
  --forge)
    REQUIRE_FORGE=1
    ;;
  *)
    echo "ERROR: Unknown option '$3'." >&2
    exit 2
    ;;
esac

case "$SIDE" in
  server|client|both)
    ;;
  *)
    echo "ERROR: Side must be server, client or both, not '$SIDE'." >&2
    exit 2
    ;;
esac

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: $TARGET_DIR does not exist, so nothing was installed." >&2
  exit 1
fi

expected_file="$(mktemp)"
actual_file="$(mktemp)"
missing_file="$(mktemp)"
unexpected_file="$(mktemp)"
trap 'rm -f "$expected_file" "$actual_file" "$missing_file" "$unexpected_file"' EXIT

# Invoked through bash because the scripts in this repo are not marked
# executable, the same way the workflows call this one.
bash "$SCRIPT_DIR/checks-mods.sh" "$SIDE" > "$expected_file"

if [[ -d "$TARGET_DIR/mods" ]]; then
  find "$TARGET_DIR/mods" -maxdepth 1 -name '*.jar' -printf '%f\n' | sort > "$actual_file"
else
  : > "$actual_file"
fi

expected_count="$(wc -l < "$expected_file" | tr -d ' ')"
actual_count="$(wc -l < "$actual_file" | tr -d ' ')"

failed=0

if [[ "$expected_count" -eq 0 ]]; then
  echo "ERROR: index.toml lists no $SIDE-side mods, which cannot be right." >&2
  failed=1
fi

comm -23 "$expected_file" "$actual_file" > "$missing_file"
comm -13 "$expected_file" "$actual_file" > "$unexpected_file"

if [[ -s "$missing_file" ]]; then
  echo "ERROR: $TARGET_DIR/mods is missing $SIDE-side mods the pack lists:" >&2
  sed 's/^/  /' "$missing_file" >&2
  failed=1
fi

if [[ -s "$unexpected_file" ]]; then
  echo "ERROR: $TARGET_DIR/mods holds jars the pack does not list:" >&2
  sed 's/^/  /' "$unexpected_file" >&2
  failed=1
fi

if [[ ! -f "$TARGET_DIR/startup.sh" ]]; then
  echo "ERROR: $TARGET_DIR/startup.sh is missing, so the install cannot be started." >&2
  failed=1
fi

if [[ "$REQUIRE_FORGE" -eq 1 && ! -e "$TARGET_DIR/unix_args.txt" && ! -e "$TARGET_DIR/server.jar" ]]; then
  echo "ERROR: $TARGET_DIR has neither unix_args.txt nor server.jar, so Forge did not install." >&2
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "OK: $TARGET_DIR holds all $expected_count $SIDE-side mods and nothing else ($actual_count jars)."
