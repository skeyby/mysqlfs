#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

BUILD_DIR=${MYSQLFS_BUILD_DIR:-"$REPO_ROOT/build"}
PREFIX=${MYSQLFS_PKG_PREFIX:-/usr/local}
PKG_NAME=${MYSQLFS_PKG_NAME:-mysqlfs}
PKG_VERSION=${MYSQLFS_PKG_VERSION:-}
PKG_MAINTAINER=${MYSQLFS_PKG_MAINTAINER:-andrea@brancatelli.it}
PKG_ORIGIN=${MYSQLFS_PKG_ORIGIN:-sysutils/mysqlfs}
PKG_COMMENT=${MYSQLFS_PKG_COMMENT:-FUSE filesystem backed by MySQL or MariaDB}
PKG_WWW=${MYSQLFS_PKG_WWW:-https://github.com/skeyby/mysqlfs}

STAGE_DIR="$BUILD_DIR/freebsd-pkgroot"
METADATA_DIR="$BUILD_DIR/freebsd-metadata"
OUTPUT_DIR="$BUILD_DIR/freebsd-dist"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command '$1' not found in PATH" >&2
        exit 1
    fi
}

detect_version() {
    if [ -n "$PKG_VERSION" ]; then
        printf '%s\n' "$PKG_VERSION"
        return 0
    fi

    if command -v git >/dev/null 2>&1; then
        PKG_VERSION=$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || true)
        if [ -n "$PKG_VERSION" ]; then
            printf '%s\n' "$PKG_VERSION"
            return 0
        fi
    fi

    printf '%s\n' "1.0.2"
}

pkg_dep_version() {
    if ! pkg query '%v' "$1" 2>/dev/null; then
        echo "error: required FreeBSD package '$1' is not installed" >&2
        exit 1
    fi
}

prepare_build() {
    require_command cmake
    require_command pkg

    if [ ! -x "$REPO_ROOT/build.sh" ]; then
        echo "error: build.sh not found at $REPO_ROOT/build.sh" >&2
        exit 1
    fi

    MYSQLFS_BUILD_DIR="$BUILD_DIR" "$REPO_ROOT/build.sh"
}

stage_files() {
    rm -rf "$STAGE_DIR" "$METADATA_DIR" "$OUTPUT_DIR"
    mkdir -p "$STAGE_DIR" "$METADATA_DIR" "$OUTPUT_DIR"

    DESTDIR="$STAGE_DIR" cmake --install "$BUILD_DIR" --prefix "$PREFIX"

    mkdir -p "$STAGE_DIR$PREFIX/share/doc/mysqlfs"
    cp "$REPO_ROOT/README.md" "$STAGE_DIR$PREFIX/share/doc/mysqlfs/README.md"
    cp "$REPO_ROOT/docs/ChangeLog.md" "$STAGE_DIR$PREFIX/share/doc/mysqlfs/ChangeLog.md"
    cp "$REPO_ROOT/docs/COPYING" "$STAGE_DIR$PREFIX/share/doc/mysqlfs/COPYING"
}

write_metadata() {
    local version
    local fuse_version
    local mysql_client_version

    version=$(detect_version)
    fuse_version=$(pkg_dep_version fusefs-libs)
    mysql_client_version=$(pkg_dep_version mysql80-client)

    cp "$SCRIPT_DIR/+DESC" "$METADATA_DIR/+DESC"
    cp "$SCRIPT_DIR/+DISPLAY" "$METADATA_DIR/+DISPLAY"

    cat >"$METADATA_DIR/+MANIFEST" <<EOF
name: ${PKG_NAME}
version: "${version}"
origin: ${PKG_ORIGIN}
comment: "${PKG_COMMENT}"
maintainer: ${PKG_MAINTAINER}
www: "${PKG_WWW}"
prefix: ${PREFIX}
desc: <<EOD
$(cat "$SCRIPT_DIR/+DESC")
EOD
licenses: [ "GPLv2" ]
deps: {
  fusefs-libs: { origin: "filesystems/fusefs-libs", version: "${fuse_version}" },
  mysql80-client: { origin: "databases/mysql80-client", version: "${mysql_client_version}" }
}
EOF
}

create_package() {
    pkg create -r "$STAGE_DIR" -m "$METADATA_DIR" -o "$OUTPUT_DIR"
    echo
    echo "Package created under:"
    echo "  $OUTPUT_DIR"
}

prepare_build
stage_files
write_metadata
create_package
