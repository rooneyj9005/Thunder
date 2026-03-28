#!/bin/bash
set -euo pipefail

SERVER_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) shift ;;
    --dir) [[ -n "${2:-}" ]] || { echo "ERROR: --dir requires a path argument." >&2; exit 1; }; SERVER_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$SERVER_DIR" ]]; then
    cd "$SERVER_DIR"
fi

PACKWIZ_URL="${PACKWIZ_URL:-https://packwiz.thunder.john.rooney.scot/pack.toml}"
PACKWIZ_SIDE="${PACKWIZ_SIDE:-server}"
CLEAN_INSTALL="${CLEAN_INSTALL:-false}"

: "${PACKWIZ_URL:?ERROR: PACKWIZ_URL must be set}"
: "${PACKWIZ_SIDE:?ERROR: PACKWIZ_SIDE must be set}"

if [[ "$PACKWIZ_SIDE" != "server" && "$PACKWIZ_SIDE" != "both" ]]; then
    echo "ERROR: PACKWIZ_SIDE must be 'server' or 'both'." >&2
    exit 1
fi

if [[ "$CLEAN_INSTALL" != "true" && "$CLEAN_INSTALL" != "false" ]]; then
    echo "ERROR: CLEAN_INSTALL must be 'true' or 'false'." >&2
    exit 1
fi

if [[ "$PACKWIZ_URL" =~ [[:space:]] ]]; then
    echo "ERROR: PACKWIZ_URL must not contain whitespace." >&2
    exit 1
fi

if [[ "$CLEAN_INSTALL" == "true" ]]; then
    echo "Clean install - wiping mods and packwiz config..."
    rm -rf mods config/packwiz-installer.toml
fi

if [[ ! -f "packwiz-installer-bootstrap.jar" ]]; then
    echo "packwiz-installer-bootstrap.jar not found, downloading latest release..."
    PACKWIZ_BOOTSTRAP_URL=$(curl -sSfL --connect-timeout 30 --max-time 30 \
      https://api.github.com/repos/packwiz/packwiz-installer-bootstrap/releases/latest \
      | jq -r '
        .assets as $assets
        | ($assets | map(select(.name == "packwiz-installer-bootstrap.jar")) | .[0].browser_download_url)
          // ($assets | map(select((.name | endswith(".jar")) and ((.name | test("(sources|javadoc)\\.jar$")) | not))) | .[0].browser_download_url)
          // empty
      ')
    if [[ -z "$PACKWIZ_BOOTSTRAP_URL" ]]; then
        echo "ERROR: Failed to resolve packwiz-installer-bootstrap download URL." >&2
        exit 1
    fi
    curl -sSfL --connect-timeout 30 --max-time 120 \
      -o packwiz-installer-bootstrap.jar "$PACKWIZ_BOOTSTRAP_URL"
fi

echo "Syncing modpack via packwiz..."
PACKWIZ_ARGS=(-g -s "${PACKWIZ_SIDE}")
if [[ -n "${PACKWIZ_EXTRA_FLAGS:-}" ]]; then
  if [[ "${PACKWIZ_EXTRA_FLAGS}" =~ [\;\&\|\<\>\`\$\(\)\{\}] ]] || [[ "${PACKWIZ_EXTRA_FLAGS}" =~ $'\n' ]]; then
    echo "ERROR: PACKWIZ_EXTRA_FLAGS contains unsupported characters." >&2
    exit 1
  fi
  read -r -a EXTRA_ARGS <<< "${PACKWIZ_EXTRA_FLAGS}"
  PACKWIZ_ARGS+=("${EXTRA_ARGS[@]}")
fi
PACKWIZ_ARGS+=("${PACKWIZ_URL}")
java -jar packwiz-installer-bootstrap.jar "${PACKWIZ_ARGS[@]}"
