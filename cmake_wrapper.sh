#!/usr/bin/env bash

set -euox pipefail

export CMAKE_INSTALL_MODE=SYMLINK_OR_COPY

# ninja target
TGT=$1

# -B value place according to meson.build
BUILD_DIR=$5

cmake "${@:1}"

ninja -C "$BUILD_DIR" -j8 "$TGT"
cp "$BUILD_DIR/lib/"* "$BUILD_DIR/"
