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
PACKWIZ_SKIP_UPDATE="${PACKWIZ_SKIP_UPDATE:-false}"

if [[ "$PACKWIZ_SKIP_UPDATE" == "true" || "$PACKWIZ_SKIP_UPDATE" == "1" || "$PACKWIZ_SKIP_UPDATE" == "yes" ]]; then
    if [[ "$CLEAN_INSTALL" == "true" ]]; then
        echo "Clean install - wiping mods and packwiz config..."
        rm -rf mods config/packwiz-installer.toml
    fi
    echo "Skipping packwiz sync (PACKWIZ_SKIP_UPDATE enabled)."
else
    UPDATE_SCRIPT="$(dirname "$0")/update.sh"
    if [[ ! -f "$UPDATE_SCRIPT" ]]; then
        echo "ERROR: Could not find '$UPDATE_SCRIPT'." >&2
        exit 1
    fi

    "$UPDATE_SCRIPT" --dir "$(pwd)"
fi

VOICE_PORT="${VOICE_PORT:-24454}"
if [[ ! "$VOICE_PORT" =~ ^[0-9]+$ ]] || (( VOICE_PORT < 0 || VOICE_PORT > 65535 )); then
    echo "ERROR: VOICE_PORT must be an integer between 0 and 65535 (0 to disable)." >&2
    exit 1
fi
if (( VOICE_PORT != 0 )); then
    mkdir -p config/voicechat
    echo "port=${VOICE_PORT}" > config/voicechat/voicechat-server.properties
fi
if [[ -f unix_args.txt ]]; then
    exec java -Xms128M -XX:MaxRAMPercentage=95.0 @unix_args.txt
else
    exec java -Xms128M -XX:MaxRAMPercentage=95.0 -jar "${SERVER_JARFILE:-server.jar}"
fi
