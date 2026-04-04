#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR"
BUILD_DIR="${MYSQLFS_BUILD_DIR:-$SOURCE_DIR/build}"
CMAKE_BIN="${CMAKE_BIN:-}"

find_cmake() {
    if [ -n "$CMAKE_BIN" ]; then
        printf '%s\n' "$CMAKE_BIN"
        return 0
    fi

    if command -v cmake >/dev/null 2>&1; then
        command -v cmake
        return 0
    fi

    return 1
}

find_multiarch_triplet() {
    local compiler
    local triplet

    for compiler in "${CC:-}" cc gcc clang; do
        if [ -z "$compiler" ] || ! command -v "$compiler" >/dev/null 2>&1; then
            continue
        fi

        triplet="$("$compiler" -print-multiarch 2>/dev/null || true)"
        if [ -n "$triplet" ] && [ "$triplet" != "." ]; then
            printf '%s\n' "$triplet"
            return 0
        fi
    done

    return 1
}

library_search_paths() {
    local triplet

    if triplet="$(find_multiarch_triplet)"; then
        printf '%s\n' "/usr/lib/$triplet"
        printf '%s\n' "/lib/$triplet"
    fi

    printf '%s\n' /usr/local/lib
    printf '%s\n' /usr/lib
    printf '%s\n' /usr/lib64
    printf '%s\n' /lib
    printf '%s\n' /lib64
}

first_existing_path() {
    local candidate

    for candidate in "$@"; do
        if [ -e "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

find_library_in_paths() {
    local library_name="$1"
    local directory

    while IFS= read -r directory; do
        [ -n "$directory" ] || continue

        if [ -e "$directory/$library_name" ]; then
            printf '%s\n' "$directory/$library_name"
            return 0
        fi
    done < <(library_search_paths)

    return 1
}

extract_first_include_dir() {
    local token

    for token in "$@"; do
        case "$token" in
            -I*)
                printf '%s\n' "${token#-I}"
                return 0
                ;;
        esac
    done

    return 1
}

normalize_component_include_dir() {
    local candidate="$1"
    local component="$2"
    local header="$3"

    if [ -f "$candidate/$component/$header" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [ -f "$candidate/$header" ]; then
        printf '%s\n' "$(dirname "$candidate")"
        return 0
    fi

    return 1
}

extract_first_library_dir() {
    local token

    for token in "$@"; do
        case "$token" in
            -L*)
                printf '%s\n' "${token#-L}"
                return 0
                ;;
        esac
    done

    return 1
}

find_mysql_include_dir() {
    local mysql_includes
    local include_dir

    if [ -n "${MYSQL_INCLUDE_DIR:-}" ]; then
        printf '%s\n' "$MYSQL_INCLUDE_DIR"
        return 0
    fi

    if command -v mysql_config >/dev/null 2>&1; then
        read -r -a mysql_includes <<<"$(mysql_config --include)"
        if include_dir="$(extract_first_include_dir "${mysql_includes[@]}")"; then
            if normalize_component_include_dir "$include_dir" "mysql" "mysql.h"; then
                return 0
            fi
        fi
    fi

    include_dir="$(first_existing_path \
        /usr/local/include/mysql \
        /usr/include/mysql)"
    normalize_component_include_dir "$include_dir" "mysql" "mysql.h"
}

find_mysql_library() {
    local mysql_libs
    local libdir

    if [ -n "${MYSQL_LIBRARY:-}" ]; then
        printf '%s\n' "$MYSQL_LIBRARY"
        return 0
    fi

    if command -v mysql_config >/dev/null 2>&1; then
        read -r -a mysql_libs <<<"$(mysql_config --libs)"
        if libdir="$(extract_first_library_dir "${mysql_libs[@]}")"; then
            if first_existing_path \
                "$libdir/libmysqlclient.so" \
                "$libdir/libmysqlclient.a" \
                "$libdir/mysql/libmysqlclient.so" \
                "$libdir/mysql/libmysqlclient.a"; then
                return 0
            fi
        fi
    fi

    if find_library_in_paths "libmysqlclient.so"; then
        return 0
    fi

    if find_library_in_paths "libmysqlclient.a"; then
        return 0
    fi

    first_existing_path \
        /usr/local/lib/mysql/libmysqlclient.so \
        /usr/local/lib/mysql/libmysqlclient.a
}

find_fuse_include_dir() {
    local fuse_includes
    local include_dir

    if [ -n "${FUSE_INCLUDE_DIRS:-}" ]; then
        printf '%s\n' "$FUSE_INCLUDE_DIRS"
        return 0
    fi

    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists fuse; then
        read -r -a fuse_includes <<<"$(pkg-config --cflags-only-I fuse)"
        if include_dir="$(extract_first_include_dir "${fuse_includes[@]}")"; then
            if normalize_component_include_dir "$include_dir" "fuse" "fuse.h"; then
                return 0
            fi
        fi
    fi

    include_dir="$(first_existing_path \
        /usr/local/include \
        /usr/include)"
    normalize_component_include_dir "$include_dir" "fuse" "fuse.h"
}

find_fuse_library() {
    local fuse_libs
    local libdir

    if [ -n "${FUSE_LIBRARIES:-}" ]; then
        printf '%s\n' "$FUSE_LIBRARIES"
        return 0
    fi

    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists fuse; then
        read -r -a fuse_libs <<<"$(pkg-config --libs-only-L fuse)"
        if libdir="$(extract_first_library_dir "${fuse_libs[@]}")"; then
            if first_existing_path \
                "$libdir/libfuse.so" \
                "$libdir/libfuse.a"; then
                return 0
            fi
        fi
    fi

    if find_library_in_paths "libfuse.so"; then
        return 0
    fi

    find_library_in_paths "libfuse.a"
}

find_libm_include_dir() {
    if [ -n "${LibM_INCLUDES:-}" ]; then
        printf '%s\n' "$LibM_INCLUDES"
        return 0
    fi

    first_existing_path \
        /usr/include \
        /usr/local/include
}

find_libm_library() {
    if [ -n "${LibM_LIBRARY:-}" ]; then
        printf '%s\n' "$LibM_LIBRARY"
        return 0
    fi

    if find_library_in_paths "libm.so"; then
        return 0
    fi

    find_library_in_paths "libm.a"
}

if ! CMAKE_BIN="$(find_cmake)"; then
    echo "error: cmake is required but was not found in PATH" >&2
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
    echo "error: could not find FUSE headers; set FUSE_INCLUDE_DIRS explicitly" >&2
    exit 1
fi

if ! FUSE_LIBRARIES="$(find_fuse_library)"; then
    echo "error: could not find libfuse; set FUSE_LIBRARIES explicitly" >&2
    exit 1
fi

if ! LibM_INCLUDES="$(find_libm_include_dir)"; then
    echo "error: could not find LibM headers; set LibM_INCLUDES explicitly" >&2
    exit 1
fi

if ! LibM_LIBRARY="$(find_libm_library)"; then
    echo "error: could not find libm; set LibM_LIBRARY explicitly" >&2
    exit 1
fi

mkdir -p "$BUILD_DIR"

echo "Configuring mysqlfs"
echo "  source:        $SOURCE_DIR"
echo "  build:         $BUILD_DIR"
echo "  cmake:         $CMAKE_BIN"
echo "  mysql headers: $MYSQL_INCLUDE_DIR"
echo "  mysql library: $MYSQL_LIBRARY"
echo "  fuse headers:  $FUSE_INCLUDE_DIRS"
echo "  fuse library:  $FUSE_LIBRARIES"
echo "  libm headers:  $LibM_INCLUDES"
echo "  libm library:  $LibM_LIBRARY"

cmake_args=(
    -S "$SOURCE_DIR"
    -B "$BUILD_DIR"
    -DMYSQL_INCLUDE_DIR="$MYSQL_INCLUDE_DIR"
    -DMYSQL_LIBRARY="$MYSQL_LIBRARY"
    -DFUSE_INCLUDE_DIRS="$FUSE_INCLUDE_DIRS"
    -DFUSE_LIBRARIES="$FUSE_LIBRARIES"
    -DLibM_INCLUDES="$LibM_INCLUDES"
    -DLibM_LIBRARY="$LibM_LIBRARY"
)

if [ "$#" -gt 0 ]; then
    cmake_args+=("$@")
fi

"$CMAKE_BIN" "${cmake_args[@]}"
"$CMAKE_BIN" --build "$BUILD_DIR"
