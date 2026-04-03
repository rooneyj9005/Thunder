#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/runtime-common.sh"

SERVER_DIR=""
while [ "$#" -gt 0 ]; do
    case $1 in
        --container)
            shift
            ;;
        --dir)
            [ -n "${2:-}" ] || die "--dir requires a path argument."
            SERVER_DIR=$2
            shift 2
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [ -n "${SERVER_DIR}" ]; then
    cd "${SERVER_DIR}"
fi

ensure_supported_java

PACKWIZ_URL=${PACKWIZ_URL:-https://packwiz.thunder.john.rooney.scot/pack.toml}
PACKWIZ_SIDE=${PACKWIZ_SIDE:-server}
CLEAN_INSTALL=${CLEAN_INSTALL:-false}
PACKWIZ_EXTRA_FLAGS=${PACKWIZ_EXTRA_FLAGS:-}

case ${PACKWIZ_SIDE} in
    server|both)
        ;;
    *)
        die "PACKWIZ_SIDE must be 'server' or 'both'."
        ;;
esac

validate_boolean_value "CLEAN_INSTALL" "${CLEAN_INSTALL}"

if printf '%s\n' "${PACKWIZ_URL}" | grep -Eq '[[:space:]]'; then
    die "PACKWIZ_URL must not contain whitespace."
fi

if [ -n "${PACKWIZ_EXTRA_FLAGS}" ] &&
    printf '%s\n' "${PACKWIZ_EXTRA_FLAGS}" | grep -Eq '[^[:alnum:].,/:=_+ -]'; then
    die "PACKWIZ_EXTRA_FLAGS may only contain letters, numbers, spaces, and the characters . , / : = _ + -."
fi

case ${CLEAN_INSTALL} in
    true|1|yes)
        printf '%s\n' "Clean install - wiping mods and packwiz config..."
        rm -rf mods config/packwiz-installer.toml
        ;;
    *)
        :
        ;;
esac

if [ ! -f packwiz-installer-bootstrap.jar ]; then
    printf '%s\n' "packwiz-installer-bootstrap.jar not found, downloading latest release..."
    curl -sSfL --connect-timeout 30 --max-time 120 \
        -o packwiz-installer-bootstrap.jar \
        "https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar"
fi

printf '%s\n' "Syncing modpack via packwiz..."
if [ -n "${PACKWIZ_EXTRA_FLAGS}" ]; then
    set -f
    # shellcheck disable=SC2086
    set -- -g -s "${PACKWIZ_SIDE}" ${PACKWIZ_EXTRA_FLAGS} "${PACKWIZ_URL}"
    set +f
    exec java -jar packwiz-installer-bootstrap.jar "$@"
fi

exec java -jar packwiz-installer-bootstrap.jar -g -s "${PACKWIZ_SIDE}" "${PACKWIZ_URL}"
