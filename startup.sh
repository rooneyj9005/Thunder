#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/runtime-common.sh"

SERVER_DIR=""
TOTAL_MEMORY_MIB=""
JVM_MEMORY_MIB=""
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
        --memory)
            [ -n "${2:-}" ] || die "--memory requires a MiB value."
            TOTAL_MEMORY_MIB=$2
            shift 2
            ;;
        --jvm-memory)
            [ -n "${2:-}" ] || die "--jvm-memory requires a MiB value."
            JVM_MEMORY_MIB=$2
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

CLEAN_INSTALL=${CLEAN_INSTALL:-false}
PACKWIZ_SKIP_UPDATE=${PACKWIZ_SKIP_UPDATE:-false}
if [ -z "${TOTAL_MEMORY_MIB}" ] && [ -n "${SERVER_MEMORY:-}" ]; then
    TOTAL_MEMORY_MIB=${SERVER_MEMORY}
fi
if [ -z "${JVM_MEMORY_MIB}" ] && [ -n "${JVM_MEMORY:-}" ]; then
    JVM_MEMORY_MIB=${JVM_MEMORY}
fi

auto_heap_from_total_memory() {
    total=$1
    reserve=$((total / 20))

    if [ "${reserve}" -lt 256 ]; then
        reserve=256
    elif [ "${reserve}" -gt 1024 ]; then
        reserve=1024
    fi

    heap=$((total - reserve))
    if [ "${heap}" -lt 512 ]; then
        die "--memory ${total} does not leave enough room for a safe heap after JVM overhead. Use at least 768 MiB or set --jvm-memory explicitly."
    fi

    printf '%s\n' "${heap}"
}

build_java_memory_args() {
    validate_non_negative_mib "--memory" "${TOTAL_MEMORY_MIB}"
    validate_non_negative_mib "--jvm-memory" "${JVM_MEMORY_MIB}"

    if [ -n "${JVM_MEMORY_MIB}" ] && [ "${JVM_MEMORY_MIB}" != "0" ]; then
        if [ -n "${TOTAL_MEMORY_MIB}" ] &&
            [ "${TOTAL_MEMORY_MIB}" != "0" ] &&
            [ "${JVM_MEMORY_MIB}" -ge "${TOTAL_MEMORY_MIB}" ]; then
            printf '%s\n' "WARNING: --jvm-memory ${JVM_MEMORY_MIB} MiB is at least the full advertised server memory of ${TOTAL_MEMORY_MIB} MiB. This leaves no headroom for native JVM or container overhead." >&2
        fi

        JAVA_MEMORY_MODE="exact"
        JAVA_MEMORY_VALUE=${JVM_MEMORY_MIB}
        printf '%s\n' "Using exact JVM heap of ${JVM_MEMORY_MIB} MiB."
        return
    fi

    if [ -n "${TOTAL_MEMORY_MIB}" ] && [ "${TOTAL_MEMORY_MIB}" != "0" ]; then
        auto_heap=$(auto_heap_from_total_memory "${TOTAL_MEMORY_MIB}")
        JAVA_MEMORY_MODE="exact"
        JAVA_MEMORY_VALUE=${auto_heap}
        printf '%s\n' "Using automatic JVM heap of ${auto_heap} MiB from ${TOTAL_MEMORY_MIB} MiB total server memory."
        return
    fi

    JAVA_MEMORY_MODE="percentage"
    JAVA_MEMORY_VALUE="95.0"
}

build_java_memory_args
validate_boolean_value "CLEAN_INSTALL" "${CLEAN_INSTALL}"
validate_boolean_value "PACKWIZ_SKIP_UPDATE" "${PACKWIZ_SKIP_UPDATE}"

case ${PACKWIZ_SKIP_UPDATE} in
    true|1|yes)
        case ${CLEAN_INSTALL} in
            true|1|yes)
                printf '%s\n' "Clean install - wiping mods and packwiz config..."
                rm -rf mods config/packwiz-installer.toml
                ;;
            *)
                :
                ;;
        esac
        printf '%s\n' "Skipping packwiz sync (PACKWIZ_SKIP_UPDATE enabled)."
        ;;
    *)
        UPDATE_SCRIPT=${SCRIPT_DIR}/update.sh
        [ -f "${UPDATE_SCRIPT}" ] || die "Could not find '${UPDATE_SCRIPT}'."
        CURRENT_DIR=$(pwd)
        "${UPDATE_SCRIPT}" --dir "${CURRENT_DIR}"
        ;;
esac

VOICE_PORT=${VOICE_PORT:-24454}
case ${VOICE_PORT} in
    *[!0-9]*|"")
        die "VOICE_PORT must be an integer between 0 and 65535 (0 to disable)."
        ;;
    *)
        :
        ;;
esac

if [ "${VOICE_PORT}" -gt 65535 ]; then
    die "VOICE_PORT must be an integer between 0 and 65535 (0 to disable)."
fi

if [ "${VOICE_PORT}" != "0" ]; then
    mkdir -p config/voicechat
    printf '%s\n' "port=${VOICE_PORT}" > config/voicechat/voicechat-server.properties
fi

if [ "${JAVA_MEMORY_MODE}" = "exact" ]; then
    if [ -f unix_args.txt ]; then
        exec java -Xms"${JAVA_MEMORY_VALUE}M" -Xmx"${JAVA_MEMORY_VALUE}M" @unix_args.txt
    fi

    exec java -Xms"${JAVA_MEMORY_VALUE}M" -Xmx"${JAVA_MEMORY_VALUE}M" -jar "${SERVER_JARFILE:-server.jar}"
fi

if [ -f unix_args.txt ]; then
    exec java -Xms128M -XX:MaxRAMPercentage="${JAVA_MEMORY_VALUE}" @unix_args.txt
fi

exec java -Xms128M -XX:MaxRAMPercentage="${JAVA_MEMORY_VALUE}" -jar "${SERVER_JARFILE:-server.jar}"
