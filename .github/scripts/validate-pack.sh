#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKWIZ_BIN="${PACKWIZ_BIN:-packwiz}"
EXPECTED_TAG="${EXPECTED_TAG:-}"
SMOKE_PACK_URL="${SMOKE_PACK_URL:-}"

extract_pack_value() {
  local key="$1"
  sed -nE "s/^${key} = \"(.*)\"$/\1/p" "$ROOT_DIR/pack.toml" | head -n 1
}

extract_bcc_value() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key} = \"(.*)\"$/\1/p" "$ROOT_DIR/config/bcc-common.toml" | head -n 1
}

cd "$ROOT_DIR"

pack_name="$(extract_pack_value name)"
pack_version="$(extract_pack_value version)"
bcc_name="$(extract_bcc_value modpackName)"
bcc_version="$(extract_bcc_value modpackVersion)"
normalized_pack_version="${pack_version#v}"
normalized_bcc_version="${bcc_version#v}"

if [[ -z "$pack_name" || -z "$pack_version" ]]; then
  echo "ERROR: Could not read pack name/version from pack.toml." >&2
  exit 1
fi

if [[ -z "$bcc_name" || -z "$bcc_version" ]]; then
  echo "ERROR: Could not read modpack name/version from config/bcc-common.toml." >&2
  exit 1
fi

if [[ "$pack_name" != "$bcc_name" ]]; then
  echo "ERROR: pack.toml name '$pack_name' does not match config/bcc-common.toml name '$bcc_name'." >&2
  exit 1
fi

if [[ "$normalized_pack_version" != "$normalized_bcc_version" ]]; then
  echo "ERROR: pack.toml version '$pack_version' does not match config/bcc-common.toml version '$bcc_version' after normalising an optional leading v." >&2
  exit 1
fi

if [[ -n "$EXPECTED_TAG" ]]; then
  if [[ "$EXPECTED_TAG" =~ ^v[0-9]+(\.[0-9]+)+$ ]]; then
    if [[ "$EXPECTED_TAG" != "v$normalized_pack_version" ]]; then
      echo "ERROR: Tag '$EXPECTED_TAG' does not match pack version 'v$normalized_pack_version'." >&2
      exit 1
    fi
  else
    echo "Info: Skipping tag/version check for non-version tag '$EXPECTED_TAG'."
  fi
fi

for managed_shell in startup.sh update.sh; do
  if LC_ALL=C grep -q $'\r' "$managed_shell"; then
    echo "ERROR: $managed_shell contains CRLF line endings." >&2
    exit 1
  fi
done

"$PACKWIZ_BIN" refresh

if ! git diff --quiet -- pack.toml index.toml; then
  echo "ERROR: packwiz refresh changed tracked metadata." >&2
  git --no-pager diff -- pack.toml index.toml
  exit 1
fi

mkdir -p _ci
rm -f _ci/Thunder.mrpack
"$PACKWIZ_BIN" modrinth export -o _ci/Thunder.mrpack

if [[ -n "$SMOKE_PACK_URL" ]]; then
  smoke_dir="$ROOT_DIR/_ci/smoke-server"
  rm -rf "$smoke_dir"
  mkdir -p "$smoke_dir"
  PACKWIZ_URL="$SMOKE_PACK_URL" PACKWIZ_SIDE=server bash "$ROOT_DIR/update.sh" --dir "$smoke_dir"
fi
