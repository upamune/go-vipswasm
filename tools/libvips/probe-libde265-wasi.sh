#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBDE265_VERSION:-1.0.16}"
WORK="${LIBDE265_PROBE_DIR:-$ROOT/.wasmify/libde265-probe}"
SRC="$WORK/libde265-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libde265.tar.gz" "https://github.com/strukturag/libde265/releases/download/v$VERSION/libde265-$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libde265.tar.gz"
fi

if ! grep -q "VIPSWASM_WASI_NO_ENCODER_OBJECTS" "$SRC/libde265/CMakeLists.txt"; then
  perl -0pi -e 's/add_subdirectory \(encoder\)/# VIPSWASM_WASI_NO_ENCODER_OBJECTS\nif (NOT CMAKE_SYSTEM_NAME STREQUAL "WASI")\n  add_subdirectory (encoder)\nendif()/' "$SRC/libde265/CMakeLists.txt"
fi

cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_CXX_COMPILER="$WASI_SDK_PATH/bin/clang++" \
  -DCMAKE_CXX_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-D_WASI_EMULATED_SIGNAL" \
  -DCMAKE_CXX_FLAGS="-D_WASI_EMULATED_SIGNAL -fno-exceptions" \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_DECODER=OFF \
  -DENABLE_ENCODER=OFF \
  -DENABLE_SDL=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
