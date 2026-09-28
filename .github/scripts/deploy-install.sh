#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <pack-toml-url> [work-dir]" >&2
  echo "Set EXPECTED_VERSION to wait until the host serves that release first." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACK_URL="$1"
WORK_DIR="${2:-$ROOT_DIR/tmp/tests/install}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"
EXPECTED_VERSION="${EXPECTED_VERSION#v}"

if [[ "$WORK_DIR" == "/" || "$WORK_DIR" == "$ROOT_DIR" ]]; then
  echo "ERROR: Refusing to wipe '$WORK_DIR'." >&2
  exit 1
fi

# Pages reports success once the artifact is deployed, not once every edge
# serves it, and the host sends max-age=600. For up to ten minutes an edge can
# answer with the previous release: an old pack.toml, which tests the wrong
# release and passes, or a new pack.toml beside an old index.toml, whose hash
# then fails and demotes a good release. So wait until pack.toml carries the
# version being deployed and index.toml hashes to what that pack.toml says.
#
# Plain requests on purpose. The question is what packwiz-installer will be
# served, and it sends no cache headers; a no-cache poll could see the new files
# while the install that follows is still handed the old ones.
wait_for_release() {
  local base_url="${PACK_URL%/pack.toml}"
  local deadline=$((SECONDS + 600))
  local pack version index_hash served_hash

  while true; do
    version=""
    served_hash=""

    if pack="$(curl -fsSL --max-time 30 "$PACK_URL")"; then
      version="$(sed -nE 's/^version = "(.*)"$/\1/p' <<<"$pack" | head -n 1)"
      index_hash="$(sed -nE '/^\[index\]/,/^\[/ s/^hash = "(.*)"$/\1/p' <<<"$pack" | head -n 1)"

      if [[ "$version" == "$EXPECTED_VERSION" && -n "$index_hash" ]]; then
        served_hash="$(curl -fsSL --max-time 30 "$base_url/index.toml" | sha256sum | cut -d ' ' -f 1)" || served_hash=""

        if [[ "$served_hash" == "$index_hash" ]]; then
          echo "The host serves $EXPECTED_VERSION, and index.toml matches its pack.toml."
          return 0
        fi
      fi
    fi

    if (( SECONDS >= deadline )); then
      echo "ERROR: After ten minutes the host still does not serve $EXPECTED_VERSION consistently (pack.toml says '${version:-nothing}')." >&2
      return 1
    fi

    echo "Waiting for the host to serve $EXPECTED_VERSION (pack.toml says '${version:-nothing}')..."
    sleep 20
  done
}

if [[ -n "$EXPECTED_VERSION" ]]; then
  wait_for_release
fi

cd "$ROOT_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

PACKWIZ_URL="$PACK_URL" PACKWIZ_SIDE=server bash "$ROOT_DIR/tools/install.sh" --dir "$WORK_DIR"

bash "$ROOT_DIR/.github/scripts/checks-install.sh" "$WORK_DIR" server --forge
