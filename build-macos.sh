#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
BUILD_DIR="${MYSQLFS_BUILD_DIR:-$SOURCE_DIR/build-macos}"
CMAKE_BIN="${CMAKE_BIN:-}"

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

    if [ -d "$prefix/include/mysql" ]; then
        printf '%s\n' "$prefix/include/mysql"
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

if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is required on macOS to locate dependencies automatically" >&2
    exit 1
fi

if [ -z "$CMAKE_BIN" ]; then
    if command -v cmake >/dev/null 2>&1; then
        CMAKE_BIN="$(command -v cmake)"
    elif brew list --formula cmake >/dev/null 2>&1; then
        CMAKE_BIN="$(brew --prefix cmake)/bin/cmake"
    fi
fi

if [ ! -x "$CMAKE_BIN" ]; then
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

mkdir -p "$BUILD_DIR"

echo "Configuring mysqlfs for macOS"
echo "  source:        $SOURCE_DIR"
echo "  build:         $BUILD_DIR"
echo "  cmake:         $CMAKE_BIN"
echo "  mysql headers: $MYSQL_INCLUDE_DIR"
echo "  mysql library: $MYSQL_LIBRARY"
echo "  fuse headers:  $FUSE_INCLUDE_DIRS"
echo "  fuse library:  $FUSE_LIBRARIES"

"$CMAKE_BIN" \
    -S "$SOURCE_DIR" \
    -B "$BUILD_DIR" \
    -DMYSQL_INCLUDE_DIR="$MYSQL_INCLUDE_DIR" \
    -DMYSQL_LIBRARY="$MYSQL_LIBRARY" \
    -DFUSE_INCLUDE_DIRS="$FUSE_INCLUDE_DIRS" \
    -DFUSE_LIBRARIES="$FUSE_LIBRARIES" \
    "${@}"

"$CMAKE_BIN" --build "$BUILD_DIR"
