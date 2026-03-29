#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$ROOT_DIR/_ci/tools"

cd "$ROOT_DIR"

latest_shellcheck_tag() {
  local latest_url=""

  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' \
    https://github.com/koalaman/shellcheck/releases/latest)"
  printf '%s\n' "${latest_url##*/}"
}

bootstrap_shellcheck() {
  local version="" os_name="" machine="" archive_name="" archive_path="" extract_dir=""

  version="$(latest_shellcheck_tag)"
  extract_dir="$TOOLS_DIR/shellcheck/$version"
  mkdir -p "$extract_dir"

  if shellcheck_path="$(find "$extract_dir" -type f \( -name 'shellcheck' -o -name 'shellcheck.exe' \) -print -quit)"; then
    if [[ -n "$shellcheck_path" ]]; then
      printf '%s\n' "$shellcheck_path"
      return 0
    fi
  fi

  case "$(uname -s)" in
    Linux)
      os_name="linux"
      case "$(uname -m)" in
        x86_64|amd64) machine="x86_64" ;;
        aarch64|arm64) machine="aarch64" ;;
        *)
          echo "ERROR: Unsupported Linux architecture for shellcheck: $(uname -m)" >&2
          return 1
          ;;
      esac
      archive_name="shellcheck-${version}.${os_name}.${machine}.tar.xz"
      archive_path="$TOOLS_DIR/$archive_name"
      curl -fsSL -o "$archive_path" \
        "https://github.com/koalaman/shellcheck/releases/latest/download/${archive_name}"
      tar -xJf "$archive_path" -C "$extract_dir" --strip-components=1
      rm -f "$archive_path"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      archive_name="shellcheck-${version}.zip"
      archive_path="$TOOLS_DIR/$archive_name"
      curl -fsSL -o "$archive_path" \
        "https://github.com/koalaman/shellcheck/releases/latest/download/${archive_name}"

      if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -ExecutionPolicy Bypass \
          -Command "Expand-Archive -LiteralPath '$archive_path' -DestinationPath '$extract_dir' -Force" >/dev/null
      elif command -v pwsh >/dev/null 2>&1; then
        pwsh -NoProfile -Command \
          "Expand-Archive -LiteralPath '$archive_path' -DestinationPath '$extract_dir' -Force" >/dev/null
      else
        echo "ERROR: Could not find PowerShell to unpack the shellcheck zip." >&2
        return 1
      fi

      rm -f "$archive_path"
      ;;
    *)
      echo "ERROR: Unsupported platform for shellcheck bootstrap: $(uname -s)" >&2
      return 1
      ;;
  esac

  shellcheck_path="$(find "$extract_dir" -type f \( -name 'shellcheck' -o -name 'shellcheck.exe' \) -print -quit)"
  if [[ -z "$shellcheck_path" ]]; then
    echo "ERROR: Failed to locate shellcheck after extracting $archive_name." >&2
    return 1
  fi

  printf '%s\n' "$shellcheck_path"
}

shell_scripts=(
  install.sh
  startup.sh
  update.sh
  .github/scripts/*.sh
)

failed=0

for script_path in "${shell_scripts[@]}"; do
  if LC_ALL=C grep -q $'\r' "$script_path"; then
    echo "ERROR: $script_path contains CRLF line endings." >&2
    failed=1
  fi

  if ! "${BASH:-bash}" -n "$script_path"; then
    failed=1
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK_BIN="$(command -v shellcheck)"
else
  mkdir -p "$TOOLS_DIR"
  echo "shellcheck not found on PATH, downloading the latest release locally..." >&2
  SHELLCHECK_BIN="$(bootstrap_shellcheck)"
fi

"$SHELLCHECK_BIN" "${shell_scripts[@]}"

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
