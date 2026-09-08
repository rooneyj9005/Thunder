#!/bin/sh
set -eu

# End-to-end test for the Thunder client.
#
# Syncs the client side the way a launcher would, launches Forge headless, and
# passes once the full mod set has loaded and the client is sitting on the title
# screen. The installed jars are checked against the client-side entries in
# index.toml, and every log the run produced is zipped into tmp/tests/
# whether it passed or failed.
#
# It stops at the title screen on purpose. Getting a headless client into a
# world needs a save for it to open, and making one without a UI costs more
# than it proves; the server test already covers world generation and loading.
#
# Where it stops is the diagnostic, so it is judged on a ladder of markers and
# not one. Dying while stitching the block atlas and dying because a mod would
# not load are different problems, and the driver should say which it was.
#
# The pack comes from your working tree over packwiz serve, unless --pack-url
# points somewhere else and the same container tests that instead.
#
# Usage:
#   sh tests/client.sh                              test the working tree
#   sh tests/client.sh --pack-url <url>             test published metadata
#   sh tests/client.sh --memory 2048 --clean        smaller heap, empty volume

ROLE=client
# shellcheck source=tests/functions.sh
. "$(CDPATH='' cd "$(dirname "$0")" && pwd)/functions.sh"

CONTAINER="thunder-test-client"
VOLUME="thunder-test-client-data"
IMAGE="thunder-test-client:local"
LOG_PATH="/data/logs/latest.log"

MEMORY=${THUNDER_CLIENT_MEMORY:-4096}
OVERHEAD=${THUNDER_CLIENT_OVERHEAD:-2560}
LOAD_TIMEOUT=${THUNDER_CLIENT_LOAD_TIMEOUT:-1800}
SETTLE_SECONDS=${THUNDER_CLIENT_SETTLE_SECONDS:-20}
PACK_URL=""
BUILD=1
CLEAN=0
KEEP=0

# The rungs, lowest first. Each is a name and an extended regex matched against
# the client log. The last is the pass bar: stitching the atlases is the end of
# the first resource reload and the last heavy work before the title screen, so
# a client that gets there and stays there has loaded the pack.
RUNG_NAMES="resources atlas"

rung_pattern() {
    case $1 in
        resources) printf '%s\n' 'Reloading ResourceManager' ;;
        atlas)     printf '%s\n' 'minecraft:textures/atlas' ;;
    esac
}

rung_description() {
    case $1 in
        resources) printf '%s\n' "every client mod was constructed and the resource reload began" ;;
        atlas)     printf '%s\n' "the texture atlases were stitched, so the client reached the title screen" ;;
    esac
}

FATAL_PATTERN='LoadingFailedException|Mod Loading has failed|Failed to create mod instance|Missing or unsupported mandatory dependencies|Incompatible mods found|java\.lang\.OutOfMemoryError'

usage() {
    cat <<'USAGE'
Usage: sh tests/client.sh [options]

Options:
  --pack-url <url>            pack.toml to sync from (default: the working tree)
  --memory <MiB>              client heap (default 4096)
  --clean                     delete the cached volume first
  --no-build                  reuse the existing image
  --keep                      leave the container running afterwards
  -h, --help                  show this
USAGE
}

while [ "$#" -gt 0 ]; do
    case $1 in
        --pack-url)
            [ -n "${2:-}" ] || die "--pack-url requires a URL."
            PACK_URL=$2
            shift 2
            ;;
        --memory)
            [ -n "${2:-}" ] || die "--memory requires a MiB value."
            MEMORY=$2
            shift 2
            ;;
        --clean) CLEAN=1; shift ;;
        --no-build) BUILD=0; shift ;;
        --keep) KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            printf '%s\n' "ERROR: Unknown argument '$1'." >&2
            usage >&2
            exit 2
            ;;
    esac
done

case ${MEMORY} in
    ''|*[!0-9]*) die "--memory must be an integer in MiB." ;;
esac

CEILING=$((MEMORY + OVERHEAD))
WORK_DIR=$(mktemp -d)
OWN_PACK_HOST=0
CLEANED=0

cleanup() {
    # The EXIT trap and the explicit call below can both reach this, so it runs
    # once and is a no-op after that.
    [ "${CLEANED}" -eq 0 ] || return 0
    CLEANED=1

    rm -rf "${WORK_DIR}"

    [ "${OWN_PACK_HOST}" -eq 1 ] && stop_pack_host

    if [ "${KEEP}" -eq 1 ]; then
        say "Container left running (--keep). Stop it with: docker rm -f ${CONTAINER}"
        return 0
    fi

    dk rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}

# The INT and TERM handler only announces itself and exits. Exiting fires the
# EXIT trap, which is what actually tears the run down.
trap 'cleanup' EXIT
trap 'say "" >&2; say "Interrupted. Tearing down so nothing is left holding memory." >&2; exit 130' INT TERM

require_docker
check_budget "$((CEILING + 256))"

banner "Thunder client test. Heap ${MEMORY} MiB, container ceiling ${CEILING} MiB."

if [ -z "${PACK_URL}" ]; then
    start_pack_host
    OWN_PACK_HOST=1
    PACK_URL=$(internal_pack_url)
    say "  Pack source: the working tree"
else
    say "  Pack source: ${PACK_URL}"
fi

if [ "${CLEAN}" -eq 1 ]; then
    say "  Clearing the cached volume (--clean)."
    dk rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    dk volume rm -f "${VOLUME}" >/dev/null 2>&1 || true
fi

if [ "${BUILD}" -eq 1 ]; then
    say "==> Building ${IMAGE}"
    dk build -f "$(host_path "${TESTS_DIR}/client.Dockerfile")" \
        -t "${IMAGE}" "$(host_path "${ROOT_DIR}")" ||
        die "The client image would not build."
fi

dk rm -f "${CONTAINER}" >/dev/null 2>&1 || true

STARTED=$(date +%s)

say "==> Starting ${CONTAINER}"
dk run -d --init \
    --name "${CONTAINER}" \
    --add-host "host.docker.internal:host-gateway" \
    -e "PACKWIZ_URL=${PACK_URL}" \
    -e "CLIENT_MEMORY=${MEMORY}" \
    -v "${VOLUME}:/data" \
    -m "${CEILING}m" \
    --memory-swap "${CEILING}m" \
    "${IMAGE}" >/dev/null ||
    die "The client container would not start."

REACHED=""
REACHED_DESC=""
STATUS=1
REASON=""
waited=0
previous=""
stalled=0

while [ "${waited}" -lt "${LOAD_TIMEOUT}" ]; do
    # Walk the whole ladder every poll and keep the highest rung that matches.
    # Rungs are listed lowest first and a log line never unwrites itself, so the
    # last match is always the furthest the client has got and the ladder cannot
    # appear to go backwards.
    highest=""
    for rung in ${RUNG_NAMES}; do
        if container_file_grep "${CONTAINER}" "${LOG_PATH}" "$(rung_pattern "${rung}")"; then
            highest=${rung}
        fi
    done

    if [ -n "${highest}" ] && [ "${highest}" != "${REACHED}" ]; then
        REACHED=${highest}
        REACHED_DESC=$(rung_description "${highest}")
        say "  Reached '${REACHED}': ${REACHED_DESC}"
    fi

    if [ "${REACHED}" = "atlas" ]; then
        STATUS=0
        break
    fi

    if dk exec "${CONTAINER}" sh -c \
        'find /data/crash-reports -name "*.txt" -print -quit 2>/dev/null | grep -q .' 2>/dev/null; then
        REASON="the client crashed and wrote a crash report"
        break
    fi

    if container_file_grep "${CONTAINER}" "${LOG_PATH}" "${FATAL_PATTERN}"; then
        REASON="mod loading failed (matched: $(container_file_match "${CONTAINER}" "${LOG_PATH}" "${FATAL_PATTERN}"))"
        break
    fi

    if ! container_running "${CONTAINER}"; then
        REASON="the client stopped before it finished loading: $(exit_reason "${CONTAINER}")"
        break
    fi

    if [ $((waited % HEARTBEAT_INTERVAL)) -eq 0 ] && [ "${waited}" -gt 0 ]; then
        current=$(container_file_tail "${CONTAINER}" "${LOG_PATH}" 1 | cut -c1-140)
        [ -n "${current}" ] || current="waiting for the game to write a log"

        # A client starved of memory stalls instead of stopping, and the log
        # going quiet is the only sign of it. Worth saying at the time.
        if [ "${current}" = "${previous}" ]; then
            stalled=$((stalled + HEARTBEAT_INTERVAL))
            say "    ${waited}s: no new log output for ${stalled}s. Still: ${current}"
        else
            stalled=0
            say "    ${waited}s: ${current}"
        fi
        previous=${current}
    fi

    sleep "${POLL_INTERVAL}"
    waited=$((waited + POLL_INTERVAL))
done

if [ "${STATUS}" -ne 0 ] && [ -z "${REASON}" ]; then
    REASON="the client did not finish loading within ${LOAD_TIMEOUT}s"
fi

# Finishing the reload is not the same as surviving it. A client that runs out
# of heap does so around here, so hold briefly and confirm it is still up.
if [ "${STATUS}" -eq 0 ]; then
    say "==> Loaded after ${waited}s. Holding ${SETTLE_SECONDS}s to confirm it stays up."
    settled=0
    while [ "${settled}" -lt "${SETTLE_SECONDS}" ]; do
        if ! container_running "${CONTAINER}"; then
            REASON="the client finished loading and then ended: $(exit_reason "${CONTAINER}")"
            STATUS=1
            break
        fi
        sleep 5
        settled=$((settled + 5))
    done
fi

if [ "${STATUS}" -eq 0 ]; then
    check_mod_set "${VOLUME}" client /vol/mods || {
        STATUS=1
        REASON="the installed mod set does not match index.toml"
    }
else
    say "" >&2
    if [ -n "${REACHED}" ]; then
        say "The client got as far as '${REACHED}': ${REACHED_DESC}." >&2
    else
        say "The client did not reach the first rung, so it never got past mod construction." >&2
    fi
    report_failure "${CONTAINER}" "${REASON}" "${LOG_PATH}"
fi

summarise_problems "${VOLUME}" "logs/latest.log"
collect_logs "${VOLUME}" "client-logs.zip" "logs" "crash-reports" "options.txt"

# Everything worth keeping is out of the container now, so stop holding memory
# while the result is printed. The EXIT trap still covers every earlier exit.
cleanup

ELAPSED=$(($(date +%s) - STARTED))

banner "Result"
if [ "${STATUS}" -eq 0 ]; then
    say "  client  PASS  ${ELAPSED}s  loaded the full mod set and held the title screen"
    exit 0
fi

say "  client  FAIL  ${ELAPSED}s  ${REASON}"
say "  Furthest rung reached: ${REACHED:-none}"
exit 1
