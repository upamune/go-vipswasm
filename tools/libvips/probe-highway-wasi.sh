#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${HIGHWAY_VERSION:-1.2.0}"
WORK="${HIGHWAY_PROBE_DIR:-$ROOT/.wasmify/highway-probe}"
SRC="$WORK/highway-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/highway.tar.gz" "https://github.com/google/highway/archive/refs/tags/$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/highway.tar.gz"
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
  -DCMAKE_C_FLAGS="-mno-atomics" \
  -DCMAKE_CXX_FLAGS="-mno-atomics" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DHWY_ENABLE_CONTRIB=OFF \
  -DHWY_ENABLE_EXAMPLES=OFF \
  -DHWY_ENABLE_TESTS=OFF \
  -DHWY_ENABLE_INSTALL=ON

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
