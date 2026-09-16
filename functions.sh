#!/bin/sh

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

ensure_executable_file() {
    path=$1

    [ -f "${path}" ] || die "Could not find '${path}'."

    if [ -x "${path}" ]; then
        return 0
    fi

    chmod +x -- "${path}" || die "Could not mark '${path}' as executable."
}

# The same, but a missing file is not an error. Used after a pack sync, which is
# allowed to move or rename the very scripts driving the upgrade: 0.12.1 moved
# update.sh into tools/ and the running startup.sh then died checking the path
# the sync had just removed.
mark_executable_if_present() {
    path=$1

    [ -f "${path}" ] || return 0
    [ -x "${path}" ] && return 0

    chmod +x -- "${path}" || die "Could not mark '${path}' as executable."
}

use_local_java21_if_available() {
    for java_dir in ./jdk-21* ./jre-21*; do
        [ -d "${java_dir}" ] || continue

        java_dir=${java_dir#./}
        JAVA_HOME=${PWD}/${java_dir}
        PATH=${JAVA_HOME}/bin:${PATH}
        export JAVA_HOME PATH
        printf '%s\n' "Using local Java 21 runtime at ${JAVA_HOME}"
        return 0
    done

    return 1
}

# Matches on ' version "' rather than the bare word, so a JAVA_TOOL_OPTIONS or
# _JAVA_OPTIONS banner, or an option value that happens to contain "version",
# cannot be read as the version string.
java_major_version() {
    java -version 2>&1 | awk -F '"' '/ version "/ { split($2, parts, "."); if (parts[1] == 1 && parts[2] != "") { print parts[2]; } else { print parts[1]; } exit }'
}

temurin_linux_arch() {
    arch=$(uname -m)

    case ${arch} in
        x86_64|amd64)
            printf '%s\n' "x64"
            ;;
        aarch64|arm64)
            printf '%s\n' "aarch64"
            ;;
        *)
            die "Unsupported Linux architecture for Temurin 21: ${arch}."
            ;;
    esac
}

install_local_java21() {
    arch=$(temurin_linux_arch)
    java_archive="temurin-21-${arch}.tar.gz"

    rm -f "${java_archive}"
    curl -sSfL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 300 \
        -o "${java_archive}" \
        "https://api.adoptium.net/v3/binary/latest/21/ga/linux/${arch}/jre/hotspot/normal/eclipse"
    tar -xzf "${java_archive}"
    rm -f "${java_archive}"

    if ! use_local_java21_if_available; then
        die "Temurin 21 archive did not contain an expected jdk-21* or jre-21* directory."
    fi
}

ensure_supported_java() {
    major=""

    if command -v java >/dev/null 2>&1; then
        major=$(java_major_version)
        case ${major} in
            17|21)
                return 0
                ;;
            *)
                :
                ;;
        esac
    fi

    if use_local_java21_if_available; then
        major=$(java_major_version)
        case ${major} in
            17|21)
                return 0
                ;;
            *)
                :
                ;;
        esac
    fi

    if [ -n "${major}" ]; then
        printf '%s\n' "Java ${major} found. Switching to local Temurin 21."
    else
        printf '%s\n' "No supported Java runtime found. Downloading local Temurin 21."
    fi

    install_local_java21
    major=$(java_major_version)

    [ "${major}" = "21" ] || die "Java 17 or Java 21 is required; found Java ${major:-unknown}."
}

# Wings sets a container's memory limit to the panel allocation times 1.05 at
# 4 GB and above, so the figure the panel advertises and the ceiling the kernel
# enforces are two different numbers. Sizing a heap against the advertised one
# and then being killed against the other is how a server disappears mid-session
# with nothing written to its log.
#
# Returns 1 when there is no container limit to read, which covers every
# non-Linux host, an unconstrained cgroup v2 whose memory.max is the word "max",
# and an unconstrained v1 whose limit_in_bytes is a number near 2^63.
cgroup_memory_limit_mib() {
    for limit_file in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
        [ -r "${limit_file}" ] || continue

        limit_bytes=$(cat "${limit_file}" 2>/dev/null) || continue
        case ${limit_bytes} in
            ''|*[!0-9]*)
                continue
                ;;
        esac

        limit_mib=$((limit_bytes / 1048576))

        # 4 TiB is not a container limit, it is the unconstrained sentinel.
        if [ "${limit_mib}" -lt 1 ] || [ "${limit_mib}" -gt 4194304 ]; then
            continue
        fi

        printf '%s\n' "${limit_mib}"
        return 0
    done

    return 1
}

# Everything outside the heap shares the same container. Metaspace alone runs
# 300 to 500 MB on a pack this size, and then there is the code cache, G1's card
# tables and remembered sets, thread stacks, Netty's direct buffers and
# allocator fragmentation on top. Aikar's guidance is 1000 to 1500 MB; the old
# total/20 reserve left 307 MiB at the memory this egg recommends.
heap_reserve_mib() {
    total=$1
    reserve=$((total * 15 / 100))

    if [ "${reserve}" -lt 1024 ]; then
        reserve=1024
    elif [ "${reserve}" -gt 2048 ]; then
        reserve=2048
    fi

    printf '%s\n' "${reserve}"
}

# Aikar's G1 flags, the reference tuning for a Minecraft server heap. Shipping
# them beats the JVM's defaults, which size the young generation for a
# throughput workload and pause a busy server long enough to be felt.
#
# AlwaysPreTouch is the one with teeth. It faults the whole heap in at boot
# instead of letting resident memory creep towards it over hours, so a heap that
# does not fit its container fails at start, in the open, rather than being
# killed quietly in the middle of a session.
jvm_gc_flags() {
    heap_mib=$1

    # Aikar splits the tuning at 12 GB: a large heap gets a bigger young
    # generation, larger regions, and starts collecting later.
    if [ -n "${heap_mib}" ] && [ "${heap_mib}" -ge 12288 ]; then
        new_size_percent=40
        max_new_size_percent=50
        heap_region_size=16M
        reserve_percent=15
        initiating_occupancy=20
    else
        new_size_percent=30
        max_new_size_percent=40
        heap_region_size=8M
        reserve_percent=20
        initiating_occupancy=15
    fi

    flags="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200"
    flags="${flags} -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC"
    flags="${flags} -XX:+AlwaysPreTouch -XX:+PerfDisableSharedMem"
    flags="${flags} -XX:G1NewSizePercent=${new_size_percent}"
    flags="${flags} -XX:G1MaxNewSizePercent=${max_new_size_percent}"
    flags="${flags} -XX:G1HeapRegionSize=${heap_region_size}"
    flags="${flags} -XX:G1ReservePercent=${reserve_percent}"
    flags="${flags} -XX:InitiatingHeapOccupancyPercent=${initiating_occupancy}"
    flags="${flags} -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4"
    flags="${flags} -XX:G1MixedGCLiveThresholdPercent=90"
    flags="${flags} -XX:G1RSetUpdatingPauseTimePercent=5"
    flags="${flags} -XX:SurvivorRatio=32 -XX:MaxTenuringThreshold=1"
    flags="${flags} -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

    # An exhausted heap otherwise means the collector thrashing for as long as
    # it takes, which reads as a hang rather than a failure. Exiting leaves the
    # panel an exit code and the log a reason.
    flags="${flags} -XX:+ExitOnOutOfMemoryError"

    printf '%s\n' "${flags}"
}

# Rewrites one key in a Java .properties file and keeps every other line,
# comments included, exactly as it was. The key is a literal from the calling
# script, so it is safe inside the grep pattern. The value never reaches a
# shell or sed, so / and & in it are safe too. A missing file is created with
# just this key; the mod fills in its defaults on the next load.
set_properties_key() {
    properties_file=$1
    properties_key=$2
    properties_value=$3

    if [ -f "${properties_file}" ]; then
        grep -v "^${properties_key}=" "${properties_file}" > "${properties_file}.new" || true
    else
        : > "${properties_file}.new"
    fi

    printf '%s=%s\n' "${properties_key}" "${properties_value}" >> "${properties_file}.new"
    mv "${properties_file}.new" "${properties_file}"
}

# True when the file holds exactly key=value on its own line.
properties_key_equals() {
    properties_file=$1
    properties_key=$2
    properties_value=$3

    [ -f "${properties_file}" ] || return 1
    grep -qxF "${properties_key}=${properties_value}" "${properties_file}"
}

validate_boolean_value() {
    name=$1
    value=$2

    case ${value} in
        true|1|yes|false|0|no|"")
            return 0
            ;;
        *)
            die "${name} must be one of: true, false, 1, 0, yes, or no."
            ;;
    esac
}

# Over plaintext an attacker on the path controls the index and the hashes that
# index is checked against, so hash verification proves nothing about what ends
# up in mods/. The only host that legitimately serves the pack over http is the
# local one in tests/ and CI, and that sets PACKWIZ_ALLOW_INSECURE_URL to say
# so. A real install has no reason to.
validate_packwiz_url() {
    name=$1
    value=$2

    if printf '%s\n' "${value}" | grep -Eq '[[:space:]]'; then
        die "${name} must not contain whitespace."
    fi

    case ${PACKWIZ_ALLOW_INSECURE_URL:-} in
        1|true|yes)
            return 0
            ;;
    esac

    case ${value} in
        https://*)
            return 0
            ;;
        *)
            die "${name} must be an https:// URL. Set PACKWIZ_ALLOW_INSECURE_URL=1 to allow a plaintext host, which is only safe for a local test."
            ;;
    esac
}

# SERVER_JARFILE names a file in the server directory, not a path to one. The
# egg's own rule already refuses anything else from a panel, so this is what
# covers a standalone run, where the value reaches a java -jar argument with
# nothing between it and the shell.
validate_server_jarfile() {
    name=$1
    value=$2

    if ! printf '%s\n' "${value}" | grep -Eq '^[A-Za-z0-9._-]+\.jar$'; then
        die "${name} must be a simple .jar filename."
    fi
}

validate_non_negative_mib() {
    name=$1
    value=$2

    [ -n "${value}" ] || return 0

    case ${value} in
        *[!0-9]*|"")
            die "${name} must be a non-negative integer in MiB."
            ;;
        *)
            return 0
            ;;
    esac
}

# Operator-supplied flag strings reach a command line, so the allowlist is a
# deliberate floor rather than a filter: letters, numbers, spaces and the
# punctuation a JVM or packwiz flag actually needs. Everything a shell would
# act on, quotes and globs included, is refused by name rather than escaped.
validate_extra_flags() {
    name=$1
    value=$2

    [ -n "${value}" ] || return 0

    if printf '%s\n' "${value}" | grep -Eq '[^[:alnum:].,/:=_+ -]'; then
        die "${name} may only contain letters, numbers, spaces, and the characters . , / : = _ + -."
    fi
}
