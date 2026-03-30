#!/usr/bin/env bash
set -euo pipefail

MODE="server"
INSTALL_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --container) MODE="container"; shift ;;
    --dir) [[ -n "${2:-}" ]] || { echo "ERROR: --dir requires a path argument." >&2; exit 1; }; INSTALL_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

TARGET_DIR="$PWD"
if [[ "$MODE" == "container" ]]; then
    TARGET_DIR="${INSTALL_DIR:-/mnt/server}"
elif [[ -n "$INSTALL_DIR" ]]; then
    TARGET_DIR="$INSTALL_DIR"
fi

cd "$TARGET_DIR"

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

if [[ "$MODE" == "container" ]]; then
    apt-get -q update
    apt-get install -y --no-install-recommends curl ca-certificates tar gzip
fi

ensure_supported_java

echo "Fetching packwiz-installer-bootstrap..."
curl -sSfL --connect-timeout 30 --max-time 120 \
  -o packwiz-installer-bootstrap.jar \
  "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"
echo "Downloaded packwiz-installer-bootstrap.jar"

MODLOADER="${MODLOADER:-forge}"
MC_VERSION="${MC_VERSION:-1.20.1}"
if [[ "$MODLOADER" == "forge" ]]; then
    FORGE_VERSION="${FORGE_VERSION:-47.4.13}"
else
    FORGE_VERSION="${FORGE_VERSION:-}"
fi

if [[ "$MODLOADER" != "forge" && "$MODLOADER" != "fabric" && "$MODLOADER" != "quilt" ]]; then
  echo "ERROR: MODLOADER must be 'forge', 'fabric', or 'quilt'." >&2
  exit 1
fi

if [[ ! "$MC_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "ERROR: MC_VERSION must be in the form x.y or x.y.z." >&2
  exit 1
fi

if [[ -n "$FORGE_VERSION" ]] && [[ ! "$FORGE_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "ERROR: FORGE_VERSION must contain only digits and dots." >&2
  exit 1
fi

if [[ ! "${SERVER_JARFILE:-server.jar}" =~ ^[A-Za-z0-9._-]+\.jar$ ]]; then
  echo "ERROR: SERVER_JARFILE must be a simple .jar filename." >&2
  exit 1
fi

case "${MODLOADER}" in
  forge)
    rm -f unix_args.txt user_jvm_args.txt run.sh run.bat

    cleanup_forge() { rm -f installer.jar installer.jar.log; }
    trap cleanup_forge EXIT

    RESOLVED_VERSION="${FORGE_VERSION:-}"
    if [[ -z "$RESOLVED_VERSION" ]]; then
      JSON_DATA=$(curl -sSfL --connect-timeout 30 --max-time 30 \
        https://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json)
      RESOLVED_VERSION=$(echo "$JSON_DATA" | jq -r \
        ".promos[\"${MC_VERSION}-recommended\"] // .promos[\"${MC_VERSION}-latest\"]")
      if [[ -z "$RESOLVED_VERSION" || "$RESOLVED_VERSION" == "null" ]]; then
        echo "ERROR: No Forge version found for Minecraft ${MC_VERSION}." >&2
        exit 1
      fi
    fi

    echo "Installing Forge ${MC_VERSION}-${RESOLVED_VERSION}..."
    curl -sSfL --connect-timeout 30 --max-time 120 \
      -o installer.jar \
      "https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${RESOLVED_VERSION}/forge-${MC_VERSION}-${RESOLVED_VERSION}-installer.jar"

    java -jar installer.jar --installServer

    ARGS_FILE="libraries/net/minecraftforge/forge/${MC_VERSION}-${RESOLVED_VERSION}/unix_args.txt"
    if [[ -f "$ARGS_FILE" ]]; then
      ln -sf "$ARGS_FILE" unix_args.txt
      echo "Linked unix_args.txt for Forge ${MC_VERSION}-${RESOLVED_VERSION}"
    elif [[ ! -f "${SERVER_JARFILE:-server.jar}" ]]; then
      echo "ERROR: Forge installation produced neither unix_args.txt nor ${SERVER_JARFILE:-server.jar}." >&2
      exit 1
    fi

    rm -f installer.jar installer.jar.log
    trap - EXIT
    ;;

  fabric)
    FABRIC_LOADER="${FORGE_VERSION:-$(curl -sSfL --connect-timeout 30 --max-time 30 \
      https://meta.fabricmc.net/v2/versions/loader | jq -r '.[0].version')}"
    FABRIC_INSTALLER=$(curl -sSfL --connect-timeout 30 --max-time 30 \
      https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')

    echo "Installing Fabric Loader ${FABRIC_LOADER} for Minecraft ${MC_VERSION}..."

    cleanup_fabric() { rm -f "${SERVER_JARFILE:-server.jar}.tmp"; }
    trap cleanup_fabric EXIT

    curl -sSfL --connect-timeout 30 --max-time 120 \
      -o "${SERVER_JARFILE:-server.jar}.tmp" \
      "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${FABRIC_LOADER}/${FABRIC_INSTALLER}/server/jar"
    mv "${SERVER_JARFILE:-server.jar}.tmp" "${SERVER_JARFILE:-server.jar}"

    trap - EXIT
    ;;

  quilt)
    QUILT_LOADER="${FORGE_VERSION:-$(curl -sSfL --connect-timeout 30 --max-time 30 \
      https://meta.quiltmc.org/v3/versions/loader | jq -r '.[0].version')}"
    QUILT_INSTALLER=$(curl -sSfL --connect-timeout 30 --max-time 30 \
      https://meta.quiltmc.org/v3/versions/installer | jq -r '.[0].version')

    echo "Installing Quilt Loader ${QUILT_LOADER} for Minecraft ${MC_VERSION}..."

    cleanup_quilt() { rm -f "${SERVER_JARFILE:-server.jar}.tmp"; }
    trap cleanup_quilt EXIT

    curl -sSfL --connect-timeout 30 --max-time 120 \
      -o "${SERVER_JARFILE:-server.jar}.tmp" \
      "https://meta.quiltmc.org/v3/versions/loader/${MC_VERSION}/${QUILT_LOADER}/${QUILT_INSTALLER}/server/jar"
    mv "${SERVER_JARFILE:-server.jar}.tmp" "${SERVER_JARFILE:-server.jar}"

    trap - EXIT
    ;;

  *)
    echo "ERROR: Unknown modloader '${MODLOADER}'. Expected: forge, fabric, or quilt." >&2
    exit 1
    ;;
esac

PACKWIZ_URL="${PACKWIZ_URL:-https://packwiz.thunder.john.rooney.scot/pack.toml}"
PACKWIZ_SIDE="${PACKWIZ_SIDE:-server}"

if [[ "$PACKWIZ_SIDE" != "server" && "$PACKWIZ_SIDE" != "both" ]]; then
  echo "ERROR: PACKWIZ_SIDE must be 'server' or 'both'." >&2
  exit 1
fi

if [[ "$PACKWIZ_URL" =~ [[:space:]] ]]; then
  echo "ERROR: PACKWIZ_URL must not contain whitespace." >&2
  exit 1
fi

echo "Syncing modpack via packwiz..."
java -jar packwiz-installer-bootstrap.jar -g -s "${PACKWIZ_SIDE}" "${PACKWIZ_URL}"
chmod +x *.sh
echo "Server installation complete."
