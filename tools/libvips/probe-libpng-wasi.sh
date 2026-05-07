#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSION="${LIBPNG_VERSION:-1.6.50}"
WORK="${LIBPNG_PROBE_DIR:-$ROOT/.wasmify/libpng-probe}"
SRC="$WORK/libpng-$VERSION"
PREFIX="$WORK/prefix"
ZLIB_PREFIX="${ZLIB_PREFIX:-$ROOT/.wasmify/zlib-probe/prefix}"
WASI_SDK_PATH="${WASI_SDK_PATH:-$HOME/.config/wasmify/bin/wasi-sdk}"

if [[ ! -x "$WASI_SDK_PATH/bin/clang" ]]; then
  echo "missing wasi-sdk at $WASI_SDK_PATH; run: make wasi-sdk" >&2
  exit 2
fi

if [[ ! -f "$ZLIB_PREFIX/lib/pkgconfig/zlib.pc" ]]; then
  echo "missing zlib WASI prefix at $ZLIB_PREFIX; run: make probe-zlib-wasi" >&2
  exit 2
fi

mkdir -p "$WORK"
if [[ ! -d "$SRC" ]]; then
  curl -L -o "$WORK/libpng.tar.gz" "https://github.com/pnggroup/libpng/archive/refs/tags/v$VERSION.tar.gz"
  tar -C "$WORK" -xf "$WORK/libpng.tar.gz"
fi

cmake -S "$SRC" -B "$WORK/build" \
  -DCMAKE_SYSTEM_NAME=WASI \
  -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_C_COMPILER="$WASI_SDK_PATH/bin/clang" \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasip1 \
  -DCMAKE_AR="$WASI_SDK_PATH/bin/llvm-ar" \
  -DCMAKE_RANLIB="$WASI_SDK_PATH/bin/llvm-ranlib" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-DPNG_SETJMP_NOT_SUPPORTED" \
  -DCMAKE_PREFIX_PATH="$ZLIB_PREFIX" \
  -DZLIB_ROOT="$ZLIB_PREFIX" \
  -DPNG_SHARED=OFF \
  -DPNG_STATIC=ON \
  -DPNG_EXECUTABLES=OFF \
  -DPNG_TESTS=OFF

cmake --build "$WORK/build" --target install --parallel "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
ln -sf libpng.a "$PREFIX/lib/libpng16.a"

echo "$PREFIX"
