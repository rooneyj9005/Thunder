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

PACKWIZ_URL="${PACKWIZ_URL:-https://thunder.john.rooney.scot/pack.toml}"
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

echo "Syncing modpack via packwiz..."
PACKWIZ_ARGS=(-g -s "${PACKWIZ_SIDE}")
if [[ -n "${PACKWIZ_EXTRA_FLAGS:-}" ]]; then
  if [[ "${PACKWIZ_EXTRA_FLAGS}" =~ [\;\&\|\<\>\`\$\(\)\{\}] ]]; then
    echo "ERROR: PACKWIZ_EXTRA_FLAGS contains unsupported characters." >&2
    exit 1
  fi
  read -r -a EXTRA_ARGS <<< "${PACKWIZ_EXTRA_FLAGS}"
  PACKWIZ_ARGS+=("${EXTRA_ARGS[@]}")
fi
PACKWIZ_ARGS+=("${PACKWIZ_URL}")
java -jar packwiz-installer-bootstrap.jar "${PACKWIZ_ARGS[@]}"

VOICE_PORT="${VOICE_PORT:-24454}"
if [[ ! "$VOICE_PORT" =~ ^[0-9]+$ ]] || (( VOICE_PORT < 1 || VOICE_PORT > 65535 )); then
    echo "ERROR: VOICE_PORT must be an integer between 1 and 65535." >&2
    exit 1
fi
mkdir -p config/voicechat
echo "port=${VOICE_PORT}" > config/voicechat/voicechat-server.properties
if [[ -f unix_args.txt ]]; then
    exec java -Xms128M -XX:MaxRAMPercentage=95.0 @unix_args.txt
else
    exec java -Xms128M -XX:MaxRAMPercentage=95.0 -jar "${SERVER_JARFILE:-server.jar}"
fi
