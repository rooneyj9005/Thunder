#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/runtime-common.sh"

MODE="server"
INSTALL_DIR=""
while [ "$#" -gt 0 ]; do
    case $1 in
        --container)
            MODE="container"
            shift
            ;;
        --dir)
            [ -n "${2:-}" ] || die "--dir requires a path argument."
            INSTALL_DIR=$2
            shift 2
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

TARGET_DIR=${PWD}
if [ "${MODE}" = "container" ]; then
    TARGET_DIR=${INSTALL_DIR:-/mnt/server}
elif [ -n "${INSTALL_DIR}" ]; then
    TARGET_DIR=${INSTALL_DIR}
fi

cd "${TARGET_DIR}"

if [ "${MODE}" = "container" ]; then
    apt-get -q update
    apt-get install -y --no-install-recommends curl ca-certificates jq tar gzip
fi

ensure_supported_java

printf '%s\n' "Fetching packwiz-installer-bootstrap..."
curl -sSfL --connect-timeout 30 --max-time 120 \
    -o packwiz-installer-bootstrap.jar \
    "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"
printf '%s\n' "Downloaded packwiz-installer-bootstrap.jar"

MODLOADER=${MODLOADER:-forge}
MC_VERSION=${MC_VERSION:-1.20.1}
if [ "${MODLOADER}" = "forge" ]; then
    FORGE_VERSION=${FORGE_VERSION:-47.4.13}
else
    FORGE_VERSION=${FORGE_VERSION:-}
fi
SERVER_JARFILE=${SERVER_JARFILE:-server.jar}

case ${MODLOADER} in
    forge|fabric|quilt)
        ;;
    *)
        die "MODLOADER must be 'forge', 'fabric', or 'quilt'."
        ;;
esac

if ! printf '%s\n' "${MC_VERSION}" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    die "MC_VERSION must be in the form x.y or x.y.z."
fi

if [ -n "${FORGE_VERSION}" ] &&
    ! printf '%s\n' "${FORGE_VERSION}" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
    die "FORGE_VERSION must contain only digits and dots."
fi

if ! printf '%s\n' "${SERVER_JARFILE}" | grep -Eq '^[A-Za-z0-9._-]+\.jar$'; then
    die "SERVER_JARFILE must be a simple .jar filename."
fi

if { [ "${MODLOADER}" = "forge" ] && [ -z "${FORGE_VERSION}" ]; } ||
    [ "${MODLOADER}" = "fabric" ] ||
    [ "${MODLOADER}" = "quilt" ]; then
    command -v jq >/dev/null 2>&1 || die "jq is required to resolve loader versions automatically."
fi

case ${MODLOADER} in
    forge)
        rm -f unix_args.txt user_jvm_args.txt run.sh run.bat

        cleanup_forge() {
            rm -f installer.jar installer.jar.log
        }
        trap cleanup_forge 0 1 2 15

        RESOLVED_VERSION=${FORGE_VERSION}
        if [ -z "${RESOLVED_VERSION}" ]; then
            JSON_DATA=$(curl -sSfL --connect-timeout 30 --max-time 30 \
                "https://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json")
            RESOLVED_VERSION=$(printf '%s\n' "${JSON_DATA}" | jq -r \
                ".promos[\"${MC_VERSION}-recommended\"] // .promos[\"${MC_VERSION}-latest\"]")
            if [ -z "${RESOLVED_VERSION}" ] || [ "${RESOLVED_VERSION}" = "null" ]; then
                die "No Forge version found for Minecraft ${MC_VERSION}."
            fi
        fi

        printf '%s\n' "Installing Forge ${MC_VERSION}-${RESOLVED_VERSION}..."
        curl -sSfL --connect-timeout 30 --max-time 120 \
            -o installer.jar \
            "https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${RESOLVED_VERSION}/forge-${MC_VERSION}-${RESOLVED_VERSION}-installer.jar"

        java -jar installer.jar --installServer

        ARGS_FILE="libraries/net/minecraftforge/forge/${MC_VERSION}-${RESOLVED_VERSION}/unix_args.txt"
        if [ -f "${ARGS_FILE}" ]; then
            ln -sf "${ARGS_FILE}" unix_args.txt
            printf '%s\n' "Linked unix_args.txt for Forge ${MC_VERSION}-${RESOLVED_VERSION}"
        elif [ ! -f "${SERVER_JARFILE}" ]; then
            die "Forge installation produced neither unix_args.txt nor ${SERVER_JARFILE}."
        fi

        rm -f installer.jar installer.jar.log
        trap - 0 1 2 15
        ;;

    fabric)
        if [ -n "${FORGE_VERSION}" ]; then
            FABRIC_LOADER=${FORGE_VERSION}
        else
            FABRIC_LOADER=$(curl -sSfL --connect-timeout 30 --max-time 30 \
                "https://meta.fabricmc.net/v2/versions/loader" | jq -r '.[0].version')
        fi
        FABRIC_INSTALLER=$(curl -sSfL --connect-timeout 30 --max-time 30 \
            "https://meta.fabricmc.net/v2/versions/installer" | jq -r '.[0].version')

        printf '%s\n' "Installing Fabric Loader ${FABRIC_LOADER} for Minecraft ${MC_VERSION}..."

        cleanup_fabric() {
            rm -f "${SERVER_JARFILE}.tmp"
        }
        trap cleanup_fabric 0 1 2 15

        curl -sSfL --connect-timeout 30 --max-time 120 \
            -o "${SERVER_JARFILE}.tmp" \
            "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${FABRIC_LOADER}/${FABRIC_INSTALLER}/server/jar"
        mv "${SERVER_JARFILE}.tmp" "${SERVER_JARFILE}"

        trap - 0 1 2 15
        ;;

    quilt)
        if [ -n "${FORGE_VERSION}" ]; then
            QUILT_LOADER=${FORGE_VERSION}
        else
            QUILT_LOADER=$(curl -sSfL --connect-timeout 30 --max-time 30 \
                "https://meta.quiltmc.org/v3/versions/loader" | jq -r '.[0].version')
        fi
        QUILT_INSTALLER=$(curl -sSfL --connect-timeout 30 --max-time 30 \
            "https://meta.quiltmc.org/v3/versions/installer" | jq -r '.[0].version')

        printf '%s\n' "Installing Quilt Loader ${QUILT_LOADER} for Minecraft ${MC_VERSION}..."

        cleanup_quilt() {
            rm -f "${SERVER_JARFILE}.tmp"
        }
        trap cleanup_quilt 0 1 2 15

        curl -sSfL --connect-timeout 30 --max-time 120 \
            -o "${SERVER_JARFILE}.tmp" \
            "https://meta.quiltmc.org/v3/versions/loader/${MC_VERSION}/${QUILT_LOADER}/${QUILT_INSTALLER}/server/jar"
        mv "${SERVER_JARFILE}.tmp" "${SERVER_JARFILE}"

        trap - 0 1 2 15
        ;;

    *)
        die "Unknown modloader '${MODLOADER}'. Expected: forge, fabric, or quilt."
        ;;
esac

PACKWIZ_URL=${PACKWIZ_URL:-https://packwiz.thunder.john.rooney.scot/pack.toml}
PACKWIZ_SIDE=${PACKWIZ_SIDE:-server}

case ${PACKWIZ_SIDE} in
    server|both)
        ;;
    *)
        die "PACKWIZ_SIDE must be 'server' or 'both'."
        ;;
esac

if printf '%s\n' "${PACKWIZ_URL}" | grep -Eq '[[:space:]]'; then
    die "PACKWIZ_URL must not contain whitespace."
fi

printf '%s\n' "Syncing modpack via packwiz..."
java -jar packwiz-installer-bootstrap.jar -g -s "${PACKWIZ_SIDE}" "${PACKWIZ_URL}"
ensure_executable_file "./startup.sh"
ensure_executable_file "./update.sh"
printf '%s\n' "Server installation complete."
