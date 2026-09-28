#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# functions.sh sits beside this script when fetched standalone, or one level
# up when this script is run from the repo tools/ directory.
_rc_loaded=0
for _rc in "${SCRIPT_DIR}/functions.sh" "${SCRIPT_DIR}/../functions.sh"; do
    if [ -f "${_rc}" ]; then
        # shellcheck source=functions.sh
        . "${_rc}"
        _rc_loaded=1
        break
    fi
done
if [ "${_rc_loaded}" -ne 1 ]; then
    printf '%s\n' "ERROR: functions.sh not found next to or above this script." >&2
    exit 1
fi

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

# Nothing is installed with apt-get here any more. The egg's install container
# carries Java 21 and curl already, and an egg from before 0.12.10, which still
# installs on Debian, fetches curl itself before it fetches this script. tar and
# gzip are part of every Debian image.
ensure_supported_java

ensure_packwiz_bootstrap

MC_VERSION=${MC_VERSION:-1.20.1}
FORGE_VERSION=${FORGE_VERSION:-47.4.13}
SERVER_JARFILE=${SERVER_JARFILE:-server.jar}

if ! printf '%s\n' "${MC_VERSION}" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    die "MC_VERSION must be in the form x.y or x.y.z."
fi

if ! printf '%s\n' "${FORGE_VERSION}" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
    die "FORGE_VERSION must contain only digits and dots."
fi

validate_server_jarfile "SERVER_JARFILE" "${SERVER_JARFILE}"

# run.sh and run.bat come straight back from the installer, so clearing them is
# only tidiness. user_jvm_args.txt does not: the installer keeps an existing one
# across a reinstall, precisely so an operator's own flags survive, and
# startup.sh launches with it when it is there.
rm -f unix_args.txt run.sh run.bat

cleanup_forge() {
    rm -f installer.jar installer.jar.log
}
trap cleanup_forge 0 1 2 15

printf '%s\n' "Installing Forge ${MC_VERSION}-${FORGE_VERSION}..."
curl -sSfL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 120 \
    -o installer.jar \
    "https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${FORGE_VERSION}/forge-${MC_VERSION}-${FORGE_VERSION}-installer.jar"

java -jar installer.jar --installServer

# Copied, not symlinked. A panel's permissions pass, its SFTP layer and most
# backup tooling all treat symlinks differently from files, and losing this one
# leaves a server that cannot boot at all with no clue as to why. The file is a
# few hundred bytes.
ARGS_FILE="libraries/net/minecraftforge/forge/${MC_VERSION}-${FORGE_VERSION}/unix_args.txt"
if [ -f "${ARGS_FILE}" ]; then
    rm -f unix_args.txt
    cp "${ARGS_FILE}" unix_args.txt
    printf '%s\n' "Wrote unix_args.txt for Forge ${MC_VERSION}-${FORGE_VERSION}"
elif [ ! -f "${SERVER_JARFILE}" ]; then
    die "Forge installation produced neither unix_args.txt nor ${SERVER_JARFILE}."
fi

rm -f installer.jar installer.jar.log
trap - 0 1 2 15

PACKWIZ_URL=${PACKWIZ_URL:-https://packwiz.thunder.john.rooney.scot/pack.toml}
PACKWIZ_SIDE=${PACKWIZ_SIDE:-server}
PACKWIZ_EXTRA_FLAGS=${PACKWIZ_EXTRA_FLAGS:-}

case ${PACKWIZ_SIDE} in
    server|both)
        ;;
    *)
        die "PACKWIZ_SIDE must be 'server' or 'both'."
        ;;
esac

validate_packwiz_url "PACKWIZ_URL" "${PACKWIZ_URL}"

validate_extra_flags "PACKWIZ_EXTRA_FLAGS" "${PACKWIZ_EXTRA_FLAGS}"

printf '%s\n' "Syncing modpack via packwiz..."
# The bootstrap checks GitHub's releases API for a newer packwiz-installer on
# every run. That is the right default for a player, who has their own sixty
# requests an hour to spend, and the wrong one for CI, where a shared runner
# address routinely has none left and the 403 reads as a broken pack. Passing
# --bootstrap-no-update with a jar fetched beforehand is how CI opts out, and it
# needs this passthrough to do it; update.sh has had one all along.
if [ -n "${PACKWIZ_EXTRA_FLAGS}" ]; then
    set -f
    # shellcheck disable=SC2086
    set -- -g -s "${PACKWIZ_SIDE}" ${PACKWIZ_EXTRA_FLAGS} "${PACKWIZ_URL}"
    set +f
    java -jar packwiz-installer-bootstrap.jar "$@"
else
    java -jar packwiz-installer-bootstrap.jar -g -s "${PACKWIZ_SIDE}" "${PACKWIZ_URL}"
fi
ensure_executable_file "./startup.sh"
ensure_executable_file "./tools/update.sh"
printf '%s\n' "Server installation complete."
