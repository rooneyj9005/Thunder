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
    curl -sSfL --connect-timeout 30 --max-time 120 \
      -o packwiz-installer-bootstrap.jar \
      "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"
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
