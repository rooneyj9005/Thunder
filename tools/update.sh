#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# functions.sh sits beside this script when fetched standalone, or one level
# up when this script is run from the repo tools/ directory.
_rc_loaded=0
for _rc in "${SCRIPT_DIR}/functions.sh" "${SCRIPT_DIR}/../functions.sh"; do
    if [ -f "${_rc}" ]; then
        # shellcheck disable=SC1090,SC1091
        . "${_rc}"
        _rc_loaded=1
        break
    fi
done
if [ "${_rc_loaded}" -ne 1 ]; then
    printf '%s\n' "ERROR: functions.sh not found next to or above this script." >&2
    exit 1
fi

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
PACKWIZ_SIDE=${PACKWIZ_SIDE:-}
CLEAN_INSTALL=${CLEAN_INSTALL:-false}
PACKWIZ_EXTRA_FLAGS=${PACKWIZ_EXTRA_FLAGS:-}

case ${PACKWIZ_SIDE} in
    server|both)
        ;;
    "")
        die "PACKWIZ_SIDE must be set to 'server' or 'both'. This script syncs a Thunder server. Running it inside a client instance replaces your client mods with the server set."
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
