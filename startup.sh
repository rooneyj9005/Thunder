#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/functions.sh"

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
PACKWIZ_AUTO_UPDATE=${PACKWIZ_AUTO_UPDATE:-false}
PACKWIZ_SIDE=${PACKWIZ_SIDE:-server}
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
validate_boolean_value "PACKWIZ_AUTO_UPDATE" "${PACKWIZ_AUTO_UPDATE}"
ENABLE_VOICE_CHAT=${ENABLE_VOICE_CHAT:-true}
validate_boolean_value "ENABLE_VOICE_CHAT" "${ENABLE_VOICE_CHAT}"

case ${PACKWIZ_AUTO_UPDATE} in
    true|1|yes) SYNC_ON_START=true ;;
    *)          SYNC_ON_START=false ;;
esac

# Wiping the mod set is only safe when something is going to put it back. These
# used to be independent, so CLEAN_INSTALL with sync switched off deleted every
# mod and then declined to re-download them, leaving a modded world to load
# against no mods at all.
case ${CLEAN_INSTALL} in
    true|1|yes)
        if [ "${SYNC_ON_START}" = "false" ]; then
            die "CLEAN_INSTALL wipes the mod set but PACKWIZ_AUTO_UPDATE is off, so nothing would reinstall it. Switch Auto Update on for this start, or switch Clean Install off."
        fi
        printf '%s\n' "Clean install - wiping mods and packwiz config..."
        rm -rf mods config/packwiz-installer.toml
        ;;
    *)
        :
        ;;
esac

if [ "${SYNC_ON_START}" = "true" ]; then
    UPDATE_SCRIPT=${SCRIPT_DIR}/tools/update.sh
    ensure_executable_file "${UPDATE_SCRIPT}"
    CURRENT_DIR=$(pwd)
    PACKWIZ_SIDE="${PACKWIZ_SIDE}" "${UPDATE_SCRIPT}" --dir "${CURRENT_DIR}"

    # A sync may have moved or renamed these, so a missing one is not fatal.
    mark_executable_if_present "${SCRIPT_DIR}/startup.sh"
    mark_executable_if_present "${UPDATE_SCRIPT}"
else
    printf '%s\n' "Skipping packwiz sync. Set PACKWIZ_AUTO_UPDATE=true to sync on every start."
fi

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

# Simple Voice Chat keeps its server settings in a .properties file that the mod
# rewrites with every key on load. Only the keys below are touched, so operator
# edits to the rest of the file survive a restart. Disabling voice chat binds the
# UDP listener to loopback instead of deleting the file, which would only make
# the mod regenerate its defaults and listen on every interface again.
VOICE_CONFIG_FILE=config/voicechat/voicechat-server.properties
mkdir -p config/voicechat
case ${ENABLE_VOICE_CHAT} in
    true|1|yes)
        VOICE_ENABLED=true
        ;;
    *)
        VOICE_ENABLED=false
        ;;
esac
if [ "${VOICE_PORT}" = "0" ]; then
    VOICE_ENABLED=false
fi

if [ "${VOICE_ENABLED}" = "true" ]; then
    set_properties_key "${VOICE_CONFIG_FILE}" port "${VOICE_PORT}"
    # shellcheck disable=SC2310
    if properties_key_equals "${VOICE_CONFIG_FILE}" bind_address 127.0.0.1; then
        printf '%s\n' "Voice chat re-enabled. Clearing the loopback bind_address so it listens on every interface again."
        set_properties_key "${VOICE_CONFIG_FILE}" bind_address ""
    fi
    printf '%s\n' "Simple Voice Chat listens on UDP port ${VOICE_PORT}."
else
    set_properties_key "${VOICE_CONFIG_FILE}" bind_address 127.0.0.1
    printf '%s\n' "Voice chat disabled. Simple Voice Chat is bound to 127.0.0.1 and is not reachable from outside."
fi

# Checked before the launcher, because a world loaded against no mods is the
# failure that costs something. A modded world with no mods either refuses to
# start or, worse, loads and strips every modded block on the first save.
if [ -d world ] &&
    [ -z "$(find mods -maxdepth 1 -name '*.jar' -print -quit 2>/dev/null)" ]; then
    die "world/ exists but mods/ holds no jars. Starting would risk stripping the world. Set PACKWIZ_AUTO_UPDATE=true and restart to reinstall the mod set."
fi

# unix_args.txt is what a Forge server launches from, and only the installer
# writes it, so a server that loses it cannot boot and cannot repair itself.
# Forge keeps its own copy under libraries/, so take that rather than making an
# operator reinstall over a missing few hundred bytes.
if [ ! -f unix_args.txt ]; then
    FORGE_ARGS=$(find libraries/net/minecraftforge/forge -name unix_args.txt -type f 2>/dev/null | sed -n '1p')
    if [ -n "${FORGE_ARGS}" ]; then
        cp "${FORGE_ARGS}" unix_args.txt
        printf '%s\n' "Restored unix_args.txt from ${FORGE_ARGS}"
    fi
fi

# Falling through to "-jar server.jar" on a Forge install reports the missing
# jar, which is not the problem and sends you looking in the wrong place.
if [ ! -f unix_args.txt ] && [ ! -f "${SERVER_JARFILE:-server.jar}" ]; then
    die "No Forge launch arguments and no ${SERVER_JARFILE:-server.jar}, so there is nothing to start. Reinstall the server to install Forge."
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
