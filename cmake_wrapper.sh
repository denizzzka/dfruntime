#!/usr/bin/env bash

set -euox pipefail

export CMAKE_INSTALL_MODE=SYMLINK_OR_COPY

# -B value place according to meson.build
BUILD_DIR=$4

cmake "$@"

ninja -C "$BUILD_DIR" -j8 druntime-ldc
cp "$BUILD_DIR/lib/"* "$BUILD_DIR/"
