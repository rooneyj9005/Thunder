#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/functions.sh"

SERVER_DIR=""
TOTAL_MEMORY_MIB=""
JVM_MEMORY_MIB=""
IN_CONTAINER=false
while [ "$#" -gt 0 ]; do
    case $1 in
        --container)
            IN_CONTAINER=true
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
PACKWIZ_SIDE=${PACKWIZ_SIDE:-server}
JVM_EXTRA_FLAGS=${JVM_EXTRA_FLAGS:-}

# A panel does not add new egg variables to servers that already exist, so a
# server created before PACKWIZ_AUTO_UPDATE was introduced has no way to set it,
# and those servers synced on every boot. Reading an absent variable as "off"
# would quietly mean they never receive a pack update again, with nothing in
# their panel able to change that.
#
# Absent under --container therefore means a panel older than the variable, and
# keeps the old behaviour. Every current egg sets it explicitly, so a deliberate
# "false" is still honoured, and a standalone run without it gets the documented
# opt-in default.
if [ -z "${PACKWIZ_AUTO_UPDATE+set}" ] && [ "${IN_CONTAINER}" = "true" ]; then
    PACKWIZ_AUTO_UPDATE=true
    printf '%s\n' "PACKWIZ_AUTO_UPDATE is not set by this egg, so syncing on start as this server always has. Re-import pterodactyl.json to control it."
else
    PACKWIZ_AUTO_UPDATE=${PACKWIZ_AUTO_UPDATE:-false}
fi
if [ -z "${TOTAL_MEMORY_MIB}" ] && [ -n "${SERVER_MEMORY:-}" ]; then
    TOTAL_MEMORY_MIB=${SERVER_MEMORY}
fi
if [ -z "${JVM_MEMORY_MIB}" ] && [ -n "${JVM_MEMORY:-}" ]; then
    JVM_MEMORY_MIB=${JVM_MEMORY}
fi

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
        budget=${TOTAL_MEMORY_MIB}

        # The kernel enforces the container limit; the panel figure is only what
        # the operator was quoted. Size against the ceiling that can actually
        # kill the process. A limit more than twice the advertised figure is a
        # parent cgroup rather than this server's, so it is ignored.
        if cgroup_mib=$(cgroup_memory_limit_mib) &&
            [ "${cgroup_mib}" -le "$((budget * 2))" ]; then
            if [ "${cgroup_mib}" != "${budget}" ]; then
                printf '%s\n' "Container memory limit is ${cgroup_mib} MiB against a ${budget} MiB allocation. Sizing the heap against the limit."
            fi
            budget=${cgroup_mib}
        fi

        reserve=$(heap_reserve_mib "${budget}")
        auto_heap=$((budget - reserve))
        if [ "${auto_heap}" -lt 512 ]; then
            die "${budget} MiB does not leave enough room for a safe heap once ${reserve} MiB is reserved for JVM and container overhead. Allocate at least 1536 MiB, or set --jvm-memory to pick the heap yourself."
        fi

        JAVA_MEMORY_MODE="exact"
        JAVA_MEMORY_VALUE=${auto_heap}
        printf '%s\n' "Using automatic JVM heap of ${auto_heap} MiB, holding ${reserve} MiB of ${budget} MiB back for JVM and container overhead."
        return
    fi

    # Nothing said how much memory this server has. MaxRAMPercentage reads the
    # container limit where there is one and physical memory otherwise, so it is
    # the shape that behaves on both. It was 95 per cent, which on a shared
    # machine is a heap free to grow over almost all of it, and paired with
    # -Xms128M gave exactly the slow creep towards the ceiling that AlwaysPreTouch
    # is here to stop.
    JAVA_MEMORY_MODE="percentage"
    JAVA_MEMORY_VALUE="75"
}

build_java_memory_args
validate_boolean_value "CLEAN_INSTALL" "${CLEAN_INSTALL}"
validate_boolean_value "PACKWIZ_AUTO_UPDATE" "${PACKWIZ_AUTO_UPDATE}"
ENABLE_VOICE_CHAT=${ENABLE_VOICE_CHAT:-true}
validate_boolean_value "ENABLE_VOICE_CHAT" "${ENABLE_VOICE_CHAT}"
validate_extra_flags "JVM_EXTRA_FLAGS" "${JVM_EXTRA_FLAGS}"

case ${PACKWIZ_AUTO_UPDATE} in
    true|1|yes) SYNC_ON_START=true ;;
    *)          SYNC_ON_START=false ;;
esac

# Wiping the mod set is only safe when something is going to put it back. These
# used to be independent, so CLEAN_INSTALL with sync switched off deleted every
# mod and then declined to re-download them, leaving a modded world to load
# against no mods at all.
#
# A clean install is an install, so it turns the sync on for this start rather
# than refusing. Refusing would strand every server built from an egg older than
# PACKWIZ_AUTO_UPDATE: those panels have CLEAN_INSTALL and no way to add the new
# variable, so there would be no setting available to get the server booting.
case ${CLEAN_INSTALL} in
    true|1|yes)
        if [ "${SYNC_ON_START}" = "false" ]; then
            printf '%s\n' "Clean install requested, so syncing this start even though PACKWIZ_AUTO_UPDATE is off."
            SYNC_ON_START=true
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
#
# Which copy matters. Once a Forge bump leaves two versions installed, the first
# find hit is filesystem order, and the wrong one boots the server against
# libraries it was not built for. Take the version this server is configured
# for, and refuse to guess when nothing says which.
restore_unix_args() {
    if [ -n "${MC_VERSION:-}" ] && [ -n "${FORGE_VERSION:-}" ]; then
        pinned="libraries/net/minecraftforge/forge/${MC_VERSION}-${FORGE_VERSION}/unix_args.txt"
        if [ -f "${pinned}" ]; then
            cp "${pinned}" unix_args.txt
            printf '%s\n' "Restored unix_args.txt from ${pinned}"
            return 0
        fi
    fi

    candidates=$(find libraries/net/minecraftforge/forge -name unix_args.txt -type f 2>/dev/null)
    [ -n "${candidates}" ] || return 0

    count=$(printf '%s\n' "${candidates}" | wc -l)
    count=$((count))
    if [ "${count}" -ne 1 ]; then
        die "unix_args.txt is missing from the server root and ${count} Forge versions are installed under libraries/, so there is nothing to say which one this server runs. Set MC_VERSION and FORGE_VERSION, or re-run tools/install.sh to repair the install."
    fi

    cp "${candidates}" unix_args.txt
    printf '%s\n' "Restored unix_args.txt from ${candidates}"
}

if [ ! -f unix_args.txt ]; then
    restore_unix_args
fi

# Falling through to "-jar server.jar" on a Forge install reports the missing
# jar, which is not the problem and sends you looking in the wrong place.
if [ ! -f unix_args.txt ] && [ ! -f "${SERVER_JARFILE:-server.jar}" ]; then
    die "No Forge launch arguments and no ${SERVER_JARFILE:-server.jar}, so there is nothing to start. Reinstall the server to install Forge."
fi

set --

if [ "${JAVA_MEMORY_MODE}" = "exact" ]; then
    set -- "$@" "-Xms${JAVA_MEMORY_VALUE}M" "-Xmx${JAVA_MEMORY_VALUE}M"
    GC_HEAP_MIB=${JAVA_MEMORY_VALUE}
else
    set -- "$@" "-XX:InitialRAMPercentage=${JAVA_MEMORY_VALUE}" "-XX:MaxRAMPercentage=${JAVA_MEMORY_VALUE}"
    GC_HEAP_MIB=""
fi

GC_FLAGS=$(jvm_gc_flags "${GC_HEAP_MIB}")
set -f
# shellcheck disable=SC2086
set -- "$@" ${GC_FLAGS}
set +f

# The Forge installer writes user_jvm_args.txt on every --installServer and
# keeps an existing one across a reinstall, which makes it the one place an
# operator can leave a flag and have it survive. Later flags win, so what is in
# here overrides the defaults above.
if [ -f user_jvm_args.txt ]; then
    set -- "$@" "@user_jvm_args.txt"
    printf '%s\n' "Reading extra JVM flags from user_jvm_args.txt."
fi

# The panel field, for operators with no way to edit a file. Last, so it beats
# both the defaults and user_jvm_args.txt.
if [ -n "${JVM_EXTRA_FLAGS}" ]; then
    set -f
    # shellcheck disable=SC2086
    set -- "$@" ${JVM_EXTRA_FLAGS}
    set +f
    printf '%s\n' "Adding JVM_EXTRA_FLAGS: ${JVM_EXTRA_FLAGS}"
fi

# nogui is a server argument rather than a JVM one, so it goes last. Without it
# the dedicated server opens its Swing console on any host with a display, which
# is every standalone Linux desktop; inside the container it is headless by
# accident rather than by instruction.
if [ -f unix_args.txt ]; then
    exec java "$@" "@unix_args.txt" nogui
fi

exec java "$@" -jar "${SERVER_JARFILE:-server.jar}" nogui
