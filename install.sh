#!/bin/bash
set -eo pipefail

apt-get update
apt-get install -y --no-install-recommends curl jq ca-certificates default-jre-headless

cd /mnt/server

echo "Fetching packwiz-installer-bootstrap..."
PACKWIZ_BOOTSTRAP_URL=$(curl -sSfL https://api.github.com/repos/packwiz/packwiz-installer-bootstrap/releases/latest | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url')

if [[ -z "$PACKWIZ_BOOTSTRAP_URL" ]]; then
  echo "ERROR: Failed to resolve packwiz-installer-bootstrap download URL."
  exit 1
fi

curl -sSfL -o packwiz-installer-bootstrap.jar "$PACKWIZ_BOOTSTRAP_URL"
echo "Downloaded packwiz-installer-bootstrap.jar"

case "${MODLOADER}" in
  forge)
    rm -f unix_args.txt user_jvm_args.txt run.sh run.bat

    RESOLVED_VERSION="${FORGE_VERSION:-}"
    if [[ -z "$RESOLVED_VERSION" ]]; then
      JSON_DATA=$(curl -sSfL https://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json)
      RESOLVED_VERSION=$(echo "$JSON_DATA" | jq -r ".promos[\"${MC_VERSION}-recommended\"] // .promos[\"${MC_VERSION}-latest\"]")
      if [[ -z "$RESOLVED_VERSION" || "$RESOLVED_VERSION" == "null" ]]; then
        echo "ERROR: No Forge version found for Minecraft ${MC_VERSION}."
        exit 1
      fi
    fi

    echo "Installing Forge ${MC_VERSION}-${RESOLVED_VERSION}..."
    curl -sSfL -o installer.jar "https://maven.minecraftforge.net/net/minecraftforge/forge/${MC_VERSION}-${RESOLVED_VERSION}/forge-${MC_VERSION}-${RESOLVED_VERSION}-installer.jar"

    java -jar installer.jar --installServer

    ARGS_FILE="libraries/net/minecraftforge/forge/${MC_VERSION}-${RESOLVED_VERSION}/unix_args.txt"
    if [[ -f "$ARGS_FILE" ]]; then
      ln -sf "$ARGS_FILE" unix_args.txt
      echo "Linked unix_args.txt for Forge ${MC_VERSION}-${RESOLVED_VERSION}"
    elif [[ ! -f "${SERVER_JARFILE}" ]]; then
      echo "ERROR: Forge installation produced neither unix_args.txt nor ${SERVER_JARFILE}."
      exit 1
    fi

    rm -f installer.jar installer.jar.log
    ;;

  fabric)
    FABRIC_LOADER=${FORGE_VERSION:-$(curl -sSfL https://meta.fabricmc.net/v2/versions/loader | jq -r '.[0].version')}
    FABRIC_INSTALLER=$(curl -sSfL https://meta.fabricmc.net/v2/versions/installer | jq -r '.[0].version')

    echo "Installing Fabric Loader ${FABRIC_LOADER} for Minecraft ${MC_VERSION}..."
    curl -sSfL -o "${SERVER_JARFILE}" "https://meta.fabricmc.net/v2/versions/loader/${MC_VERSION}/${FABRIC_LOADER}/${FABRIC_INSTALLER}/server/jar"
    ;;

  quilt)
    QUILT_LOADER=${FORGE_VERSION:-$(curl -sSfL https://meta.quiltmc.org/v3/versions/loader | jq -r '.[0].version')}
    QUILT_INSTALLER=$(curl -sSfL https://meta.quiltmc.org/v3/versions/installer | jq -r '.[0].version')

    echo "Installing Quilt Loader ${QUILT_LOADER} for Minecraft ${MC_VERSION}..."
    curl -sSfL -o "${SERVER_JARFILE}" "https://meta.quiltmc.org/v3/versions/loader/${MC_VERSION}/${QUILT_LOADER}/${QUILT_INSTALLER}/server/jar"
    ;;

  *)
    echo "ERROR: Unknown modloader '${MODLOADER}'. Expected: forge, fabric, or quilt."
    exit 1
    ;;
esac

echo "Server installation complete."
