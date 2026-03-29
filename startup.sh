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

use_local_java21_if_available() {
    local java_dir=""

    java_dir="$(find . -maxdepth 1 -type d \( -name 'jdk-21*' -o -name 'jre-21*' \) -print -quit)"
    java_dir="${java_dir#./}"

    if [[ -z "$java_dir" ]]; then
        return 1
    fi

    export JAVA_HOME="$PWD/$java_dir"
    export PATH="$JAVA_HOME/bin:$PATH"
    echo "Using local Java 21 runtime at $JAVA_HOME"
    return 0
}

java_major_version() {
    java -version 2>&1 | awk -F '"' '/version/ { split($2, parts, "."); if (parts[1] == 1 && parts[2] != "") { print parts[2]; } else { print parts[1]; } exit }'
}

ensure_java21() {
    local major=""

    if ! command -v java >/dev/null 2>&1; then
        if ! use_local_java21_if_available; then
            echo "ERROR: Java 21 is required." >&2
            exit 1
        fi
    fi

    major="$(java_major_version)"
    if [[ "$major" != "21" ]]; then
        if use_local_java21_if_available; then
            major="$(java_major_version)"
        fi
    fi

    if [[ "$major" != "21" ]]; then
        echo "ERROR: Java 21 is required; found Java ${major:-unknown}." >&2
        exit 1
    fi
}

ensure_java21

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
