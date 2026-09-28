#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd "${SCRIPT_DIR}/../.." && pwd)
TOOLS_DIR=${ROOT_DIR}/tmp/tools
CR_CHARACTER=$(printf '\r')

# Pinned, so a lint result depends on the tree and not on whichever shellcheck
# a runner image happens to carry. One already on the PATH is used only when it
# is this same version. Bump the version and the three hashes together; each
# hash is the SHA-256 of the archive GitHub publishes for that release.
SHELLCHECK_VERSION=v0.11.0

cd "${ROOT_DIR}"

shellcheck_archive_sha256() {
    case $1 in
        "shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.xz")
            printf '%s\n' "8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
            ;;
        "shellcheck-${SHELLCHECK_VERSION}.linux.aarch64.tar.xz")
            printf '%s\n' "12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588"
            ;;
        "shellcheck-${SHELLCHECK_VERSION}.zip")
            printf '%s\n' "8a4e35ab0b331c85d73567b12f2a444df187f483e5079ceffa6bda1faa2e740e"
            ;;
        *)
            return 1
            ;;
    esac
}

fetch_shellcheck_archive() {
    archive_name=$1
    archive_path=$2

    expected=$(shellcheck_archive_sha256 "${archive_name}") || {
        printf '%s\n' "ERROR: No pinned hash for ${archive_name}." >&2
        return 1
    }

    curl -fsSL --retry 3 --retry-delay 2 -o "${archive_path}" \
        "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${archive_name}"

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "${archive_path}" | cut -d ' ' -f 1)
    else
        actual=$(shasum -a 256 "${archive_path}" | cut -d ' ' -f 1)
    fi

    if [ "${actual}" != "${expected}" ]; then
        rm -f "${archive_path}"
        printf '%s\n' "ERROR: ${archive_name} did not match its pinned SHA-256." >&2
        return 1
    fi
}

path_shellcheck_is_pinned() {
    command -v shellcheck >/dev/null 2>&1 || return 1
    [ "$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')" = "${SHELLCHECK_VERSION#v}" ]
}

native_path() {
    path=$1

    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "${path}"
        return 0
    fi

    printf '%s\n' "${path}"
}

extract_zip_archive() {
    archive_path=$1
    extract_dir=$2

    if command -v unzip >/dev/null 2>&1; then
        unzip -q "${archive_path}" -d "${extract_dir}"
        return 0
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
        archive_path_native=$(native_path "${archive_path}")
        extract_dir_native=$(native_path "${extract_dir}")
        powershell.exe -NoProfile -ExecutionPolicy Bypass \
            -Command "Expand-Archive -LiteralPath '${archive_path_native}' -DestinationPath '${extract_dir_native}' -Force" >/dev/null
        return 0
    fi

    if command -v pwsh >/dev/null 2>&1; then
        archive_path_native=$(native_path "${archive_path}")
        extract_dir_native=$(native_path "${extract_dir}")
        pwsh -NoProfile -Command \
            "Expand-Archive -LiteralPath '${archive_path_native}' -DestinationPath '${extract_dir_native}' -Force" >/dev/null
        return 0
    fi

    printf '%s\n' "ERROR: Could not find unzip or PowerShell to unpack ${archive_path##*/}." >&2
    return 1
}

bootstrap_shellcheck() {
    version=${SHELLCHECK_VERSION}
    extract_dir="${TOOLS_DIR}/shellcheck/${version}"
    mkdir -p "${extract_dir}"

    shellcheck_path=$(find "${extract_dir}" -type f \( -name 'shellcheck' -o -name 'shellcheck.exe' \) -print | sed -n '1p')
    if [ -n "${shellcheck_path}" ]; then
        printf '%s\n' "${shellcheck_path}"
        return 0
    fi

    printf '%s\n' "Fetching shellcheck ${version} into tmp/tools..." >&2

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
            fetch_shellcheck_archive "${archive_name}" "${archive_path}"
            tar -xJf "${archive_path}" -C "${extract_dir}" --strip-components=1
            rm -f "${archive_path}"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            archive_name="shellcheck-${version}.zip"
            archive_path="${TOOLS_DIR}/${archive_name}"
            fetch_shellcheck_archive "${archive_name}" "${archive_path}"
            extract_zip_archive "${archive_path}" "${extract_dir}"
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

# The shebang decides the dialect, not the directory a script happens to sit in.
# The split used to be by folder, which checked this script as bash because of
# its neighbours even though it declares POSIX sh, so a bashism in here would
# have passed.
syntax_checker_for() {
    case $(head -n 1 "$1") in
        *bash)
            printf '%s\n' "${BASH:-bash}"
            ;;
        *)
            printf '%s\n' "sh"
            ;;
    esac
}

# One list, held in the positional parameters so the globs expand once and the
# paths reach shellcheck as separate arguments without being re-split.
set -- tools/install.sh startup.sh tools/update.sh functions.sh tests/*.sh .github/scripts/*.sh

failed=0

for script_path in "$@"; do
    [ -f "${script_path}" ] || continue
    check_line_endings "${script_path}"

    checker=$(syntax_checker_for "${script_path}")
    if ! "${checker}" -n "${script_path}"; then
        failed=1
    fi
done

if path_shellcheck_is_pinned; then
    SHELLCHECK_BIN=$(command -v shellcheck)
else
    mkdir -p "${TOOLS_DIR}"
    SHELLCHECK_BIN=$(bootstrap_shellcheck)
fi

# -x follows sourced files, which is what lets shellcheck see functions.sh from
# the scripts that source it instead of reporting every call into it. No -s
# here either: each script's own shebang picks its dialect.
"${SHELLCHECK_BIN}" -x "$@"

if [ "${failed}" -ne 0 ]; then
    exit 1
fi
