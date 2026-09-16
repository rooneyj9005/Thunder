#!/bin/sh
# Shared plumbing for tests/server.sh and tests/client.sh.
#
# Both drivers do the same four things in the same order: work out where the
# pack metadata comes from, build and run one container, watch it from the
# outside until it either proves itself or stops, and collect every log it
# produced into a zip that outlives the container. That is what lives here.
#
# Sourced, never executed. The caller sets ROLE before sourcing.

TESTS_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd "${TESTS_DIR}/.." && pwd)
ARTIFACT_DIR="${ROOT_DIR}/tmp/tests"
HELPER_IMAGE=python:3.12-alpine
PACK_HOST_PORT="${THUNDER_PACK_HOST_PORT:-8123}"

POLL_INTERVAL=5
HEARTBEAT_INTERVAL=30

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

say() {
    printf '%s\n' "$*"
}

banner() {
    printf '\n%s\n%s\n%s\n' \
        "===================================================================" \
        "$1" \
        "==================================================================="
}

# Git Bash rewrites anything that looks like a Unix path before handing it to
# docker.exe, which mangles container paths and volume specs. Turned off here
# for every docker call.
dk() {
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"
}

# The other half of turning that conversion off: host paths now have to be
# converted here, because docker.exe cannot resolve /c/Users/... itself. The
# mixed form (C:/Users/...) keeps forward slashes, so it needs no escaping and
# still parses correctly on the host side of a -v spec. A no-op off Windows.
host_path() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s\n' "$1"
    fi
}

require_docker() {
    command -v docker >/dev/null 2>&1 ||
        die "docker is not on PATH. Install Docker Desktop, or start it if it is already installed."
    dk info >/dev/null 2>&1 ||
        die "The Docker engine is not answering. Is Docker Desktop running?"
}

docker_memory_mib() {
    mem_bytes=$(dk info --format '{{.MemTotal}}' 2>/dev/null || true)
    case ${mem_bytes} in
        ''|*[!0-9]*)
            die "Could not ask the Docker engine how much memory it has."
            ;;
    esac
    printf '%s\n' "$((mem_bytes / 1048576))"
}

# The container ceiling has to cover the heap plus the JVM's own native memory.
# Then the kernel kills a runaway container instead of the whole Docker VM going
# down with it. Checked before anything is built, because twenty minutes into a
# run is a bad time to find out.
check_budget() {
    budget_needed=$1
    budget_reserve=${THUNDER_VM_RESERVE:-512}
    budget_have=$(docker_memory_mib)
    budget_room=$((budget_have - budget_reserve))

    [ "${budget_needed}" -le "${budget_room}" ] && return 0

    say "ERROR: the ${ROLE} test needs up to ${budget_needed} MiB but the Docker engine has ${budget_have} MiB, of which ${budget_room} MiB is usable." >&2
    say "" >&2
    say "Either give Docker more memory (Docker Desktop: Settings, Resources; on WSL2 the limit comes from %UserProfile%\\.wslconfig), or lower the heap with --memory." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Pack metadata source
# ---------------------------------------------------------------------------

# The pack host is packwiz's own development server. It refuses anything the
# index does not list, so the container sees the file set the packwiz host
# publishes and nothing more. It also refreshes the index as it is queried,
# which keeps the working tree and index.toml from disagreeing part way through
# a run.
#
# This runs on the host, not in a container: packwiz is a stated PATH tool here
# and is already installed in CI. It binds 0.0.0.0, and the test container
# reaches it through the bridge gateway alias.
PACK_HOST_PID=""

start_pack_host() {
    command -v packwiz >/dev/null 2>&1 ||
        die "packwiz is not on PATH, so the working tree cannot be served. Install packwiz, or pass --pack-url to test published metadata instead."

    say "==> Serving the indexed pack from the working tree on port ${PACK_HOST_PORT}"
    # exec so $! is packwiz itself, not the subshell wrapping the cd.
    # Refresh is left at packwiz's default. A run that rewrites index.toml is
    # then telling you the working tree was stale instead of hiding it.
    ( cd "${ROOT_DIR}" && exec packwiz serve -p "${PACK_HOST_PORT}" ) \
        > "${WORK_DIR}/packwiz-serve.log" 2>&1 &
    PACK_HOST_PID=$!

    host_waited=0
    while [ "${host_waited}" -lt 30 ]; do
        if curl -fsS -o /dev/null "http://127.0.0.1:${PACK_HOST_PORT}/pack.toml" 2>/dev/null; then
            return 0
        fi

        # A packwiz that died on a bad index says so in its own words. Better
        # that than this timing out thirty seconds later.
        if ! kill -0 "${PACK_HOST_PID}" 2>/dev/null; then
            say "packwiz serve output:" >&2
            sed 's/^/  /' "${WORK_DIR}/packwiz-serve.log" >&2
            die "packwiz serve stopped before it served pack.toml."
        fi

        sleep 1
        host_waited=$((host_waited + 1))
    done

    die "packwiz serve did not answer on port ${PACK_HOST_PORT} within 30s."
}

stop_pack_host() {
    [ -n "${PACK_HOST_PID}" ] || return 0
    kill "${PACK_HOST_PID}" 2>/dev/null || true
    PACK_HOST_PID=""
}

# Reached through the gateway alias, which both drivers add. packwiz serve binds
# every interface, so this works on Docker Desktop and on a Linux engine alike.
internal_pack_url() {
    printf '%s\n' "http://host.docker.internal:${PACK_HOST_PORT}/pack.toml"
}

# ---------------------------------------------------------------------------
# Reading what the container is doing
# ---------------------------------------------------------------------------

container_field() {
    dk inspect --format "$2" "$1" 2>/dev/null || printf '%s\n' ""
}

container_running() {
    [ "$(container_field "$1" '{{.State.Status}}')" = "running" ]
}

# Reads a file the container is still writing. portablemc draws progress bars
# with carriage returns, so fold them into lines before taking a tail.
container_file_tail() {
    dk exec "$1" sh -c "tr '\\r' '\\n' < '$2' 2>/dev/null | grep -v '^[[:space:]]*\$' | tail -n $3" 2>/dev/null || true
}

container_file_grep() {
    dk exec "$1" sh -c "grep -Eq -- \"\$1\" '$2' 2>/dev/null" _ "$3" 2>/dev/null
}

container_file_match() {
    dk exec "$1" sh -c "grep -Eom1 -- \"\$1\" '$2' 2>/dev/null" _ "$3" 2>/dev/null || true
}

container_file_exists() {
    dk exec "$1" sh -c "[ -e '$2' ]" 2>/dev/null
}

# Docker records whether the kernel killed a container for memory, which is
# worth more than the exit code: a container whose main process was killed
# exits 137, but so does one that ignored a stop.
exit_reason() {
    reason_name=$1
    reason_code=$(container_field "${reason_name}" '{{.State.ExitCode}}')

    if [ "$(container_field "${reason_name}" '{{.State.OOMKilled}}')" = "true" ]; then
        printf '%s\n' "the kernel killed it for exceeding its memory ceiling (exit ${reason_code}), so lower --memory or raise the ceiling"
        return 0
    fi

    case ${reason_code} in
        137) printf '%s\n' "it was killed rather than stopping on its own (exit 137)" ;;
        143) printf '%s\n' "it was stopped (exit 143)" ;;
        *)   printf '%s\n' "it exited with code ${reason_code}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Waiting
# ---------------------------------------------------------------------------

# Watches one container until its log holds READY_PATTERN, or something says the
# run is over. The heartbeat exists because a long wait with no output is
# indistinguishable from a hang. A repeated line is the shape of a stall, and
# worth saying out loud.
#
# Usage: wait_for_marker <container> <log-path> <ready-re> <fatal-re> <timeout>
#
# Returns 0 and prints the line that matched, or returns 1 and prints why it
# gave up. Progress goes to stderr so the caller can capture stdout for that
# one answer.
wait_for_marker() {
    marker_name=$1
    marker_log=$2
    marker_ready=$3
    marker_fatal=$4
    marker_limit=$5

    marker_waited=0
    marker_previous=""
    marker_stalled=0

    while [ "${marker_waited}" -lt "${marker_limit}" ]; do
        if container_file_grep "${marker_name}" "${marker_log}" "${marker_ready}"; then
            container_file_match "${marker_name}" "${marker_log}" "${marker_ready}"
            return 0
        fi

        if [ -n "${marker_fatal}" ] &&
            container_file_grep "${marker_name}" "${marker_log}" "${marker_fatal}"; then
            say "the run failed outright (matched: $(container_file_match "${marker_name}" "${marker_log}" "${marker_fatal}"))"
            return 1
        fi

        if ! container_running "${marker_name}"; then
            say "the container stopped before it was ready: $(exit_reason "${marker_name}")"
            return 1
        fi

        if [ $((marker_waited % HEARTBEAT_INTERVAL)) -eq 0 ] && [ "${marker_waited}" -gt 0 ]; then
            marker_current=$(container_file_tail "${marker_name}" "${marker_log}" 1 | cut -c1-140)
            [ -n "${marker_current}" ] || marker_current="waiting"

            if [ "${marker_current}" = "${marker_previous}" ]; then
                marker_stalled=$((marker_stalled + HEARTBEAT_INTERVAL))
                say "    ${marker_waited}s: no new output for ${marker_stalled}s. Still: ${marker_current}" >&2
            else
                marker_stalled=0
                say "    ${marker_waited}s: ${marker_current}" >&2
            fi
            marker_previous=${marker_current}
        fi

        sleep "${POLL_INTERVAL}"
        marker_waited=$((marker_waited + POLL_INTERVAL))
    done

    say "nothing matched within ${marker_limit}s"
    return 1
}

# ---------------------------------------------------------------------------
# What the pack says should be installed
# ---------------------------------------------------------------------------

# What the pack says a correct instance holds comes from checks-mods.sh, which
# the CI install checks use too, so the side rule is worked out in one place. A
# missing jar means the sync did not finish; an unexpected one means a removed
# mod is still in the volume from an earlier run.
check_mod_set() {
    check_volume=$1
    check_side=$2
    check_dir=$3

    bash "${ROOT_DIR}/.github/scripts/checks-mods.sh" "${check_side}" \
        > "${WORK_DIR}/expected" ||
        die "Could not work out which mods the pack expects on the ${check_side} side."
    volume_run "${check_volume}" "ls -1 '${check_dir}' 2>/dev/null" |
        grep '\.jar$' | sort > "${WORK_DIR}/actual" || true

    expected_count=$(wc -l < "${WORK_DIR}/expected" | tr -d ' ')
    actual_count=$(wc -l < "${WORK_DIR}/actual" | tr -d ' ')

    if [ "${expected_count}" -eq 0 ]; then
        say "  Mods: index.toml lists no ${check_side}-side mods, which cannot be right." >&2
        return 1
    fi

    comm -23 "${WORK_DIR}/expected" "${WORK_DIR}/actual" > "${WORK_DIR}/missing"
    comm -13 "${WORK_DIR}/expected" "${WORK_DIR}/actual" > "${WORK_DIR}/unexpected"

    if [ ! -s "${WORK_DIR}/missing" ] && [ ! -s "${WORK_DIR}/unexpected" ]; then
        say "  Mods: ${actual_count} installed, matching all ${expected_count} ${check_side}-side entries in index.toml."
        return 0
    fi

    say "  Mods: ${actual_count} installed, expected ${expected_count} for side=${check_side}." >&2
    if [ -s "${WORK_DIR}/missing" ]; then
        say "  Missing from the instance:" >&2
        sed 's/^/    /' "${WORK_DIR}/missing" >&2
    fi
    if [ -s "${WORK_DIR}/unexpected" ]; then
        say "  Present but not in the pack:" >&2
        sed 's/^/    /' "${WORK_DIR}/unexpected" >&2
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Collecting what the run produced
# ---------------------------------------------------------------------------

# Runs a command against a harness volume in a throwaway container. Works
# whether the owning container is running, stopped or gone.
volume_run() {
    dk run --rm --network none \
        -v "$1:/vol:ro" \
        "${HELPER_IMAGE}" sh -c "$2" 2>/dev/null || true
}

# Copies the logs and crash reports out of the volume and zips them, so the
# result survives the container and uploads as one artefact. The zipping happens
# in the helper container because zip is not reliably on a Git Bash PATH, and
# because it keeps the whole thing to one bind mount of a small output folder.
collect_logs() {
    collect_volume=$1
    collect_zip=$2
    shift 2

    mkdir -p "${ARTIFACT_DIR}"
    rm -f "${ARTIFACT_DIR}/${collect_zip}" "${ARTIFACT_DIR}/crash-reports-${ROLE}.zip"

    collect_paths=""
    for collect_path in "$@"; do
        collect_paths="${collect_paths} '${collect_path}'"
    done

    dk run --rm --network none \
        -v "${collect_volume}:/vol:ro" \
        -v "$(host_path "${ARTIFACT_DIR}"):/out" \
        "${HELPER_IMAGE}" sh -c "
            set -e
            mkdir -p /tmp/collect
            for p in ${collect_paths}; do
                [ -e \"/vol/\$p\" ] || continue
                mkdir -p \"/tmp/collect/\$(dirname \"\$p\")\"
                cp -r \"/vol/\$p\" \"/tmp/collect/\$p\"
            done
            cd /tmp/collect
            if [ -n \"\$(find . -type f -print -quit)\" ]; then
                python -c \"import shutil;shutil.make_archive('/out/${collect_zip%.zip}','zip','/tmp/collect')\"
            fi
            if [ -d /vol/crash-reports ] && [ -n \"\$(find /vol/crash-reports -type f -print -quit)\" ]; then
                python -c \"import shutil;shutil.make_archive('/out/crash-reports-${ROLE}','zip','/vol/crash-reports')\"
            fi
        " >/dev/null 2>&1 || true

    if [ -f "${ARTIFACT_DIR}/${collect_zip}" ]; then
        say "  Logs: tmp/tests/${collect_zip}"
    else
        say "  Logs: nothing was written to collect."
    fi

    if [ -f "${ARTIFACT_DIR}/crash-reports-${ROLE}.zip" ]; then
        say "  Crash reports: tmp/tests/crash-reports-${ROLE}.zip"
    fi
}

# Counts what the run logged as problems. Some are known and harmless, so this
# reports and never fails. A jump in the count is still worth a look, and the
# log is in the artefacts.
summarise_problems() {
    summary_volume=$1
    summary_path=$2

    summary_counts=$(volume_run "${summary_volume}" "
        [ -f '/vol/${summary_path}' ] || exit 0
        printf '%s %s\n' \
            \"\$(grep -c '/ERROR\]' '/vol/${summary_path}' || true)\" \
            \"\$(grep -c '/WARN\]' '/vol/${summary_path}' || true)\"
    ")
    [ -n "${summary_counts}" ] || return 0

    summary_errors=${summary_counts% *}
    summary_warnings=${summary_counts#* }
    say "  Log: ${summary_errors} ERROR lines, ${summary_warnings} WARN lines."

    [ "${summary_errors}" -gt 0 ] || return 0

    say "  Most frequent ERROR sources:"
    volume_run "${summary_volume}" "
        grep -o '\[[^]]*/ERROR\] \[[^]]*\]' '/vol/${summary_path}' 2>/dev/null |
            sort | uniq -c | sort -rn | head -n 8
    " | sed 's/^/    /'
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

report_failure() {
    failed_name=$1
    failed_reason=$2
    failed_log=$3

    say "" >&2
    say "FAILED: the ${ROLE} test." >&2
    say "Why: ${failed_reason}" >&2
    say "" >&2
    say "Last 60 lines of ${failed_log}:" >&2
    container_file_tail "${failed_name}" "${failed_log}" 60 | sed 's/^/  /' >&2

    say "" >&2
    say "Last 40 lines of container output:" >&2
    dk logs --tail 40 "${failed_name}" 2>&1 | tr '\r' '\n' | grep -v '^[[:space:]]*$' | sed 's/^/  /' >&2
}
