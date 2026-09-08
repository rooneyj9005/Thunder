# syntax=docker/dockerfile:1
# Prism-style Thunder client, for the end-to-end client test.
#
# Java 21 plus a virtual display and software OpenGL so the Forge client can run
# with no GPU, and portablemc as the launcher, which is the closest standalone
# equivalent of what Prism does.
#
# The base is Ubuntu 24.04, which carries Mesa 24.x. It was moved up from 22.04
# to test whether llvmpipe explained the client dying while stitching the block
# atlas. It did not: that was the heap, and software OpenGL renders the pack
# perfectly well. The newer base stays because it works.
#
# tests/client.sh builds and drives this. It only has to get the game running
# and write a log; the driver reads that log and decides how far it got.
FROM eclipse-temurin:21-jdk-noble

ENV DEBIAN_FRONTEND=noninteractive

# xauth is what xvfb-run needs for its cookie. It comes with this base today;
# naming it keeps a slimmer base from breaking the run. mesa-utils earns its
# place by making glxinfo available, which is the difference between "the GL
# stack is wrong" and a guess.
RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        xauth \
        libgl1 \
        libgl1-mesa-dri \
        libglu1-mesa \
        libglfw3 \
        libopenal1 \
        mesa-utils \
        curl ca-certificates \
        python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

# portablemc in an isolated venv. Recent releases ship Forge support built in.
RUN python3 -m venv /opt/pmc && /opt/pmc/bin/pip install --no-cache-dir portablemc
ENV PATH="/opt/pmc/bin:${PATH}"

# The whole client-side test: sync the client files the way a launcher would,
# set up a throwaway instance, and launch the game. The driver decides how far
# it got by reading the log this writes.
COPY <<'ENTRYPOINT' /usr/local/bin/run-client
#!/bin/sh
set -eu

PACKWIZ_URL="${PACKWIZ_URL:-http://host.docker.internal:8123/pack.toml}"
MC_VERSION="${MC_VERSION:-1.20.1}"
FORGE_VERSION="${FORGE_VERSION:-47.4.13}"
USERNAME="${CLIENT_USERNAME:-TestPlayer}"
CLIENT_MEMORY="${CLIENT_MEMORY:-4096}"
SYNC_TIMEOUT="${CLIENT_SYNC_TIMEOUT:-900}"
RENDER_DISTANCE="${RENDER_DISTANCE:-6}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://github.com/packwiz/packwiz-installer-bootstrap/releases/latest/download/packwiz-installer-bootstrap.jar}"

GAME_DIR=/data
STATE_DIR="${GAME_DIR}/.thunder-test"

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

mkdir -p "${STATE_DIR}"
cd "${GAME_DIR}"

# Clear the previous run's diagnostics so nothing here can be judged on a log
# left in the volume by an earlier run. Everything portablemc caches lives
# outside these.
rm -rf "${GAME_DIR}/logs" "${GAME_DIR}/crash-reports"
mkdir -p "${GAME_DIR}/logs"

# Recorded so the driver can tell a broken GL stack from a broken pack without
# anyone having to reproduce the run by hand.
printf '%s\n' "==> Software OpenGL:"
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a glxinfo -B 2>&1 | sed -n '1,12p' | sed 's/^/    /' || true

printf '%s\n' "==> Syncing client files (side=client) from ${PACKWIZ_URL}"

BOOTSTRAP_JAR="${STATE_DIR}/packwiz-installer-bootstrap.jar"
if [ ! -s "${BOOTSTRAP_JAR}" ]; then
    curl -fsSL --connect-timeout 15 --max-time 180 --retry 3 --retry-delay 2 \
        -o "${BOOTSTRAP_JAR}" "${BOOTSTRAP_URL}" ||
        die "Could not download packwiz-installer-bootstrap from ${BOOTSTRAP_URL}."
fi

sync_status=0
timeout "${SYNC_TIMEOUT}" java -jar "${BOOTSTRAP_JAR}" -g -s client "${PACKWIZ_URL}" || sync_status=$?

if [ "${sync_status}" -eq 124 ]; then
    die "packwiz-installer did not finish within ${SYNC_TIMEOUT}s. Raise CLIENT_SYNC_TIMEOUT if the connection is slow."
elif [ "${sync_status}" -ne 0 ]; then
    die "packwiz-installer failed with exit code ${sync_status}. A hash mismatch above means the working tree and index.toml disagree, so run packwiz refresh."
fi

MOD_COUNT=$(find "${GAME_DIR}/mods" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l | tr -d ' ')
[ "${MOD_COUNT}" -gt 0 ] ||
    die "packwiz-installer reported success but ${GAME_DIR}/mods holds no jars, so the client would launch as good as vanilla."
printf '%s\n' "==> Synced ${MOD_COUNT} client mods."

# A throwaway instance, so the settings are ours to set. Low distances and no
# sound keep the client inside a modest heap on software OpenGL, and the two
# onboarding flags stop 1.20 opening a screen over the title screen. Mipmaps off
# matters most: stitching the block atlas is the largest allocation the client
# makes and mipmaps multiply it.
cat > "${GAME_DIR}/options.txt" <<OPTIONS
version:3465
renderDistance:${RENDER_DISTANCE}
mipmapLevels:0
simulationDistance:5
graphicsMode:0
particles:2
enableVsync:false
maxFps:60
guiScale:2
soundCategory_master:0.0
narrator:0
skipMultiplayerWarning:true
onboardAccessibility:false
tutorialStep:none
OPTIONS

export LIBGL_ALWAYS_SOFTWARE=1

JVM_ARGS="-Xmx${CLIENT_MEMORY}M -XX:+ExitOnOutOfMemoryError -Dfml.earlyprogresswindow=false"

printf '%s\n' "==> Launching Forge ${MC_VERSION}-${FORGE_VERSION} as ${USERNAME}, heap ${CLIENT_MEMORY} MiB"

# No setsid here. Docker kills every process in the container's PID namespace
# when the container stops, and --init gives us an init that forwards signals,
# so the game needs no session of its own. An earlier version wrapped this in
# setsid, which forks when it is already a process group leader: the parent
# returned 0 straight away, the container went down with it, and a launch that
# never happened was reported as a clean exit.
#
# Nothing is passed after the version. `portablemc start` accepts a version and
# nothing else, so game arguments cannot be forwarded through it at all.
exec xvfb-run -a \
    portablemc --main-dir "${GAME_DIR}" start \
        --jvm "$(command -v java)" \
        "--jvm-args=${JVM_ARGS}" \
        -u "${USERNAME}" \
        "forge:${MC_VERSION}-${FORGE_VERSION}"
ENTRYPOINT

RUN chmod +x /usr/local/bin/run-client

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/run-client"]
