#!/usr/bin/env bash

set -euox pipefail

export CMAKE_INSTALL_MODE=SYMLINK_OR_COPY

# ninja target
TGT=$1

# result dir
COPY_TO=$2

# -B value place according to meson.build
BUILD_DIR=$6

cmake "${@:2}"

ninja -C "$BUILD_DIR" -j8 "$TGT"
cp "$BUILD_DIR/lib/"* "$COPY_TO/"
