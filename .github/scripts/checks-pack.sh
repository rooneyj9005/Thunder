#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKWIZ_BIN="${PACKWIZ_BIN:-packwiz}"
EXPECTED_TAG="${EXPECTED_TAG:-}"
TEST_PACK_URL="${TEST_PACK_URL:-}"

extract_pack_value() {
  local key="$1"
  sed -nE "s/^${key} = \"(.*)\"$/\1/p" "$ROOT_DIR/pack.toml" | head -n 1
}

extract_bcc_value() {
  local key="$1"
  sed -nE "s/^[[:space:]]*${key} = \"(.*)\"$/\1/p" "$ROOT_DIR/config/bcc-common.toml" | head -n 1
}

cd "$ROOT_DIR"

pack_name="$(extract_pack_value name)"
pack_version="$(extract_pack_value version)"
bcc_name="$(extract_bcc_value modpackName)"
bcc_version="$(extract_bcc_value modpackVersion)"
normalised_pack_version="${pack_version#v}"
normalised_bcc_version="${bcc_version#v}"

if [[ -z "$pack_name" || -z "$pack_version" ]]; then
  echo "ERROR: Could not read pack name/version from pack.toml." >&2
  exit 1
fi

if [[ -z "$bcc_name" || -z "$bcc_version" ]]; then
  echo "ERROR: Could not read modpack name/version from config/bcc-common.toml." >&2
  exit 1
fi

if [[ "$pack_name" != "$bcc_name" ]]; then
  echo "ERROR: pack.toml name '$pack_name' does not match config/bcc-common.toml name '$bcc_name'." >&2
  exit 1
fi

if [[ "$normalised_pack_version" != "$normalised_bcc_version" ]]; then
  echo "ERROR: pack.toml version '$pack_version' does not match config/bcc-common.toml version '$bcc_version' after normalising an optional leading v." >&2
  exit 1
fi

if [[ -n "$EXPECTED_TAG" ]]; then
  if [[ "$EXPECTED_TAG" =~ ^v[0-9]+(\.[0-9]+)+$ ]]; then
    if [[ "$EXPECTED_TAG" != "v$normalised_pack_version" ]]; then
      echo "ERROR: Tag '$EXPECTED_TAG' does not match pack version 'v$normalised_pack_version'." >&2
      exit 1
    fi

    # Promoting a release deploys its metadata to Pages, and Pages keeps no
    # history to go back to. A tag numbered below the current stable release
    # would therefore publish older metadata over a newer one and hand every
    # player a downgrade, so refuse it here rather than at the point where
    # someone notices their mods went backwards.
    #
    # A shared runner address routinely has no API budget left, and a busy API
    # is not a reason to fail a build. An unanswerable question is reported and
    # skipped; the check is a floor, not the only thing standing between a
    # mistake and a release.
    previous_tag=""
    if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
      previous_tag="$(
        gh api --paginate "repos/${GITHUB_REPOSITORY}/releases?per_page=100" 2>/dev/null |
          jq -sr --arg current "$EXPECTED_TAG" '
              add
              | map(select(.draft == false and .prerelease == false and .tag_name != $current))
              | .[0].tag_name // empty
            ' 2>/dev/null
      )" || previous_tag=""
    fi

    if [[ -z "$previous_tag" ]]; then
      echo "Info: Skipping the release-order check. No previous stable release was readable from the releases API."
    else
      previous_version="${previous_tag#v}"
      lowest="$(printf '%s\n%s\n' "$normalised_pack_version" "$previous_version" | sort -V | head -n 1)"

      if [[ "$lowest" == "$normalised_pack_version" ]]; then
        echo "ERROR: Tag '$EXPECTED_TAG' is not higher than the current stable release '$previous_tag'. Releasing it would deploy older pack metadata over a newer one." >&2
        exit 1
      fi

      echo "Tag '$EXPECTED_TAG' is higher than the current stable release '$previous_tag'."
    fi
  else
    echo "Info: Skipping tag/version check for non-version tag '$EXPECTED_TAG'."
  fi
fi

for managed_shell in startup.sh functions.sh tools/install.sh tools/update.sh; do
  if LC_ALL=C grep -q $'\r' "$managed_shell"; then
    echo "ERROR: $managed_shell contains CRLF line endings." >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Constants that live in more than one file
#
# The Minecraft and Forge versions and the packwiz host are each written out in
# several places, because a runtime script cannot read pack.toml before it has
# fetched anything. pack.toml is the source of truth and this is the one place
# that says so, so a bump is one edit and then a check that names whatever was
# missed, rather than a grep and a hope.
# ---------------------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to validate pterodactyl.json." >&2
  exit 1
fi

if ! jq empty pterodactyl.json 2>/dev/null; then
  echo "ERROR: pterodactyl.json is not valid JSON. It ships as a release asset, so a broken egg reaches operators." >&2
  jq empty pterodactyl.json || true
  exit 1
fi

egg_default() {
  jq -r --arg name "$1" '
      .variables[]? | select(.env_variable == $name) | .default_value
    ' pterodactyl.json
}

pack_minecraft_version="$(extract_pack_value minecraft)"
pack_forge_version="$(extract_pack_value forge)"

if [[ -z "$pack_minecraft_version" || -z "$pack_forge_version" ]]; then
  echo "ERROR: Could not read the minecraft/forge versions from pack.toml [versions]." >&2
  exit 1
fi

check_egg_default() {
  local name="$1" expected="$2" actual
  actual="$(egg_default "$name")"

  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: pterodactyl.json ${name} default is '${actual}', but pack.toml says '${expected}'." >&2
    exit 1
  fi
}

check_egg_default MC_VERSION "$pack_minecraft_version"
check_egg_default FORGE_VERSION "$pack_forge_version"
check_egg_default PACKWIZ_SIDE server

# Not read from anywhere: Pages serves it and nothing in the repository declares
# it any more, since the CNAME went. Changing the host means changing this line
# and then fixing whatever the check names.
expected_pack_url="https://packwiz.thunder.john.rooney.scot/pack.toml"
check_egg_default PACKWIZ_URL "$expected_pack_url"

for defaulting_file in tools/install.sh tools/install.ps1 tools/update.sh tools/update.ps1 startup.ps1; do
  if ! grep -qF -- "$expected_pack_url" "$defaulting_file"; then
    echo "ERROR: $defaulting_file does not carry the packwiz host default '$expected_pack_url'." >&2
    exit 1
  fi
done

for versioned_file in tools/install.sh tools/install.ps1 tests/client.Dockerfile; do
  if ! grep -qF -- "$pack_minecraft_version" "$versioned_file"; then
    echo "ERROR: $versioned_file does not mention Minecraft $pack_minecraft_version, which pack.toml requires." >&2
    exit 1
  fi

  if ! grep -qF -- "$pack_forge_version" "$versioned_file"; then
    echo "ERROR: $versioned_file does not mention Forge $pack_forge_version, which pack.toml requires." >&2
    exit 1
  fi
done

# The egg curls its own install scripts out of the latest release. If build.yml
# stops uploading one of them, every new server install breaks at the first
# step, and nothing else would catch it before an operator did.
while IFS= read -r egg_asset; do
  [[ -n "$egg_asset" ]] || continue

  if ! grep -qE "(^|[[:space:]/])${egg_asset//./\\.}([[:space:]]|$)" .github/workflows/build.yml; then
    echo "ERROR: The egg fetches '${egg_asset}' from the latest release, but build.yml does not upload it." >&2
    exit 1
  fi
done < <(
  jq -r '.scripts.installation.script' pterodactyl.json |
    grep -oE 'releases/[^ ]*/download/[A-Za-z0-9._-]+' |
    sed 's|.*/||' |
    sort -u
)

# checks-install.sh silently treats a missing side as "both", so a mod with no
# side would install on both sides and nobody would be told. All of them declare
# one today; this is what keeps that true.
mapfile -t missing_side < <(grep -L '^side = ' mods/*.pw.toml || true)

if [[ "${#missing_side[@]}" -gt 0 ]]; then
  echo "ERROR: These mods declare no side:" >&2
  printf '  %s\n' "${missing_side[@]}" >&2
  exit 1
fi

"$PACKWIZ_BIN" refresh

if ! git diff --quiet -- pack.toml index.toml; then
  echo "ERROR: packwiz refresh changed tracked metadata." >&2
  git --no-pager diff -- pack.toml index.toml
  exit 1
fi

mkdir -p tmp
rm -f tmp/Thunder.mrpack
"$PACKWIZ_BIN" modrinth export -o tmp/Thunder.mrpack

if [[ -n "$TEST_PACK_URL" ]]; then
  test_dir="$ROOT_DIR/tmp/tests/update"
  rm -rf "$test_dir"
  mkdir -p "$test_dir"
  # update.sh refuses a plaintext pack host, because over http the attacker who
  # controls the index also controls the hashes it is checked against.
  # TEST_PACK_URL is the local python http.server the workflow starts on the
  # runner's own loopback, so the rule is waived for this one call.
  PACKWIZ_URL="$TEST_PACK_URL" PACKWIZ_SIDE=server PACKWIZ_ALLOW_INSECURE_URL=1 \
    bash "$ROOT_DIR/tools/update.sh" --dir "$test_dir"
  bash "$ROOT_DIR/.github/scripts/checks-install.sh" "$test_dir" server
fi
