#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
CMAKE_BIN="${CMAKE_BIN:-}"
MACOS_SDK_PATH="${MACOS_SDK_PATH:-}"

find_cmake() {
    if [ -n "$CMAKE_BIN" ]; then
        printf '%s\n' "$CMAKE_BIN"
        return 0
    fi

    if command -v cmake >/dev/null 2>&1; then
        command -v cmake
        return 0
    fi

    if command -v brew >/dev/null 2>&1 && brew list --formula cmake >/dev/null 2>&1; then
        printf '%s\n' "$(brew --prefix cmake)/bin/cmake"
        return 0
    fi

    return 1
}

find_mysql_prefix() {
    local formula

    for formula in \
        mysql@8.4 \
        mysql-client@8.4 \
        mysql \
        mysql-client
    do
        if brew --prefix "$formula" >/dev/null 2>&1; then
            brew --prefix "$formula"
            return 0
        fi
    done

    return 1
}

find_mysql_include_dir() {
    local prefix

    if [ -n "${MYSQL_INCLUDE_DIR:-}" ]; then
        printf '%s\n' "$MYSQL_INCLUDE_DIR"
        return 0
    fi

    if ! prefix="$(find_mysql_prefix)"; then
        return 1
    fi

    if [ -f "$prefix/include/mysql/mysql.h" ]; then
        printf '%s\n' "$prefix/include"
        return 0
    fi

    return 1
}

find_mysql_library() {
    local prefix
    local candidate

    if [ -n "${MYSQL_LIBRARY:-}" ]; then
        printf '%s\n' "$MYSQL_LIBRARY"
        return 0
    fi

    if ! prefix="$(find_mysql_prefix)"; then
        return 1
    fi

    for candidate in \
        "$prefix/lib/libmysqlclient.dylib" \
        "$prefix/lib/libmysqlclient.a"
    do
        if [ -e "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

find_fuse_include_dir() {
    local candidate

    if [ -n "${FUSE_INCLUDE_DIRS:-}" ]; then
        printf '%s\n' "$FUSE_INCLUDE_DIRS"
        return 0
    fi

    for candidate in \
        /usr/local/include \
        /opt/homebrew/include
    do
        if [ -f "$candidate/fuse.h" ] || [ -f "$candidate/fuse/fuse.h" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

find_fuse_library() {
    local candidate

    if [ -n "${FUSE_LIBRARIES:-}" ]; then
        printf '%s\n' "$FUSE_LIBRARIES"
        return 0
    fi

    for candidate in \
        /usr/local/lib/libfuse.dylib \
        /opt/homebrew/lib/libfuse.dylib
    do
        if [ -e "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

find_macos_sdk_path() {
    if [ -n "$MACOS_SDK_PATH" ]; then
        printf '%s\n' "$MACOS_SDK_PATH"
        return 0
    fi

    if command -v xcrun >/dev/null 2>&1; then
        xcrun --show-sdk-path
        return 0
    fi

    return 1
}

find_libm_include_dir() {
    local sdk_path

    if [ -n "${LibM_INCLUDES:-}" ]; then
        printf '%s\n' "$LibM_INCLUDES"
        return 0
    fi

    if ! sdk_path="$(find_macos_sdk_path)"; then
        return 1
    fi

    if [ -f "$sdk_path/usr/include/math.h" ]; then
        printf '%s\n' "$sdk_path/usr/include"
        return 0
    fi

    return 1
}

find_libm_library() {
    local sdk_path

    if [ -n "${LibM_LIBRARY:-}" ]; then
        printf '%s\n' "$LibM_LIBRARY"
        return 0
    fi

    if ! sdk_path="$(find_macos_sdk_path)"; then
        return 1
    fi

    if [ -e "$sdk_path/usr/lib/libm.tbd" ]; then
        printf '%s\n' "$sdk_path/usr/lib/libm.tbd"
        return 0
    fi

    return 1
}

if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required on macOS to locate dependencies automatically" >&2
    exit 1
fi

if ! CMAKE_BIN="$(find_cmake)"; then
    echo "error: cmake is required but was not found in PATH" >&2
    echo "hint: install it with 'brew install cmake'" >&2
    exit 1
fi

if ! MYSQL_INCLUDE_DIR="$(find_mysql_include_dir)"; then
    echo "error: could not find MySQL headers; set MYSQL_INCLUDE_DIR explicitly" >&2
    exit 1
fi

if ! MYSQL_LIBRARY="$(find_mysql_library)"; then
    echo "error: could not find libmysqlclient; set MYSQL_LIBRARY explicitly" >&2
    exit 1
fi

if ! FUSE_INCLUDE_DIRS="$(find_fuse_include_dir)"; then
    echo "error: could not find macFUSE headers; set FUSE_INCLUDE_DIRS explicitly" >&2
    exit 1
fi

if ! FUSE_LIBRARIES="$(find_fuse_library)"; then
    echo "error: could not find libfuse.dylib; set FUSE_LIBRARIES explicitly" >&2
    exit 1
fi

if ! LibM_INCLUDES="$(find_libm_include_dir)"; then
    echo "error: could not find LibM headers in the active macOS SDK; set LibM_INCLUDES explicitly" >&2
    exit 1
fi

if ! LibM_LIBRARY="$(find_libm_library)"; then
    echo "error: could not find libm in the active macOS SDK; set LibM_LIBRARY explicitly" >&2
    exit 1
fi

export MYSQLFS_BUILD_DIR="${MYSQLFS_BUILD_DIR:-$SOURCE_DIR/build-macos}"
export CMAKE_BIN
export MYSQL_INCLUDE_DIR
export MYSQL_LIBRARY
export FUSE_INCLUDE_DIRS
export FUSE_LIBRARIES
export LibM_INCLUDES
export LibM_LIBRARY

exec "$SCRIPT_DIR/build.sh" "$@"
