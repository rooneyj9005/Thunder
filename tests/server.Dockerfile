# syntax=docker/dockerfile:1
# Pterodactyl-style Thunder server, for the end-to-end server test.
#
# Built on the same yolk image Pterodactyl runs and driven by the pack's own
# install.sh and startup.sh, so it exercises what a real panel deployment does
# and not an approximation of it.
#
# tests/server.sh builds and drives this. Nothing in here decides whether the
# test passed; that judgement is the driver's.
FROM ghcr.io/pterodactyl/yolks:java_21

# Root so the harness volume at /home/container is writable. A real panel sets
# this ownership itself; this is a convenience for a throwaway test.
USER root

# The whole server-side test: get the installer, install Forge and the server
# mods, accept the EULA, set the test-only overrides, and hand over to the
# pack's own startup script.
COPY <<'ENTRYPOINT' /usr/local/bin/run-server
#!/bin/sh
set -eu

PACKWIZ_URL="${PACKWIZ_URL:-http://host.docker.internal:8123/pack.toml}"
PACK_HOST="${PACKWIZ_URL%/pack.toml}"
SERVER_DIR=/home/container
STATE_DIR="${SERVER_DIR}/.thunder-test"
INSTALL_MARKER="${STATE_DIR}/installed"

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

fetch() {
    curl -fsSL --connect-timeout 15 --max-time 180 --retry 3 --retry-delay 2 \
        -o "$2" "$1" ||
        die "Could not fetch $1."
}

cd "${SERVER_DIR}"
mkdir -p "${STATE_DIR}"

# Clear the previous run's diagnostics. Without this a "]: Done (" left in the
# volume by an earlier run would mark this one ready before it has started.
rm -rf "${SERVER_DIR}/logs" "${SERVER_DIR}/crash-reports"

# install.sh and functions.sh are release assets, not pack content. The
# packwiz host serves only indexed files, and .packwizignore keeps install.sh
# out of the index deliberately, so neither can come from there. The Pterodactyl
# egg fetches both from the GitHub release; a release test does the same, and a
# local run uses the working-tree copies mounted at /opt/thunder.
if [ -n "${INSTALL_ASSETS_URL:-}" ]; then
    printf '%s\n' "==> Fetching the installer from ${INSTALL_ASSETS_URL}, which is the egg's own path"
    fetch "${INSTALL_ASSETS_URL}/install.sh" install.sh
    fetch "${INSTALL_ASSETS_URL}/functions.sh" functions.sh
else
    printf '%s\n' "==> Using the working-tree installer mounted at /opt/thunder"
    [ -f /opt/thunder/install.sh ] ||
        die "Neither INSTALL_ASSETS_URL nor /opt/thunder/install.sh is present, so there is no installer to run."
    cp /opt/thunder/install.sh install.sh
    cp /opt/thunder/functions.sh functions.sh
fi

# The marker carries the index hash. A cached volume then reinstalls when the
# pack definition changes underneath it, instead of testing the old mod set
# against the new index and calling that a pass.
fetch "${PACK_HOST}/index.toml" "${STATE_DIR}/index.remote.toml"
INDEX_HASH=$(sha256sum "${STATE_DIR}/index.remote.toml" | cut -d' ' -f1)

if [ ! -f "${INSTALL_MARKER}" ] || [ "$(cat "${INSTALL_MARKER}")" != "${INDEX_HASH}" ]; then
    printf '%s\n' "==> Installing the Thunder server (side=server) from ${PACKWIZ_URL}"
    PACKWIZ_URL="${PACKWIZ_URL}" PACKWIZ_SIDE=server sh install.sh --dir "${SERVER_DIR}" ||
        die "install.sh failed, so nothing was installed. The output above is from the pack's own installer."

    # install.sh reports its own failures, but a silent partial install is worse
    # than a loud one: check for what a Forge install must leave behind.
    [ -e unix_args.txt ] || [ -e server.jar ] ||
        die "install.sh finished successfully but left neither unix_args.txt nor server.jar, so there is nothing to start."
    [ -f startup.sh ] ||
        die "install.sh did not sync startup.sh from the pack. Check that startup.sh is indexed in index.toml."

    printf '%s\n' "${INDEX_HASH}" > "${INSTALL_MARKER}"
else
    printf '%s\n' "==> Reusing the install in the volume; index.toml is unchanged. Use --clean to start from scratch."
fi

printf 'eula=true\n' > eula.txt

# Rewrites one server.properties key and keeps every other line. The key is a
# literal from this script and the value never reaches a shell or sed, so a
# value containing / or & is safe.
set_property() {
    if [ -f server.properties ]; then
        grep -v "^$1=" server.properties > server.properties.new || true
    else
        : > server.properties.new
    fi
    printf '%s=%s\n' "$1" "$2" >> server.properties.new
    mv server.properties.new server.properties
}

# A small view distance keeps the test inside a modest heap. The pack's own
# defaults are for real servers with real hardware.
set_property motd "Thunder test"
set_property spawn-protection 0
set_property view-distance "${VIEW_DISTANCE:-6}"
set_property simulation-distance "${SIMULATION_DISTANCE:-5}"

printf '%s\n' "==> Starting the server with SERVER_MEMORY=${SERVER_MEMORY:-4096} MiB, the Pterodactyl startup command"
# The mods are installed above, so leave the startup re-sync off.
export PACKWIZ_AUTO_UPDATE=false
exec sh startup.sh --container --memory "${SERVER_MEMORY:-4096}"
ENTRYPOINT

RUN chmod +x /usr/local/bin/run-server

WORKDIR /home/container
ENTRYPOINT ["/usr/local/bin/run-server"]
