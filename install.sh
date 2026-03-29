#!/bin/bash
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

if [[ "$MODE" == "container" ]]; then
    apt-get -q update
    apt-get install -y --no-install-recommends curl jq ca-certificates

    if ! command -v java >/dev/null 2>&1; then
        if apt-get install -y --no-install-recommends openjdk-21-jre-headless; then
            :
        else
            echo "openjdk-21-jre-headless not available, downloading Temurin 21 JRE..." >&2
            apt-get install -y --no-install-recommends tar gzip

            JAVA_TAR="temurin-21.tar.gz"
            curl -sSfL --connect-timeout 30 --max-time 300 \
              -o "$JAVA_TAR" \
              "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jre/hotspot/normal/eclipse"
            tar -xzf "$JAVA_TAR"
            rm -f "$JAVA_TAR"

            JRE_DIR="$(find . -maxdepth 1 -type d \( -name 'jdk-21*' -o -name 'jre-21*' \) -print -quit)"
            JRE_DIR="${JRE_DIR#./}"
            if [[ -z "$JRE_DIR" ]]; then
                echo "ERROR: Temurin 21 archive did not contain an expected jdk-21* or jre-21* directory." >&2
                exit 1
            fi

            export JAVA_HOME="$PWD/$JRE_DIR"
            export PATH="$JAVA_HOME/bin:$PATH"
        fi
    fi
fi

ensure_java21

echo "Fetching packwiz-installer-bootstrap..."
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

echo "Server installation complete."
