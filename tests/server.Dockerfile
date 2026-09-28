# syntax=docker/dockerfile:1
# Pterodactyl-style Thunder server, for the end-to-end server test.
#
# Two stages, because a panel uses two containers. The install stage is the
# egg's own install image running install.sh --container against /mnt/server,
# which is exactly what the egg's install script does. The run stage is the yolk
# image the server then runs on, driven by the pack's own startup.sh. Between
# them they exercise what a real panel deployment does and not an approximation
# of it. checks-pack.sh holds the install stage to the image the egg names, so
# the two cannot drift apart again.
#
# tests/server.sh builds and drives both. Nothing in here decides whether the
# test passed; that judgement is the driver's.

FROM eclipse-temurin:21-jre-noble AS install

# Get the installer, then install Forge and the server mods the way the egg
# does. Everything it prints also goes to a file in the volume, so the driver
# can zip it with the server's own logs.
COPY <<'INSTALL' /usr/local/bin/install-server
#!/bin/sh
set -eu

PACKWIZ_URL="${PACKWIZ_URL:-http://host.docker.internal:8123/pack.toml}"
PACK_HOST="${PACKWIZ_URL%/pack.toml}"

# install.sh refuses a plaintext pack host, because over http the attacker who
# controls the index also controls the hashes it is checked against. The host
# here is packwiz serve on the loopback of the machine running the test, so the
# rule is waived for the length of this container and nowhere else.
PACKWIZ_ALLOW_INSECURE_URL=1
export PACKWIZ_ALLOW_INSECURE_URL
SERVER_DIR=/mnt/server
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

if [ -f "${INSTALL_MARKER}" ] && [ "$(cat "${INSTALL_MARKER}")" = "${INDEX_HASH}" ]; then
    printf '%s\n' "==> Reusing the install in the volume; index.toml is unchanged. Use --clean to start from scratch."
    exit 0
fi

printf '%s\n' "==> Installing the Thunder server (side=server) from ${PACKWIZ_URL}"
PACKWIZ_URL="${PACKWIZ_URL}" PACKWIZ_SIDE=server bash install.sh --container ||
    die "install.sh failed, so nothing was installed. The output above is from the pack's own installer."

# install.sh reports its own failures, but a silent partial install is worse
# than a loud one: check for what a Forge install must leave behind.
[ -e unix_args.txt ] || [ -e server.jar ] ||
    die "install.sh finished successfully but left neither unix_args.txt nor server.jar, so there is nothing to start."
[ -f startup.sh ] ||
    die "install.sh did not sync startup.sh from the pack. Check that startup.sh is indexed in index.toml."

# The whole point of installing on an image that already has Java.
if ls -d jdk-21* jre-21* >/dev/null 2>&1; then
    die "install.sh downloaded a Java runtime into the server directory, though the install image already has one."
fi

printf '%s\n' "${INDEX_HASH}" > "${INSTALL_MARKER}"
INSTALL

RUN chmod +x /usr/local/bin/install-server
WORKDIR /mnt/server
# bash for pipefail: through tee in plain sh, the exit status would be tee's and
# a failed install would read as a good one.
ENTRYPOINT ["/bin/bash", "-o", "pipefail", "-c", "mkdir -p /mnt/server/.thunder-test && /usr/local/bin/install-server 2>&1 | tee /mnt/server/.thunder-test/install.log"]

FROM ghcr.io/pterodactyl/yolks:java_21 AS run

# Root so the harness volume at /home/container is writable. A real panel sets
# this ownership itself; this is a convenience for a throwaway test.
USER root

# Accept the EULA, set the test-only overrides, and hand over to the pack's own
# startup script, which is what the panel's startup command runs.
COPY <<'ENTRYPOINT' /usr/local/bin/run-server
#!/bin/sh
set -eu

SERVER_DIR=/home/container

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

cd "${SERVER_DIR}"

[ -f startup.sh ] ||
    die "Nothing is installed in the volume. tests/server.sh runs the install stage first."

# Clear the previous run's diagnostics. Without this a "]: Done (" left in the
# volume by an earlier run would mark this one ready before it has started.
rm -rf "${SERVER_DIR}/logs" "${SERVER_DIR}/crash-reports"

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
