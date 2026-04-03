#!/bin/sh

die() {
    printf '%s\n' "ERROR: $*" >&2
    exit 1
}

use_local_java21_if_available() {
    for java_dir in ./jdk-21* ./jre-21*; do
        [ -d "${java_dir}" ] || continue

        java_dir=${java_dir#./}
        JAVA_HOME=${PWD}/${java_dir}
        PATH=${JAVA_HOME}/bin:${PATH}
        export JAVA_HOME PATH
        printf '%s\n' "Using local Java 21 runtime at ${JAVA_HOME}"
        return 0
    done

    return 1
}

java_major_version() {
    java -version 2>&1 | awk -F '"' '/version/ { split($2, parts, "."); if (parts[1] == 1 && parts[2] != "") { print parts[2]; } else { print parts[1]; } exit }'
}

temurin_linux_arch() {
    arch=$(uname -m)

    case ${arch} in
        x86_64|amd64)
            printf '%s\n' "x64"
            ;;
        aarch64|arm64)
            printf '%s\n' "aarch64"
            ;;
        *)
            die "Unsupported Linux architecture for Temurin 21: ${arch}."
            ;;
    esac
}

install_local_java21() {
    arch=$(temurin_linux_arch)
    java_archive="temurin-21-${arch}.tar.gz"

    rm -f "${java_archive}"
    curl -sSfL --connect-timeout 30 --max-time 300 \
        -o "${java_archive}" \
        "https://api.adoptium.net/v3/binary/latest/21/ga/linux/${arch}/jre/hotspot/normal/eclipse"
    tar -xzf "${java_archive}"
    rm -f "${java_archive}"

    # shellcheck disable=SC2310
    if ! use_local_java21_if_available; then
        die "Temurin 21 archive did not contain an expected jdk-21* or jre-21* directory."
    fi
}

ensure_supported_java() {
    major=""

    if command -v java >/dev/null 2>&1; then
        major=$(java_major_version)
        case ${major} in
            17|21)
                return 0
                ;;
            *)
                :
                ;;
        esac
    fi

    # shellcheck disable=SC2310
    if use_local_java21_if_available; then
        major=$(java_major_version)
        case ${major} in
            17|21)
                return 0
                ;;
            *)
                :
                ;;
        esac
    fi

    if [ -n "${major}" ]; then
        printf '%s\n' "Java ${major} found. Switching to local Temurin 21."
    else
        printf '%s\n' "No supported Java runtime found. Downloading local Temurin 21."
    fi

    install_local_java21
    major=$(java_major_version)

    [ "${major}" = "21" ] || die "Java 17 or Java 21 is required; found Java ${major:-unknown}."
}

validate_boolean_value() {
    name=$1
    value=$2

    case ${value} in
        true|1|yes|false|0|no|"")
            return 0
            ;;
        *)
            die "${name} must be one of: true, false, 1, 0, yes, or no."
            ;;
    esac
}

validate_non_negative_mib() {
    name=$1
    value=$2

    [ -n "${value}" ] || return 0

    case ${value} in
        *[!0-9]*|"")
            die "${name} must be a non-negative integer in MiB."
            ;;
        *)
            return 0
            ;;
    esac
}
