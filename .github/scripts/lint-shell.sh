#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd "${SCRIPT_DIR}/../.." && pwd)
TOOLS_DIR=${ROOT_DIR}/_ci/tools
CR_CHARACTER=$(printf '\r')

cd "${ROOT_DIR}"

latest_shellcheck_tag() {
    latest_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' \
        "https://github.com/koalaman/shellcheck/releases/latest")
    printf '%s\n' "${latest_url##*/}"
}

bootstrap_shellcheck() {
    version=$(latest_shellcheck_tag)
    extract_dir="${TOOLS_DIR}/shellcheck/${version}"
    mkdir -p "${extract_dir}"

    shellcheck_path=$(find "${extract_dir}" -type f \( -name 'shellcheck' -o -name 'shellcheck.exe' \) -print | sed -n '1p')
    if [ -n "${shellcheck_path}" ]; then
        printf '%s\n' "${shellcheck_path}"
        return 0
    fi

    case $(uname -s) in
        Linux)
            os_name="linux"
            case $(uname -m) in
                x86_64|amd64)
                    machine="x86_64"
                    ;;
                aarch64|arm64)
                    machine="aarch64"
                    ;;
                *)
                    printf '%s\n' "ERROR: Unsupported Linux architecture for shellcheck: $(uname -m)" >&2
                    return 1
                    ;;
            esac
            archive_name="shellcheck-${version}.${os_name}.${machine}.tar.xz"
            archive_path="${TOOLS_DIR}/${archive_name}"
            curl -fsSL -o "${archive_path}" \
                "https://github.com/koalaman/shellcheck/releases/latest/download/${archive_name}"
            tar -xJf "${archive_path}" -C "${extract_dir}" --strip-components=1
            rm -f "${archive_path}"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            archive_name="shellcheck-${version}.zip"
            archive_path="${TOOLS_DIR}/${archive_name}"
            curl -fsSL -o "${archive_path}" \
                "https://github.com/koalaman/shellcheck/releases/latest/download/${archive_name}"

            if command -v powershell.exe >/dev/null 2>&1; then
                powershell.exe -NoProfile -ExecutionPolicy Bypass \
                    -Command "Expand-Archive -LiteralPath '${archive_path}' -DestinationPath '${extract_dir}' -Force" >/dev/null
            elif command -v pwsh >/dev/null 2>&1; then
                pwsh -NoProfile -Command \
                    "Expand-Archive -LiteralPath '${archive_path}' -DestinationPath '${extract_dir}' -Force" >/dev/null
            else
                printf '%s\n' "ERROR: Could not find PowerShell to unpack the shellcheck zip." >&2
                return 1
            fi

            rm -f "${archive_path}"
            ;;
        *)
            printf '%s\n' "ERROR: Unsupported platform for shellcheck bootstrap: $(uname -s)" >&2
            return 1
            ;;
    esac

    shellcheck_path=$(find "${extract_dir}" -type f \( -name 'shellcheck' -o -name 'shellcheck.exe' \) -print | sed -n '1p')
    if [ -z "${shellcheck_path}" ]; then
        printf '%s\n' "ERROR: Failed to locate shellcheck after extracting ${archive_name}." >&2
        return 1
    fi

    printf '%s\n' "${shellcheck_path}"
}

check_line_endings() {
    script_path=$1

    if LC_ALL=C grep -q "${CR_CHARACTER}" "${script_path}"; then
        printf '%s\n' "ERROR: ${script_path} contains CRLF line endings." >&2
        failed=1
    fi
}

failed=0

for script_path in install.sh startup.sh update.sh runtime-common.sh; do
    check_line_endings "${script_path}"

    if ! sh -n "${script_path}"; then
        failed=1
    fi
done

for script_path in .github/scripts/*.sh; do
    [ -f "${script_path}" ] || continue
    check_line_endings "${script_path}"

    if ! "${BASH:-bash}" -n "${script_path}"; then
        failed=1
    fi
done

if command -v shellcheck >/dev/null 2>&1; then
    SHELLCHECK_BIN=$(command -v shellcheck)
else
    mkdir -p "${TOOLS_DIR}"
    printf '%s\n' "shellcheck not found on PATH, downloading the latest release locally..." >&2
    SHELLCHECK_BIN=$(bootstrap_shellcheck)
fi

"${SHELLCHECK_BIN}" -s sh install.sh startup.sh update.sh runtime-common.sh
"${SHELLCHECK_BIN}" -s bash .github/scripts/*.sh

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
