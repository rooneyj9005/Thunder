#!/usr/bin/env bash
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

java_is_supported() {
    local major="${1:-}"
    [[ "$major" == "17" || "$major" == "21" ]]
}

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

temurin_linux_arch() {
    case "$(uname -m)" in
        x86_64|amd64) printf '%s\n' "x64" ;;
        aarch64|arm64) printf '%s\n' "aarch64" ;;
        *)
            echo "ERROR: Unsupported Linux architecture for Temurin 21: $(uname -m)." >&2
            return 1
            ;;
    esac
}

install_local_java21() {
    local arch="" java_archive=""

    arch="$(temurin_linux_arch)"
    java_archive="temurin-21-${arch}.tar.gz"

    rm -f "$java_archive"
    curl -sSfL --connect-timeout 30 --max-time 300 \
      -o "$java_archive" \
      "https://api.adoptium.net/v3/binary/latest/21/ga/linux/${arch}/jre/hotspot/normal/eclipse"
    tar -xzf "$java_archive"
    rm -f "$java_archive"

    if ! use_local_java21_if_available; then
        echo "ERROR: Temurin 21 archive did not contain an expected jdk-21* or jre-21* directory." >&2
        exit 1
    fi
}

ensure_supported_java() {
    local major=""

    if command -v java >/dev/null 2>&1; then
        major="$(java_major_version)"
        if java_is_supported "$major"; then
            return 0
        fi
    fi

    if use_local_java21_if_available; then
        major="$(java_major_version)"
        if java_is_supported "$major"; then
            return 0
        fi
    fi

    if [[ -n "$major" ]]; then
        echo "Java $major found. Switching to local Temurin 21."
    else
        echo "No supported Java runtime found. Downloading local Temurin 21."
    fi

    install_local_java21
    major="$(java_major_version)"

    if [[ "$major" != "21" ]]; then
        echo "ERROR: Java 17 or Java 21 is required; found Java ${major:-unknown}." >&2
        exit 1
    fi
}

ensure_supported_java

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
