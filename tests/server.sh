#!/bin/sh
set -eu

# End-to-end test for the Thunder server.
#
# Installs the pack the way the Pterodactyl egg does, boots it, and passes when
# the server has generated its world and finished starting. The installed jars
# are checked against the server-side entries in index.toml, and every log the
# run produced is zipped into tmp/tests/ whether it passed or failed.
#
# With no --pack-url the working tree is served by packwiz serve. Give it a URL
# and the same container tests published metadata under the same assertions,
# which is what the release workflow does.
#
# Usage:
#   sh tests/server.sh                              test the working tree
#   sh tests/server.sh --pack-url <url>             test published metadata
#   sh tests/server.sh --memory 3072 --clean        smaller heap, empty volume

ROLE=server
# shellcheck source=tests/functions.sh
. "$(CDPATH='' cd "$(dirname "$0")" && pwd)/functions.sh"

CONTAINER="thunder-test-server"
VOLUME="thunder-test-server-data"
IMAGE="thunder-test-server:local"
LOG_PATH="/home/container/logs/latest.log"

MEMORY=${THUNDER_SERVER_MEMORY:-4096}
OVERHEAD=${THUNDER_SERVER_OVERHEAD:-1024}
BOOT_TIMEOUT=${THUNDER_SERVER_BOOT_TIMEOUT:-2400}
PACK_URL=""
INSTALL_ASSETS_URL=""
BUILD=1
CLEAN=0
KEEP=0

usage() {
    cat <<'USAGE'
Usage: sh tests/server.sh [options]

Options:
  --pack-url <url>            pack.toml to install from (default: the working tree)
  --install-assets-url <url>  where to fetch install.sh and functions.sh,
                              as the Pterodactyl egg does (default: the working tree)
  --memory <MiB>              server heap (default 4096)
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
        --install-assets-url)
            [ -n "${2:-}" ] || die "--install-assets-url requires a URL."
            INSTALL_ASSETS_URL=$2
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

banner "Thunder server test. Heap ${MEMORY} MiB, container ceiling ${CEILING} MiB."

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
    dk build -f "$(host_path "${TESTS_DIR}/server.Dockerfile")" \
        -t "${IMAGE}" "$(host_path "${ROOT_DIR}")" ||
        die "The server image would not build."
fi

dk rm -f "${CONTAINER}" >/dev/null 2>&1 || true

STARTED=$(date +%s)

# A hard ceiling with swap denied turns "the whole Docker VM thrashes" into
# "this container was killed", which is something the driver can explain.
say "==> Starting ${CONTAINER}"
dk run -d --init \
    --name "${CONTAINER}" \
    --add-host "host.docker.internal:host-gateway" \
    -e "PACKWIZ_URL=${PACK_URL}" \
    -e "INSTALL_ASSETS_URL=${INSTALL_ASSETS_URL}" \
    -v "$(host_path "${ROOT_DIR}/tools/install.sh"):/opt/thunder/install.sh:ro" \
    -v "$(host_path "${ROOT_DIR}/functions.sh"):/opt/thunder/functions.sh:ro" \
    -e "SERVER_MEMORY=${MEMORY}" \
    -e "ENABLE_VOICE_CHAT=false" \
    -v "${VOLUME}:/home/container" \
    -m "${CEILING}m" \
    --memory-swap "${CEILING}m" \
    "${IMAGE}" >/dev/null ||
    die "The server container would not start."

STATUS=0
REASON=""

# The server has proved itself when it has generated its world and finished
# starting, which is the line vanilla logs and the panel watches for.
if MARKER=$(wait_for_marker "${CONTAINER}" "${LOG_PATH}" ']: Done \(' '' "${BOOT_TIMEOUT}"); then
    say "  Ready: ${MARKER}"
    check_mod_set "${VOLUME}" server /vol/mods || {
        STATUS=1
        REASON="the installed mod set does not match index.toml"
    }
else
    STATUS=1
    REASON=${MARKER}
    report_failure "${CONTAINER}" "${REASON}" "${LOG_PATH}"
fi

summarise_problems "${VOLUME}" "logs/latest.log"
collect_logs "${VOLUME}" "server-logs.zip" "logs" "crash-reports" "server.properties"

# Everything worth keeping is out of the container now, so stop holding memory
# while the result is printed. The EXIT trap still covers every earlier exit.
cleanup

ELAPSED=$(($(date +%s) - STARTED))

banner "Result"
if [ "${STATUS}" -eq 0 ]; then
    say "  server  PASS  ${ELAPSED}s"
    exit 0
fi

say "  server  FAIL  ${ELAPSED}s  ${REASON}"
exit 1
