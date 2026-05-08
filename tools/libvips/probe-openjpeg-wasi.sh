#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${OPENJPEG_VERSION:-2.5.3}"
WORK="${OPENJPEG_PROBE_DIR:-$ROOT/.wasmify/openjpeg-probe}"
SRC="$WORK/openjpeg-$VERSION"
PREFIX="$WORK/prefix"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
LIBPNG_PREFIX="${LIBPNG_PREFIX:-$ROOT/.wasmify/libpng-probe/prefix}"
LIBTIFF_PREFIX="${LIBTIFF_PREFIX:-$ROOT/.wasmify/libtiff-probe/prefix}"
LIBJPEG_PREFIX="${LIBJPEG_PREFIX:-$ROOT/.wasmify/libjpeg-probe/prefix}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/openjpeg.tar.gz" "https://github.com/uclouvain/openjpeg/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/openjpeg.tar.gz"
fi

export PKG_CONFIG_PATH="$ZLIB_PREFIX/lib/pkgconfig:$LIBPNG_PREFIX/lib/pkgconfig:$LIBTIFF_PREFIX/lib/pkgconfig:$LIBJPEG_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$ZLIB_PREFIX;$LIBPNG_PREFIX;$LIBTIFF_PREFIX;$LIBJPEG_PREFIX" \
  -DCMAKE_C_FLAGS="-mno-atomics -D_WASI_EMULATED_PROCESS_CLOCKS" \
  -DCMAKE_EXE_LINKER_FLAGS="-lwasi-emulated-process-clocks" \
  -DCMAKE_SHARED_LINKER_FLAGS="-lwasi-emulated-process-clocks" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_CODEC=OFF \
  -DBUILD_TESTING=OFF \
  -DBUILD_DOC=OFF \
  -DBUILD_PKGCONFIG_FILES=ON \
  -DBUILD_THIRDPARTY=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "$PREFIX"
